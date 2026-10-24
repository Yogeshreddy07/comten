import time
import uuid
import pytest
from firebase_admin import auth
from fastapi import HTTPException
from app.store import db, get
from app import email_activation, recovery, messaging
from test_employee_identity import client
from conftest import activate_employee


def create(client):
    response=client.post('/api/employees',json={'name':'Email activation test','role':'EMPLOYEE','email':uuid.uuid4().hex+'@example.invalid'})
    assert response.status_code==200,response.text
    return response.json()['data']


def test_new_account_uses_email_otp_not_temporary_password(client):
    person=create(client);code=person['employeeCode'];uid=str(person['id'])
    assert 'temporaryPassword' not in person and person['activationEmailSent']
    assert person['activationStatus']=='PENDING' and auth.get_user(uid).disabled
    state=get('email-activation',uid)
    assert '123456' not in str(state) and 'otp' not in state
    assert client.post('/api/auth/signup/set-password',json={'employeeCode':code,'signupToken':'forged','newPassword':'ValidPassword123!','confirmPassword':'ValidPassword123!'}).status_code==401
    password=activate_employee(client,code)
    assert not auth.get_user(uid).disabled
    assert get('employees',uid)['emailVerified']
    assert client.post('/api/auth/login',json={'employeeCode':code,'password':password}).status_code==200
    assert client.post('/api/auth/signup/verify-otp',json={'employeeCode':code,'otp':'123456'}).status_code==401


def test_activation_attempts_expiry_recipient_binding_and_proof_replay(client):
    person=create(client);uid=str(person['id']);code=person['employeeCode']
    request={'employeeCode':code,'otp':'000000'}
    for _ in range(5): assert client.post('/api/auth/signup/verify-otp',json=request).status_code==401
    assert client.post('/api/auth/signup/verify-otp',json=request|{'otp':'123456'}).status_code==401
    ref=db.collection('email-activation').document(uid)
    ref.update({'lastSent':0})
    assert client.post('/api/auth/signup/send-otp',json={'employeeCode':code}).status_code==200
    ref.update({'expires':time.time()-1})
    assert client.post('/api/auth/signup/verify-otp',json=request|{'otp':'123456'}).status_code==401
    ref.update({'lastSent':0})
    client.post('/api/auth/signup/send-otp',json={'employeeCode':code})
    db.collection('employees').document(uid).update({'email':uuid.uuid4().hex+'@example.invalid'})
    assert client.post('/api/auth/signup/verify-otp',json=request|{'otp':'123456'}).status_code==401
    ref.update({'lastSent':0})
    client.post('/api/auth/signup/send-otp',json={'employeeCode':code})
    verified=client.post('/api/auth/signup/verify-otp',json=request|{'otp':'123456'}).json()['data']
    body=verified|{'newPassword':'ValidPassword123!','confirmPassword':'ValidPassword123!'}
    assert client.post('/api/auth/signup/set-password',json=body).status_code==200
    assert client.post('/api/auth/signup/set-password',json=body).status_code==401


def test_resend_is_idempotent_during_cooldown(client):
    person=create(client);uid=str(person['id'])
    before=get('email-activation',uid)
    assert client.post('/api/auth/signup/send-otp',json={'employeeCode':person['employeeCode']}).status_code==200
    assert get('email-activation',uid)==before


def test_provider_failure_is_visible_and_does_not_lose_created_employee(client,monkeypatch):
    async def unavailable(*args,**kwargs):raise HTTPException(503,'Synthetic dispatch disabled')
    monkeypatch.setattr(email_activation.settings,'environment','development')
    monkeypatch.setattr(email_activation.settings,'recovery_hmac_key','synthetic-development-test-key')
    monkeypatch.setattr(email_activation,'email',unavailable)
    person=create(client)
    assert person['activationEmailSent'] is False
    assert get('employees',person['id'])['activationStatus']=='PENDING'
    assert get('email-activation',person['id'])['deliveryState']=='FAILED'


def test_recovery_still_requires_email_otp_and_is_bound_to_contact(client):
    person=create(client);activate_employee(client,person['employeeCode'])
    request={'employeeCode':person['employeeCode'],'email':person['email']}
    assert client.post('/api/auth/forgot-password/send-otp',json=request).status_code==200
    db.collection('employees').document(str(person['id'])).update({'email':'changed-'+person['email']})
    assert client.post('/api/auth/forgot-password/verify-otp',json=request|{'email':'changed-'+person['email'],'otp':'123456'}).status_code==401


def test_enrolled_recipient_scope_does_not_allow_arbitrary_email(client,monkeypatch):
    person=create(client)
    db.collection('employees').document(str(person['id'])).update({'email':'enrolled@gmail.com'})
    for key,value in {'allow_real_messages':True,'resend_dispatch_enabled':True,'email_registered_recipients_enabled':True,'approved_email_recipients':''}.items():
        monkeypatch.setattr(messaging.settings,key,value)
    messaging.recipient_allowed('resend','enrolled@gmail.com')
    with pytest.raises(HTTPException): messaging.recipient_allowed('resend','arbitrary@gmail.com')


def test_recovery_delivery_failure_does_not_claim_success_on_retry(client,monkeypatch):
    person=create(client);activate_employee(client,person['employeeCode'])
    async def unavailable(*args,**kwargs):raise HTTPException(503,'Synthetic provider failure')
    monkeypatch.setattr(recovery.settings,'environment','development')
    monkeypatch.setattr(recovery.settings,'recovery_hmac_key','synthetic-test-recovery-key')
    monkeypatch.setattr(recovery,'email',unavailable)
    request={'employeeCode':person['employeeCode'],'email':person['email']}
    assert client.post('/api/auth/forgot-password/send-otp',json=request).status_code==503
    assert client.post('/api/auth/forgot-password/send-otp',json=request).status_code==429
