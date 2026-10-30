"""Regression coverage for project selection and shared roster reconciliation."""
import time
import hashlib
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.security import current_user
from app.store import db, get
from google.cloud.firestore_v1.base_query import FieldFilter


@pytest.fixture
def graph():
    base = time.time_ns() // 1000
    refs = []

    def put(collection, key, row):
        ref = db.collection(collection).document(str(key))
        ref.set({'id': key, **row})
        refs.append(ref)

    lead, employee, peer = base, base + 1, base + 2
    for uid, role in [(lead, 'TEAM_LEADER'), (employee, 'EMPLOYEE'), (peer, 'EMPLOYEE')]:
        put('employees', uid, {'employeeCode': str(uid), 'name': 'Synthetic',
                             'active': True, 'role': role, 'permissionVersion': 1})
    activity, inactive = base + 3, base + 4
    put('activities', activity, {'name': 'Active', 'active': True})
    put('activities', inactive, {'name': 'Retired', 'active': False})
    app.dependency_overrides[current_user] = lambda: {'id': 1, 'name': 'Synthetic manager', 'role': 'CAPTAIN'}
    try:
        yield TestClient(app), put, lead, employee, peer, activity, inactive, refs
    finally:
        app.dependency_overrides.pop(current_user, None)
        batch = db.batch()
        for ref in refs:
            batch.delete(ref)
        batch.commit()


def create(graph):
    client, _, lead, employee, _, activity, _, refs = graph
    response = client.post('/api/projects', json={
        'projectName': 'Synthetic lifecycle', 'projectCode': f'PERF-{lead}', 'moduleName': 'Design',
        'teamLeadId': lead, 'memberIds': [employee], 'billableActivityIds': [activity]})
    assert response.status_code == 200, response.text
    project = response.json()['data']
    module = project['modules'][0]
    refs.extend([db.collection('projects').document(str(project['id'])),
                 db.collection('modules').document(str(module['id'])),
                 db.collection('project-codes').document(hashlib.sha256(project['projectCode'].casefold().encode()).hexdigest())])
    return project['id'], module['id']


def test_duplicate_project_codes_are_rejected_even_with_case_and_spaces(graph):
    client = graph[0]
    pid, _ = create(graph)
    code = get('projects', pid)['projectCode']
    response = client.post('/api/projects', json={
        'projectCode': ' ' + code.lower() + ' ', 'projectName': 'Duplicate',
        'moduleName': 'Design'})
    assert response.status_code == 409, response.text
    assert 'Project ID already exists' in response.json()['message']


def test_legacy_project_codes_are_protected(graph):
    client, put, lead, *_ = graph
    put('projects', lead + 20, {'projectCode': f' Legacy-{lead} ', 'active': False})
    response = client.post('/api/projects', json={
        'projectCode': f'LEGACY-{lead}', 'projectName': 'Duplicate', 'moduleName': 'Design'})
    assert response.status_code == 409


def test_creation_response_failure_does_not_write_project(graph, monkeypatch):
    import app.main as main
    def fail(*args, **kwargs):
        raise RuntimeError('Synthetic response failure')
    monkeypatch.setattr(main, 'project_response', fail)
    with pytest.raises(RuntimeError, match='Synthetic response failure'):
        create(graph)
    matches=list(db.collection('projects').where(filter=FieldFilter('projectCode','==',f'PERF-{graph[2]}')).stream())
    assert matches == []


def test_assigned_activity_cannot_be_deleted_and_unassigned_stays_deleted(graph):
    client, put, lead, _, _, activity, *_ = graph
    create(graph)
    blocked=client.delete(f'/api/activities/{activity}')
    assert blocked.status_code == 409
    assert 'assigned to a project' in blocked.json()['message']
    assert get('activities',activity)['active'] is True
    spare=lead+30
    put('activities',spare,{'name':'Unused','active':True})
    assert client.delete(f'/api/activities/{spare}').status_code == 200
    for _ in range(2):
        offered=client.get('/api/activities?limit=200').json()['data']
        assert spare not in {row['id'] for row in offered}
    assert get('activities',spare)['active'] is False


