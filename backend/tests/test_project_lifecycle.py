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


def test_billing_deactivation_keeps_project_active_pending_approval(graph):
    client = graph[0]
    pid, mid = create(graph)
    db.collection('modules').document(str(mid)).update({'workStage': 'BILLING'})
    app.dependency_overrides[current_user] = lambda: {'id': 2, 'name': 'Controller', 'role': 'PROJECT_CONTROLLER'}
    response = client.delete(f'/api/projects/{pid}')
    assert response.status_code == 200
    assert response.json()['data']['active'] is True
    assert get('modules', mid)['active'] is True
    for snap in db.collection('project-deactivation-requests').where(filter=FieldFilter('projectId', '==', pid)).stream():
        graph[-1].append(snap.reference)


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


def test_staff_only_directory_excludes_managers_and_preserves_controller_directory(graph):
    client, put, lead, *_ = graph
    put('employees',lead+40,{'role':'PROJECT_CONTROLLER','active':True})
    put('employees',lead+41,{'role':'CAPTAIN','active':True})
    staff=client.get('/api/employees?staffOnly=true&limit=200').json()['data']
    assert staff
    assert {row['role'] for row in staff} <= {'EMPLOYEE','TEAM_LEADER'}
    controllers=client.get('/api/employees?role=PROJECT_CONTROLLER&limit=200').json()['data']
    assert lead+40 in {row['id'] for row in controllers}
