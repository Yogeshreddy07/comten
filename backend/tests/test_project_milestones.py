"""Module milestones use approved hours and atomic once-only markers."""
from concurrent.futures import ThreadPoolExecutor
import pytest
from google.cloud.firestore_v1.base_query import FieldFilter
from app.store import db, get
from test_project_lifecycle import graph, create


def setup_project(graph, estimate=90):
    client, put, lead, employee, peer, _, _, _ = graph
    pid, mid = create(graph)
    db.collection('modules').document(str(mid)).update({'estimatedMinutes': estimate, 'status': 'IN_PROGRESS'})
    other = mid + 50
    put('modules', other, {'projectId': pid, 'projectName': 'Synthetic lifecycle',
        'projectCode': 'TEST', 'moduleName': 'Other', 'active': True, 'status': 'IN_PROGRESS',
        'estimatedMinutes': estimate, 'teamLeadId': lead, 'memberIds': [lead, peer]})
    for offset, role in ((60, 'CAPTAIN'), (61, 'PROJECT_CONTROLLER')):
        put('employees', lead + offset, {'role': role, 'active': True})
    put('employees', lead + 62, {'role': 'PROJECT_CONTROLLER', 'active': False})
    return pid, mid, other


def approve(graph, mid, seconds, offset):
    client, put, _, employee, *_ = graph
    key = mid + offset
    module = get('modules', mid)
    put('work-logs', key, {'moduleId': mid, 'moduleName': module['moduleName'],
        'employeeId': employee, 'projectId': module['projectId'], 'workDate': '2026-10-30',
        'approvalStatus': 'PENDING', 'billableDurationSeconds': seconds})
    result = client.put(f'/api/work-logs/{key}/approve', json={})
    assert result.status_code == 200, result.text
    return key


def milestones(pid, mid=None):
    return [s.to_dict() for s in db.collection('notifications').where(
        filter=FieldFilter('projectId', '==', pid)).stream()
        if (mid is None or s.to_dict().get('moduleId') == mid) and s.to_dict().get('type') == 'MODULE_MILESTONE_REACHED' and s.to_dict().get('milestonePercent') is not None]


def test_module_crosses_all_four_thresholds_once_for_its_team_and_managers(graph):
    pid, mid, other = setup_project(graph)
    lead, employee, peer = graph[2:5]
    for index, module in enumerate([mid, mid, mid, mid]):
        approve(graph, module, [27, 27, 27, 9][index] * 60, 100 + index)
        assert get('modules', mid)['notifiedMilestones'] == [30, 60, 90, 100][:index + 1]
    notes = milestones(pid)
    assert {lead, employee, lead + 60, lead + 61} <= {n['userId'] for n in notes}
    assert lead + 62 not in {n['userId'] for n in notes}
    for uid in {n['userId'] for n in notes}:
        assert sorted(n['milestonePercent'] for n in notes if n['userId'] == uid) == [30, 60, 90, 100]
    assert all(n['pushPending'] and n['estimatedMinutes'] == 90 for n in notes)
    # Further approvals above 100% and ordinary module saves cannot repeat them.
    approve(graph, mid, 60, 200)
    assert graph[0].put(f'/api/modules/{mid}', json={'remarks': 'Unchanged progress'}).status_code == 200
    assert len(milestones(pid)) == len(notes)


def test_module_uses_own_estimate_and_second_precision(graph):
    pid, mid, _ = setup_project(graph)
    approve(graph, mid, 27 * 60 - 1, 100)
    assert milestones(pid) == []
    approve(graph, mid, 1, 101)
    assert {n['milestonePercent'] for n in milestones(pid)} == {30}
    assert all(n['workedMinutes'] == 27 for n in milestones(pid))


def test_only_module_team_gets_milestones_even_if_leader_outside_member_list(graph):
    pid, mid, other = setup_project(graph)
    lead = graph[2]
    second_lead, unrelated_lead = lead + 70, lead + 71
    for uid in (second_lead, unrelated_lead):
        graph[1]('employees', uid, {'role': 'TEAM_LEADER', 'active': True})
    db.collection('modules').document(str(mid)).update({'memberIds': [graph[3]]})
    db.collection('modules').document(str(other)).update({
        'teamLeadId': second_lead, 'memberIds': [graph[4]]})
    for index, module in enumerate([mid, mid, mid, mid]):
        approve(graph, module, [27, 27, 27, 9][index] * 60, 100 + index)
    notes = milestones(pid)
    for uid in (lead,):
        alerts = [n for n in notes if n['userId'] == uid]
        assert sorted(n['milestonePercent'] for n in alerts) == [30, 60, 90, 100]
        assert all(n['pushPending'] and not n['read'] for n in alerts)
    assert second_lead not in {n['userId'] for n in notes}
    assert graph[4] not in {n['userId'] for n in notes}
    assert unrelated_lead not in {n['userId'] for n in notes}