def test_concurrent_duplicate_creation_commits_only_once(graph):
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(create,graph) for _ in range(2)]
        outcomes=[]
        for future in futures:
            try:
                outcomes.append(future.result())
            except AssertionError as error:
                assert 'Project ID already exists' in str(error)
    assert len(outcomes)==1


def test_activity_picker_excludes_retired_and_stale_selection_is_rejected(graph):
    client, _, lead, employee, _, active, inactive, _ = graph
    offered = client.get('/api/activities?limit=200').json()['data']
    assert active in {row['id'] for row in offered}
    assert inactive not in {row['id'] for row in offered}
    response = client.post('/api/projects', json={
        'projectName': 'Invalid selection', 'projectCode': 'PERF', 'moduleName': 'Design',
        'teamLeadId': lead, 'memberIds': [employee], 'billableActivityIds': [inactive]})
    assert response.status_code == 422
    assert 'Activity selection is unavailable' in response.json()['message']


def test_lifecycle_preserves_other_project_permissions_and_cascades(graph):
    client, put, lead, employee, peer, _, _, _ = graph
    pid, mid = create(graph)
    other = peer + 10
    put('projects', other, {'active': True, 'memberIds': [employee, peer]})
    put('modules', other + 1, {'projectId': other, 'active': True,
                              'memberIds': [employee, peer], 'teamLeadId': peer})
    assert client.delete(f'/api/projects/{pid}').status_code == 200
    assert get('modules', mid)['active'] is False
    assert get('projects', pid)['memberIds'] == []
    assert get('employees', employee)['teamLeadIds'] == [peer]
    assert get('employees', employee)['peerIds'] == sorted([employee, peer])
    assert get('employees', lead)['peerIds'] == [lead]
    assert client.put(f'/api/modules/{mid}/activate', json={}).status_code == 409
    assert client.put(f'/api/projects/{pid}/activate', json={}).status_code == 200
    assert get('modules', mid)['active'] is False
    assert client.put(f'/api/modules/{mid}/activate', json={}).status_code == 200
    assert get('projects', pid)['memberIds'] == sorted([lead, employee])
    assert get('employees', employee)['teamLeadIds'] == sorted([lead, peer])
    assert get('employees', employee)['permissionVersion'] > 1


@pytest.mark.parametrize('role', ['CAPTAIN', 'PROJECT_CONTROLLER'])
@pytest.mark.parametrize('stage', ['WIP', 'BILLING'])
def test_managers_change_project_status_directly_without_approval(graph, role, stage):
    client = graph[0]
    pid, mid = create(graph)
    db.collection('modules').document(str(mid)).update({
        'workStage': stage, 'billingStatus': 'PART_PAYMENT_RECEIVED'})
    app.dependency_overrides[current_user] = lambda: {'id': 2, 'name': 'Manager', 'role': role}
    for _ in range(2):
        response = client.delete(f'/api/projects/{pid}')
        assert response.status_code == 200, response.text
        assert response.json()['data']['active'] is False
        assert 'deactivationPending' not in response.json()['data']
    assert get('modules', mid)['active'] is False
    assert get('modules', mid)['billingStatus'] == 'PART_PAYMENT_RECEIVED'
    assert get('projects', pid)['memberIds'] == []
    assert not list(db.collection('project-deactivation-requests').where(filter=FieldFilter('projectId', '==', pid)).stream())
    assert not list(db.collection('notifications').where(filter=FieldFilter('projectId', '==', pid)).stream())
    assert client.put(f'/api/projects/{pid}/activate', json={}).status_code == 200
    assert get('projects', pid)['active'] is True
    # Preserve existing activation behavior: modules are activated individually.
    assert get('modules', mid)['active'] is False


@pytest.mark.parametrize('role', ['TEAM_LEADER', 'EMPLOYEE'])
def test_project_status_changes_still_require_manager_permissions(graph, role):
    client = graph[0]
    pid, mid = create(graph)
    app.dependency_overrides[current_user] = lambda: {'id': 2, 'role': role}
    assert client.delete(f'/api/projects/{pid}').status_code == 403
    assert client.put(f'/api/projects/{pid}/activate', json={}).status_code == 403
    assert get('projects', pid)['active'] is True
    assert get('modules', mid)['active'] is True


