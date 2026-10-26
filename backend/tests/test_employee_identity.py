"""Identity invariants exercised against the local Firebase emulators."""
import re
import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient
from firebase_admin import auth

from app.main import app
from app.security import current_user
from app.store import db
from conftest import activate_employee


@pytest.fixture
def client(monkeypatch):
    from app import delivery
    from app.config import settings
    assert settings.environment == 'local' and settings.project_id.startswith('demo-')
    before = {s.id for s in db.collection('employees').stream()}
    previous = app.dependency_overrides.copy()
    app.dependency_overrides[current_user] = lambda: {'id': 1, 'role': 'CAPTAIN'}
    monkeypatch.setattr(delivery, 'event', lambda *args, **kwargs: None)
    yield TestClient(app)
    app.dependency_overrides.clear()
    app.dependency_overrides.update(previous)
    for snapshot in db.collection('employees').stream():
        if snapshot.id not in before:
            snapshot.reference.delete()
            try:
                auth.delete_user(snapshot.id)
            except auth.UserNotFoundError:
                pass


def payload(**changes):
    return {'name': 'Identity regression', 'email': uuid.uuid4().hex + '@example.invalid',
            'role': 'EMPLOYEE'} | changes


def create(client, **changes):
    response = client.post('/api/employees', json=payload(**changes))
    assert response.status_code == 200, response.text
    return response.json()['data']


def test_auto_codes_follow_highest_existing_code_and_sort_numerically(client):
    state = db.collection('counters').document('employee-identities').get().to_dict() or {}
    legacy_code = f"EMP{state.get('sequence', 0) + 100:03d}"
    legacy = create(client, employeeCode=legacy_code)
    first = create(client)
    second = create(client)
    assert first['employeeCode'].startswith('EMP')
    assert int(first['employeeCode'][3:]) == int(legacy_code[3:]) + 1
    assert db.collection('employees').document(str(legacy['id'])).get().to_dict()['employeeCode'] == legacy_code
    assert int(second['employeeCode'][3:]) == int(first['employeeCode'][3:]) + 1
    assert 'temporaryPassword' not in first
    password = activate_employee(client, first['employeeCode'])
    assert client.post('/api/auth/login', json={'employeeCode': first['employeeCode'], 'password': password}).status_code == 200


@pytest.mark.parametrize('field,value,duplicate', [
    ('employeeCode', 'UNIQUE_TEST', 'unique_test'),
    ('email', 'Unique.Test@Example.invalid', '  UNIQUE.TEST@example.invalid  '),
    ('phone', '9876543210', '+91 98765-43210'),
])
def test_duplicates_rejected_even_for_inactive_deleted_accounts(client, field, value, duplicate):
    employee = create(client, **{field: value})
    db.collection('employees').document(str(employee['id'])).update({'active': False, 'deleted': True})
    response = client.post('/api/employees', json=payload(**{field: duplicate}))
    assert response.status_code == 409, response.text
    assert 'already in use' in response.json()['message']


def test_edit_cannot_take_another_contact_but_can_keep_own(client):
    first = create(client, phone='9876543211')
    second = create(client, phone='9876543212')
    for field in ('email', 'phone'):
        response = client.put(f"/api/employees/{second['id']}", json={field: first[field]})
        assert response.status_code == 409, response.text
    assert client.put(f"/api/employees/{first['id']}", json={
        'email': first['email'].upper(), 'phone': '9876543211'
    }).status_code == 200


def test_legacy_unformatted_contact_is_reserved(client):
    first = create(client)
    db.collection('employees').document(str(first['id'])).update({
        'phone': '98765 43213', 'email': 'Legacy.Contact@Example.invalid'
    })
    assert client.post('/api/employees', json=payload(phone='+919876543213')).status_code == 409
    assert client.post('/api/employees', json=payload(email='legacy.contact@example.invalid')).status_code == 409


@pytest.mark.parametrize('identity', ['email', 'phone', 'employeeCode'])
def test_concurrent_creates_cannot_share_contacts_or_code(client, identity):
    values = {'email': 'race@example.invalid', 'phone': '9876543214', 'employeeCode': 'RACE_TEST'}
    bodies = [payload(**{identity: values[identity]}), payload(**{identity: values[identity]})]
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda body: client.post('/api/employees', json=body), bodies))
    assert sorted(r.status_code for r in responses) == [200, 409]
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda _: client.post('/api/employees', json=payload()), range(2)))
    assert [r.status_code for r in responses] == [200, 200]
    codes = sorted(int(r.json()['data']['employeeCode'][3:]) for r in responses)
    assert codes[1] == codes[0] + 1