def test_concurrent_approvals_do_not_duplicate(graph):
    pid, mid, other = setup_project(graph)
    # Pre-create the logs to avoid concurrent fixture bookkeeping.
    keys = [mid + 100, other + 101]
    for key, module in zip(keys, [mid, other]):
        graph[1]('work-logs', key, {'moduleId': module, 'moduleName': 'Design',
            'employeeId': graph[3], 'projectId': pid, 'workDate': '2026-10-30',
            'approvalStatus': 'PENDING', 'billableDurationSeconds': 54 * 60})
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda key: graph[0].put(f'/api/work-logs/{key}/approve', json={}), keys))
    assert all(r.status_code == 200 for r in responses), [r.text for r in responses]
    notes = milestones(pid)
    for module in (mid, other):
        alerts = milestones(pid, module)
        assert alerts
        for uid in {n['userId'] for n in alerts}:
            assert [n['milestonePercent'] for n in alerts if n['userId'] == uid] == [60]
        assert get('modules', module)['notifiedMilestones'] == [30, 60]
    assert graph[0].put(f'/api/work-logs/{keys[0]}/approve', json={}).status_code == 409
    assert len(milestones(pid)) == len(notes)


@pytest.mark.parametrize('inactive,estimate', [(True, 90), (False, 0)])
def test_inactive_or_unestimated_projects_do_not_emit_percentage_alerts(graph, inactive, estimate):
    pid, mid, _ = setup_project(graph, estimate)
    if inactive:
        db.collection('projects').document(str(pid)).update({'active': False})
    approve(graph, mid, 180 * 60, 100)
    assert milestones(pid) == []


@pytest.mark.parametrize('minutes,threshold,consumed', [
    (59, 60, [30, 60]), (85, 90, [30, 60, 90]), (90, 100, [30, 60, 90, 100])])
def test_large_approval_only_queues_highest_crossed_threshold(graph, minutes, threshold, consumed):
    pid, mid, _ = setup_project(graph)
    approve(graph, mid, minutes * 60, 100)
    notes = milestones(pid)
    assert notes
    for uid in {n['userId'] for n in notes}:
        assert [n['milestonePercent'] for n in notes if n['userId'] == uid] == [threshold]
    assert get('modules', mid)['notifiedMilestones'] == consumed
    approve(graph, mid, 1, 101)
    assert len(milestones(pid)) == len(notes)


def test_estimate_increase_does_not_repeat_already_notified_thresholds(graph):
    pid, mid, _ = setup_project(graph)
    approve(graph, mid, 27 * 60, 100)
    notes = milestones(pid)
    assert {n['milestonePercent'] for n in notes} == {30}
    db.collection('modules').document(str(mid)).update({'estimatedMinutes': 270})
    approve(graph, mid, 54 * 60, 101)
    assert len(milestones(pid)) == len(notes)
    assert get('modules', mid)['notifiedMilestones'] == [30]


def test_exact_boundaries_legacy_markers_and_skipped_levels_do_not_replay(graph):
    pid, mid, _ = setup_project(graph)
    db.collection('projects').document(str(pid)).update({'notifiedMilestones': [25, 50]})
    approve(graph, mid, 54 * 60 - 1, 100)
    assert {n['milestonePercent'] for n in milestones(pid)} == {30}
    approve(graph, mid, 1, 101)
    notes = milestones(pid)
    assert {n['milestonePercent'] for n in notes} == {30, 60}
    assert get('modules', mid)['notifiedMilestones'] == [30, 60]
    db.collection('modules').document(str(mid)).update({'estimatedMinutes': 270})
    approve(graph, mid, 1, 102)
    assert len(milestones(pid)) == len(notes)


def test_progress_and_timesheet_alert_ids_do_not_collide_in_one_clock_tick(graph, monkeypatch):
    pid, mid, _ = setup_project(graph)
    import app.module_events as events
    monkeypatch.setattr(events.time, 'time_ns', lambda: graph[2] * 1000)
    approve(graph, mid, 59 * 60, 100)
    notes = milestones(pid)
    assert notes and {n['milestonePercent'] for n in notes} == {60}
    # Completion may add recipients; find the independent timesheet alert by its module.
    alerts = [s.to_dict() for s in db.collection('notifications').where(
        filter=FieldFilter('moduleId', '==', mid)).stream()]
    assert len([n for n in alerts if n['type'] == 'TIMESHEET_APPROVED']) == 1