@pytest.mark.parametrize('stage', ['WIP', 'BILLING'])
def test_completed_module_cannot_be_moved_back_to_wip_by_lead(graph, stage):
    client, _, lead, *_ = graph
    _, mid = create(graph)
    db.collection('modules').document(str(mid)).update({'status':'COMPLETED','workStage':stage})
    app.dependency_overrides[current_user] = lambda: {'id':lead,'role':'TEAM_LEADER'}
    response=client.put(f'/api/modules/{mid}/work-stage',json={'workStage':'WIP'})
    assert response.status_code == 409
    assert 'already completed and cannot be moved back to WIP' in response.json()['message']
    assert get('modules',mid)['status']=='COMPLETED'
    assert get('modules',mid)['workStage']==stage


def test_billing_completed_module_cannot_return_to_wip(graph):
    client, _, lead, *_ = graph
    _, mid = create(graph)
    db.collection('modules').document(str(mid)).update({'status':'IN_PROGRESS','workStage':'BILLING','billingStatus':'FULL_PAYMENT_RECEIVED'})
    app.dependency_overrides[current_user] = lambda: {'id':lead,'role':'TEAM_LEADER'}
    response=client.put(f'/api/modules/{mid}/work-stage',json={'workStage':'WIP'})
    assert response.status_code == 409
    assert 'already completed and cannot be moved back to WIP' in response.json()['message']
    assert get('modules',mid)['workStage']=='BILLING'


def test_module_already_in_billing_cannot_be_moved_to_billing_again(graph):
    client, _, lead, *_ = graph
    _, mid = create(graph)
    app.dependency_overrides[current_user] = lambda: {'id':lead,'role':'TEAM_LEADER','name':'Lead'}
    assert client.put(f'/api/modules/{mid}/work-stage',json={'workStage':'BILLING'}).status_code == 200
    notified=len([n for n in db.collection('notifications').stream() if n.to_dict().get('moduleId')==mid])
    response=client.put(f'/api/modules/{mid}/work-stage',json={'workStage':'BILLING'})
    assert response.status_code == 409 and response.json()['message']=='This module is already in Billing.'
    assert len([n for n in db.collection('notifications').stream() if n.to_dict().get('moduleId')==mid])==notified
    assert client.put(f'/api/modules/{mid}/work-stage',json={'workStage':'WIP'}).status_code == 200
    assert client.put(f'/api/modules/{mid}/work-stage',json={'workStage':'WIP'}).json()['message']=='This module is already in WIP.'


def test_staff_only_directory_excludes_managers_and_preserves_controller_directory(graph):
    client, put, lead, *_ = graph
    put('employees',lead+40,{'role':'PROJECT_CONTROLLER','active':True})
    put('employees',lead+41,{'role':'CAPTAIN','active':True})
    staff=client.get('/api/employees?staffOnly=true&limit=200').json()['data']
    assert staff
    assert {row['role'] for row in staff} <= {'EMPLOYEE','TEAM_LEADER'}
    controllers=client.get('/api/employees?role=PROJECT_CONTROLLER&limit=200').json()['data']
    assert lead+40 in {row['id'] for row in controllers}


def test_module_with_no_pending_hours_reads_completed():
    from app.mobile_contracts import effective_status
    base={'status':'IN_PROGRESS','active':True,'estimatedMinutes':60}
    assert effective_status(base|{'completedMinutes':59})=='IN_PROGRESS'
    assert effective_status(base|{'completedMinutes':60})=='COMPLETED'
    assert effective_status(base|{'completedMinutes':65})=='COMPLETED'
    # No estimate, on hold, or inactive modules are never inferred complete.
    assert effective_status(base|{'estimatedMinutes':0,'completedMinutes':65})=='IN_PROGRESS'
    assert effective_status(base|{'status':'ON_HOLD','completedMinutes':65})=='ON_HOLD'
    assert effective_status(base|{'active':False,'completedMinutes':65})=='INACTIVE'


