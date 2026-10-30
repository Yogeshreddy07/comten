"""Combined-project milestones use approved hours and atomic once-only markers."""
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


def milestones(pid):
    return [s.to_dict() for s in db.collection('notifications').where(
        filter=FieldFilter('projectId', '==', pid)).stream()
        if s.to_dict().get('type') == 'PROJECT_MILESTONE_REACHED']


def test_combined_project_crosses_all_four_thresholds_once_for_managers_and_staff(graph):
    pid, mid, other = setup_project(graph)
    lead, employee, peer = graph[2:5]
    for index, module in enumerate([mid, mid, other, other]):
        approve(graph, module, 45 * 60, 100 + index)
        assert get('projects', pid)['notifiedMilestones'] == [25, 50, 75, 100][:index + 1]
    notes = milestones(pid)
    assert {lead, employee, peer, lead + 60, lead + 61} <= {n['userId'] for n in notes}
    assert lead + 62 not in {n['userId'] for n in notes}
    for uid in {n['userId'] for n in notes}:
        assert sorted(n['milestonePercent'] for n in notes if n['userId'] == uid) == [25, 50, 75, 100]
    assert all(n['pushPending'] and n['estimatedMinutes'] == 180 for n in notes)
    # Further approvals above 100% and ordinary module saves cannot repeat them.
    approve(graph, other, 60, 200)
    assert graph[0].put(f'/api/modules/{mid}', json={'remarks': 'Unchanged progress'}).status_code == 200
    assert len(milestones(pid)) == len(notes)


def test_one_hour_of_three_reaches_only_25_percent_and_uses_second_precision(graph):
    pid, mid, _ = setup_project(graph)
    approve(graph, mid, 45 * 60 - 1, 100)
    assert milestones(pid) == []
    approve(graph, mid, 15 * 60 + 1, 101)
    assert {n['milestonePercent'] for n in milestones(pid)} == {25}
    assert all(n['workedMinutes'] == 60 for n in milestones(pid))


def test_large_approval_crosses_several_thresholds_and_concurrent_approvals_do_not_duplicate(graph):
    pid, mid, other = setup_project(graph)
    # Pre-create the logs to avoid concurrent fixture bookkeeping.
    keys = [mid + 100, other + 101]
    for key, module in zip(keys, [mid, other]):
        graph[1]('work-logs', key, {'moduleId': module, 'moduleName': 'Design',
            'employeeId': graph[3], 'projectId': pid, 'workDate': '2026-10-30',
            'approvalStatus': 'PENDING', 'billableDurationSeconds': 45 * 60})
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda key: graph[0].put(f'/api/work-logs/{key}/approve', json={}), keys))
    assert all(r.status_code == 200 for r in responses), [r.text for r in responses]
    notes = milestones(pid)
    for uid in {n['userId'] for n in notes}:
        assert sorted(n['milestonePercent'] for n in notes if n['userId'] == uid) == [25, 50]
    assert graph[0].put(f'/api/work-logs/{keys[0]}/approve', json={}).status_code == 409
    assert len(milestones(pid)) == len(notes)


@pytest.mark.parametrize('inactive,estimate', [(True, 90), (False, 0)])
def test_inactive_or_unestimated_projects_do_not_emit_percentage_alerts(graph, inactive, estimate):
    pid, mid, _ = setup_project(graph, estimate)
    if inactive:
        db.collection('projects').document(str(pid)).update({'active': False})
    approve(graph, mid, 180 * 60, 100)
    assert milestones(pid) == []


def test_one_large_approval_queues_every_crossed_project_threshold(graph):
    pid, mid, _ = setup_project(graph)
    approve(graph, mid, 135 * 60, 100)
    notes = milestones(pid)
    for uid in {n['userId'] for n in notes}:
        assert sorted(n['milestonePercent'] for n in notes if n['userId'] == uid) == [25, 50, 75]


def test_estimate_increase_does_not_repeat_already_notified_thresholds(graph):
    pid, mid, _ = setup_project(graph)
    approve(graph, mid, 90 * 60, 100)
    notes = milestones(pid)
    assert {n['milestonePercent'] for n in notes} == {25, 50}
    db.collection('modules').document(str(mid)).update({'estimatedMinutes': 270})
    approve(graph, mid, 90 * 60, 101)
    assert len(milestones(pid)) == len(notes)
    assert get('projects', pid)['notifiedMilestones'] == [25, 50]
