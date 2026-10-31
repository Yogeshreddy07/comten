"""Email recovery must enforce the same three-attempt policy as activation/SMS."""
import time
from app.store import db
from conftest import activate_employee
from test_email_activation import create
from test_employee_identity import client


def test_recovery_lockout_blocks_resend_then_requires_fresh_code(client):
    person = create(client)
    activate_employee(client, person['employeeCode'])
    request = {'employeeCode': person['employeeCode'], 'email': person['email']}
    assert client.post('/api/auth/forgot-password/send-otp', json=request).status_code == 200
    ref = db.collection('recovery').document(str(person['id']))
    for left in (2, 1, 0):
        response = client.post('/api/auth/forgot-password/verify-otp', json=request | {'otp': '000000'})
        assert response.status_code == 401
        assert response.json()['message'] == (
            f'Incorrect OTP. {left} attempt{"s" if left != 1 else ""} left.' if left
            else 'No attempts left. Please try again after 15 minutes.')
    deadline = ref.get().to_dict()['lockedUntil']
    for endpoint in ('send-otp', 'verify-otp'):
        response = client.post('/api/auth/forgot-password/' + endpoint, json=request | {'otp': '123456'})
        assert response.status_code == 429
        assert 899 <= response.json()['data']['retryAfterSeconds'] <= 900
        assert ref.get().to_dict()['lockedUntil'] == deadline
    ref.update({'lockedUntil': time.time() - 1, 'lastSent': 0})
    assert client.post('/api/auth/forgot-password/verify-otp', json=request | {'otp': '123456'}).status_code == 401
    assert client.post('/api/auth/forgot-password/send-otp', json=request).status_code == 200
    assert client.post('/api/auth/forgot-password/verify-otp', json=request | {'otp': '123456'}).status_code == 200
