import sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))


def activate_employee(client, code, password='SyntheticPass123!'):
    from app.recovery import resolve
    from app.store import db
    from app.config import settings
    person = resolve(code)
    if not person.get('phone'):
        assert settings.environment == 'local'
        db.collection('employees').document(str(person['id'])).update({'phone': '+1555' + str(person['id']).zfill(7)})
    response = client.post('/api/auth/signup/send-otp', json={'employeeCode':code})
    assert response.status_code == 200, response.text
    response = client.post('/api/auth/signup/verify-otp', json={'employeeCode':code,'otp':'123456'})
    assert response.status_code == 200, response.text
    response = client.post('/api/auth/signup/set-password', json={
        'employeeCode':code,'signupToken':response.json()['data']['signupToken'],
        'newPassword':password,'confirmPassword':password})
    assert response.status_code == 200, response.text
    phone_session = response.json()['data']
    phone_request = {'employeeCode': code, 'phoneVerificationToken': phone_session['phoneVerificationToken']}
    assert client.post('/api/auth/signup/phone/send-otp', json=phone_request).status_code == 200
    response = client.post('/api/auth/signup/phone/verify-otp', json=phone_request | {'otp': '123456'})
    assert response.status_code == 200, response.text
    return password
