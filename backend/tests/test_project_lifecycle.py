"""Regression coverage for project selection and shared roster reconciliation."""
import time

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
        'projectName': 'Synthetic lifecycle', 'projectCode': 'PERF', 'moduleName': 'Design',
        'teamLeadId': lead, 'memberIds': [employee], 'billableActivityIds': [activity]})
    assert response.status_code == 200, response.text
    project = response.json()['data']
    module = project['modules'][0]
    refs.extend([db.collection('projects').document(str(project['id'])),
                 db.collection('modules').document(str(module['id']))])
    return project['id'], module['id']


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
