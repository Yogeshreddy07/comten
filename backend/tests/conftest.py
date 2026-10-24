import sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))


def activate_employee(client, code, password='SyntheticPass123!'):
    response = client.post('/api/auth/signup/send-otp', json={'employeeCode':code})
    assert response.status_code == 200, response.text
    response = client.post('/api/auth/signup/verify-otp', json={'employeeCode':code,'otp':'123456'})
    assert response.status_code == 200, response.text
    response = client.post('/api/auth/signup/set-password', json={
        'employeeCode':code,'signupToken':response.json()['data']['signupToken'],
        'newPassword':password,'confirmPassword':password})
    assert response.status_code == 200, response.text
    return password