def test_concurrent_edits_cannot_claim_same_phone(client):
    employees = [create(client), create(client)]
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda e: client.put(
            f"/api/employees/{e['id']}", json={'phone': '9876543215'}), employees))
    assert sorted(r.status_code for r in responses) == [200, 409]


def test_failed_auth_creation_releases_contacts(client, monkeypatch):
    body = payload(phone='9876543216')
    original = auth.create_user
    def fail(**kwargs):
        raise auth.EmailAlreadyExistsError('Simulated existing Auth alias', None, None)
    monkeypatch.setattr(auth, 'create_user', fail)
    assert client.post('/api/employees', json=body).status_code == 409
    monkeypatch.setattr(auth, 'create_user', original)
    assert client.post('/api/employees', json=body).status_code == 200


def test_preflight_reports_both_owners_without_writing(client):
    first = create(client, phone='9876543220')
    second = create(client)
    db.collection('employees').document(str(first['id'])).update({'deleted': True, 'active': False})
    before = {s.id for s in db.collection('employees').stream()}
    counter = db.collection('counters').document('employee-identities').get().to_dict()
    response = client.post('/api/employees/validate-identity', json={
        'phone': '+91 98765 43220', 'email': ' ' + second['email'].upper() + ' '
    })
    assert response.status_code == 200, response.text
    data = response.json()['data']
    assert data['valid'] is False
    assert set(data['errors']) == {'phone', 'email'}
    assert first['name'] in data['errors']['phone'] and first['employeeCode'] in data['errors']['phone']
    assert second['employeeCode'] in data['errors']['email']
    assert first['email'] not in response.text
    assert {s.id for s in db.collection('employees').stream()} == before
    assert db.collection('counters').document('employee-identities').get().to_dict() == counter


def test_edit_preflight_allows_own_contacts_but_not_another_employee(client):
    employee = create(client, phone='9876543221')
    request = {'phone': '9876543221', 'email': employee['email'], 'excludeEmployeeId': employee['id']}
    data = client.post('/api/employees/validate-identity', json=request).json()['data']
    assert data == {'valid': True, 'errors': {}}
    request.pop('excludeEmployeeId')
    assert client.post('/api/employees/validate-identity', json=request).json()['data']['valid'] is False
    response = client.post('/api/employees', json=payload(phone='9876543221'))
    assert response.status_code == 409
    assert employee['employeeCode'] in response.json()['message']


def test_preflight_requires_manager_and_rejects_invalid_fields(client):
    previous = app.dependency_overrides[current_user]
    app.dependency_overrides[current_user] = lambda: {'id': 1, 'role': 'EMPLOYEE'}
    assert client.post('/api/employees/validate-identity', json={'email': 'test@example.invalid'}).status_code == 403
    app.dependency_overrides.pop(current_user)
    assert client.post('/api/employees/validate-identity', json={'email': 'test@example.invalid'}).status_code == 401
    app.dependency_overrides[current_user] = previous
    response = client.post('/api/employees/validate-identity', json={'email': 'test@example.invalid', 'password': 'NeverEchoThisPassword'})
    assert response.status_code == 422 and 'NeverEchoThisPassword' not in response.text
    assert client.post('/api/employees/validate-identity', json={'email': 'not-an-email'}).status_code == 422


def test_auto_codes_use_role_prefix_with_independent_sequences(client):
    codes = {role: [create(client, role=role)['employeeCode'] for _ in range(2)]
             for role in ('PROJECT_CONTROLLER', 'TEAM_LEADER', 'EMPLOYEE')}
    for role, prefix in (('PROJECT_CONTROLLER', 'PC'), ('TEAM_LEADER', 'TL'), ('EMPLOYEE', 'EMP')):
        first, second = codes[role]
        assert first.startswith(prefix) and second.startswith(prefix)
        assert re.fullmatch(prefix + r'\d{3,}', first)
        assert int(second[len(prefix):]) == int(first[len(prefix):]) + 1
    # A role's numbering is unaffected by codes issued to other roles.
    pc = create(client, role='PROJECT_CONTROLLER')['employeeCode']
    assert int(pc[2:]) == int(codes['PROJECT_CONTROLLER'][1][2:]) + 1
    password = activate_employee(client, pc)
    assert client.post('/api/auth/login', json={'employeeCode': pc, 'password': password}).status_code == 200