def test_inactive_billing_moves_to_completed_without_inventing_payment(graph):
    client=graph[0]
    pid,mid=create(graph)
    ref=db.collection('modules').document(str(mid))
    ref.update({'workStage':'BILLING','billingStatus':'PART_PAYMENT_RECEIVED'})
    assert client.delete(f'/api/projects/{pid}').status_code==200
    row=next(m for m in client.get('/api/billing').json()['data'] if m['moduleId']==mid)
    assert row['stage']=='COMPLETED' and row['moduleStatus']=='INACTIVE' and not row['editable']
    assert row['status']=='PART_PAYMENT_RECEIVED'
    assert get('modules',mid)['billingStatus']=='PART_PAYMENT_RECEIVED'


def test_legacy_pending_deactivation_does_not_block_or_override_status_changes(graph):
    client, put, *_ = graph
    pid, mid = create(graph)
    db.collection('modules').document(str(mid)).update({'workStage': 'BILLING'})
    request_id = mid + 200
    put('project-deactivation-requests', request_id, {
        'projectId': pid, 'requestedById': 2, 'approvalStatus': 'PENDING', 'status': 'PENDING'})
    lock = db.collection('pending-approvals').document(f'project-deactivation-requests-{pid}')
    lock.set({'requestId': request_id})
    graph[-1].append(lock)
    app.dependency_overrides[current_user] = lambda: {'id': 2, 'name': 'Controller', 'role': 'PROJECT_CONTROLLER'}
    assert client.delete(f'/api/projects/{pid}').status_code == 200
    assert get('projects', pid)['active'] is False
    assert get('modules', mid)['active'] is False
    assert client.put(f'/api/projects/{pid}/activate', json={}).status_code == 200
    # Retired endpoints cannot queue new requests or apply an old one later.
    assert client.post('/api/project-deactivation-requests', json={'projectId': pid}).status_code == 410
    app.dependency_overrides[current_user] = lambda: {'id': 1, 'name': 'Captain', 'role': 'CAPTAIN'}
    assert client.put(f'/api/project-deactivation-requests/{request_id}/approve', json={}).status_code == 410
    assert get('projects', pid)['active'] is True


def test_completion_alert_is_atomic_and_not_repeated_on_save(graph):
    client,_,lead,employee,*_=graph
    _,mid=create(graph)
    for _ in range(2):
        response=client.put(f'/api/modules/{mid}',json={'status':'COMPLETED'})
        assert response.status_code==200,response.text
    alerts=[s.to_dict() for s in db.collection('notifications').where(filter=FieldFilter('moduleId','==',mid)).stream() if s.to_dict().get('title')=='Module completed']
    assert len([n for n in alerts if n['userId']==lead])==1
    assert len([n for n in alerts if n['userId']==employee])==1
    assert all(n['pushPending'] for n in alerts)
    app.dependency_overrides[current_user]=lambda:{'id':lead,'role':'TEAM_LEADER'}
    assert client.post('/api/notifications/delay-requests',json={'moduleId':mid,'reason':'Stale picker'}).status_code==409


def test_hours_approval_crossing_estimate_emits_one_completion_alert(graph):
    client,put,lead,employee,*_=graph
    _,mid=create(graph)
    db.collection('modules').document(str(mid)).update({'estimatedMinutes':60,'completedSeconds':3540,'completedMinutes':59})
    for offset in (100,101):
        key=mid+offset
        put('work-logs',key,{'moduleId':mid,'moduleName':'Design','employeeId':employee,'projectId':get('modules',mid)['projectId'],
                             'workDate':'2026-10-28','approvalStatus':'PENDING','billableDurationSeconds':60})
        assert client.put(f'/api/work-logs/{key}/approve',json={}).status_code==200
    alerts=[s.to_dict() for s in db.collection('notifications').where(filter=FieldFilter('moduleId','==',mid)).stream() if s.to_dict().get('title')=='Module completed']
    assert len([n for n in alerts if n['userId']==employee])==1
    assert len([n for n in alerts if n['userId']==lead])==1
