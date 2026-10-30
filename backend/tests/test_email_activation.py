import asyncio
import hashlib
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
    response=client.post('/api/employees',json={'name':'Email activation test','role':'EMPLOYEE','email':uuid.uuid4().hex+'@example.invalid','phone':'9'+str(uuid.uuid4().int%1000000000).zfill(9)})
    assert response.status_code==200,response.text
    return response.json()['data']


def test_new_account_uses_email_otp_not_temporary_password(client):
    person=create(client);code=person['employeeCode'];uid=str(person['id'])
    assert 'temporaryPassword' not in person and person['activationEmailSent'] is False
    assert person['activationStatus']=='PENDING' and auth.get_user(uid).disabled
    assert get('email-activation',uid) is None
    assert client.post('/api/auth/signup/verify-otp',json={'employeeCode':code,'otp':'123456'}).status_code==401
    assert client.post('/api/auth/signup/send-otp',json={'employeeCode':code}).status_code==200
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
    assert client.post('/api/auth/signup/send-otp',json={'employeeCode':code}).status_code==200
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
    assert client.post('/api/auth/signup/send-otp',json={'employeeCode':person['employeeCode']}).status_code==200
    before=get('email-activation',uid)
    assert client.post('/api/auth/signup/send-otp',json={'employeeCode':person['employeeCode']}).status_code==200
    assert get('email-activation',uid)==before


def test_creation_queues_welcome_without_otp_and_worker_sends_once(client,monkeypatch):
    from app import delivery
    from app.email_templates import render
    for key,value in {'allow_real_messages':True,'email_provider':'resend','resend_dispatch_enabled':True}.items():
        monkeypatch.setattr(messaging.settings,key,value)
    # Synthetic recipients only; no provider request is made in this test.
    monkeypatch.setattr(messaging,'recipient_allowed',lambda *args:None)
    monkeypatch.setattr(delivery,'event',delivery.queue_event)
    sent=[]
    async def accepted(*args,**kwargs):sent.append((args,kwargs))
    monkeypatch.setattr(messaging,'email',accepted)
    person=create(client)
    key=hashlib.sha256(('employee-invited-'+str(person['id'])).encode()).hexdigest()
    queued=get('email-outbox',key)
    assert queued['kind']=='invitation' and queued['values']=={'code':person['employeeCode']}
    assert queued['state']=='PENDING'
    assert get('email-activation',person['id']) is None
    delivery.event(person['id'],'invitation','employee-invited-'+str(person['id']),code=person['employeeCode'])
    asyncio.run(delivery.dispatch_emails())
    asyncio.run(delivery.dispatch_emails())
    assert len(sent)==1
    subject,html,text=render('invitation',person['name'],code=person['employeeCode'])
    assert sent[0][0]==(person['email'],person['name'],subject,html)
    assert sent[0][1]['text']==text and 'tap Send OTP' in text
    assert get('email-outbox',key)['state']=='ACCEPTED'
    assert get('email-activation',person['id']) is None


def test_provider_failure_is_visible_and_does_not_lose_created_employee(client,monkeypatch):
    deliveries=[]
    async def unavailable(*args,**kwargs):
        deliveries.append(True)
        raise HTTPException(503,'Synthetic dispatch disabled')
    monkeypatch.setattr(email_activation.settings,'environment','development')
    monkeypatch.setattr(email_activation.settings,'recovery_hmac_key','synthetic-development-test-key')
    monkeypatch.setattr(email_activation,'email',unavailable)
    person=create(client)
    assert person['activationEmailSent'] is False
    assert deliveries==[]
    assert get('employees',person['id'])['activationStatus']=='PENDING'
    assert get('email-activation',person['id']) is None
    response=client.post('/api/auth/signup/send-otp',json={'employeeCode':person['employeeCode']})
    assert response.status_code==503
    assert 'Unable to send the verification email' in response.json()['message']
    assert deliveries==[True]
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


def password_stage(client, person):
    code=person['employeeCode']
    sent=client.post('/api/auth/signup/send-otp',json={'employeeCode':code})
    assert sent.status_code==200
    assert '**' in sent.json()['data']['maskedEmail']
    assert person['email'] not in sent.text
    verified=client.post('/api/auth/signup/verify-otp',json={'employeeCode':code,'otp':'123456'})
    proof=verified.json()['data']['signupToken']
    response=client.post('/api/auth/signup/set-password',json={'employeeCode':code,'signupToken':proof,
        'newPassword':'ValidPassword123!','confirmPassword':'ValidPassword123!'})
    assert response.status_code==200,response.text
    return {'employeeCode':code,'phoneVerificationToken':response.json()['data']['phoneVerificationToken']}


def test_activation_phone_reports_two_one_then_no_attempts_for_combined_provider_error(client, monkeypatch):
    import httpx
    monkeypatch.setattr(recovery.settings, 'recovery_hmac_key', 'synthetic-activation-test-key')
    person = create(client)
    request = password_stage(client, person)
    monkeypatch.setattr(recovery.settings, 'msg91_widget_id', 'synthetic-widget')
    assert client.post('/api/auth/signup/phone/send-otp', json=request).status_code == 200
    ref = db.collection('phone-challenges').document(str(person['id']))
    ref.update({'attempts': 2})
    deadline = ref.get().to_dict()['expires']
    for key, value in {'environment': 'development', 'allow_real_messages': True,
                       'msg91_dispatch_enabled': True, 'msg91_auth_key': 'synthetic',
                       'approved_sms_recipients': messaging.normalize_phone(person['phone'])}.items():
        monkeypatch.setattr(recovery.settings, key, value)
    calls = []
    async def reject(method, url, **kwargs):
        calls.append(url)
        assert url.endswith('verifyOtp')
        return httpx.Response(200, json={'type': 'error', 'message': 'OTP not matched or expired'})
    monkeypatch.setattr(messaging, 'provider_request', reject)
    try:
        for message in ('Incorrect OTP. 2 attempts left.', 'Incorrect OTP. 1 attempt left.',
                        'No attempts left. Please try again after some time.'):
            response = client.post('/api/auth/signup/phone/verify-otp', json=request | {'otp': '000000'})
            assert response.status_code == 401 and response.json()['message'] == message
            assert ref.get().to_dict()['expires'] == deadline
            assert not get('employees', person['id'])['phoneVerified']
            assert auth.get_user(str(person['id'])).disabled
        response = client.post('/api/auth/signup/phone/verify-otp', json=request | {'otp': '123456'})
        assert response.status_code == 401
        assert response.json()['message'] == 'No attempts left. Please try again after some time.'
        assert len(calls) == 3
    finally:
        ref.delete()


def test_login_locked_until_both_verifications_and_phone_proof_single_use(client):
    person=create(client);request=password_stage(client,person);uid=str(person['id'])
    assert get('employees',uid)['activationStatus']=='PHONE_PENDING'
    assert auth.get_user(uid).disabled
    assert client.post('/api/auth/login',json={'employeeCode':person['employeeCode'],'password':'ValidPassword123!'}).status_code==401
    reset=client.post('/api/auth/forgot-password/send-otp',json={'employeeCode':person['employeeCode'],'email':person['email']})
    assert reset.status_code==200 and get('recovery',uid) is None
    assert client.post('/api/auth/signup/phone/send-otp',json=request|{'phoneVerificationToken':'forged'}).status_code==401
    sent=client.post('/api/auth/signup/phone/send-otp',json=request)
    assert sent.status_code==200 and '**' in sent.json()['data']['maskedPhone']
    assert person['phone'] not in sent.text
    assert client.post('/api/auth/signup/phone/send-otp',json=request).status_code==429
    assert client.post('/api/auth/signup/phone/verify-otp',json=request|{'otp':'000000'}).status_code==401
    response=client.post('/api/auth/signup/phone/verify-otp',json=request|{'otp':'123456'})
    assert response.status_code==200,response.text
    assert response.json()['data'] is None
    assert get('employees',uid)['activationStatus']=='ACTIVE'
    assert get('employees',uid)['emailVerified'] and get('employees',uid)['phoneVerified']
    assert not auth.get_user(uid).disabled
    assert client.post('/api/auth/signup/phone/verify-otp',json=request|{'otp':'123456'}).status_code==401
    assert client.post('/api/auth/login',json={'employeeCode':person['employeeCode'],'password':'ValidPassword123!'}).status_code==200


@pytest.mark.parametrize('change',[{'phone':'+919876543210'},{'email':'changed@example.invalid'}])
def test_phone_session_expires_when_enrolled_contact_changes(client,change):
    person=create(client);request=password_stage(client,person)
    db.collection('employees').document(str(person['id'])).update(change)
    assert client.post('/api/auth/signup/phone/send-otp',json=request).status_code==401


def test_phone_session_expiry_and_missing_phone_block_activation(client):
    person=create(client);request=password_stage(client,person)
    db.collection('email-activation').document(str(person['id'])).update({'phoneExpires':time.time()-1})
    assert client.post('/api/auth/signup/phone/send-otp',json=request).status_code==401
    assert auth.get_user(str(person['id'])).disabled


def test_phone_enable_failure_can_retry_without_sending_another_sms(client,monkeypatch):
    person=create(client);request=password_stage(client,person)
    assert client.post('/api/auth/signup/phone/send-otp',json=request).status_code==200
    update=auth.update_user
    def fail_enable(uid,**kwargs):
        if kwargs.get('disabled') is False:raise RuntimeError('synthetic outage')
        return update(uid,**kwargs)
    monkeypatch.setattr(auth,'update_user',fail_enable)
    assert client.post('/api/auth/signup/phone/verify-otp',json=request|{'otp':'123456'}).status_code==502
    assert auth.get_user(str(person['id'])).disabled
    monkeypatch.setattr(auth,'update_user',update)
    assert client.post('/api/auth/signup/phone/verify-otp',json=request|{'otp':'123456'}).status_code==200


def test_simultaneous_phone_completion_does_not_disable_activated_account(client):
    from concurrent.futures import ThreadPoolExecutor
    person=create(client);request=password_stage(client,person)
    assert client.post('/api/auth/signup/phone/send-otp',json=request).status_code==200
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses=list(pool.map(lambda _:client.post('/api/auth/signup/phone/verify-otp',json=request|{'otp':'123456'}),range(2)))
    assert sum(r.status_code==200 for r in responses)==1
    assert all(r.status_code in (200,401,409) for r in responses)
    assert not auth.get_user(str(person['id'])).disabled
    assert get('employees',person['id'])['activationStatus']=='ACTIVE'


def test_enrolled_sms_scope_rejects_unknown_and_deleted_contacts(client,monkeypatch):
    person=create(client)
    monkeypatch.setattr(messaging.settings,'allow_real_messages',True)
    monkeypatch.setattr(messaging.settings,'msg91_dispatch_enabled',True)
    monkeypatch.setattr(messaging.settings,'sms_registered_recipients_enabled',True)
    monkeypatch.setattr(messaging.settings,'approved_sms_recipients','')
    number=messaging.normalize_phone(person['phone'])
    messaging.recipient_allowed('msg91',number)
    with pytest.raises(HTTPException): messaging.recipient_allowed('msg91','919000000099')
    db.collection('employees').document(str(person['id'])).update({'deleted':True})
    with pytest.raises(HTTPException): messaging.recipient_allowed('msg91',number)


def test_send_otp_reports_unknown_and_already_active_codes(client):
    assert client.post('/api/auth/signup/send-otp',json={'employeeCode':'NOPE'+uuid.uuid4().hex[:6]}).status_code==404
    person=create(client);activate_employee(client,person['employeeCode'])
    response=client.post('/api/auth/signup/send-otp',json={'employeeCode':person['employeeCode']})
    assert response.status_code==409 and 'already activated' in response.json()['message']


def test_wrong_otps_report_attempts_left_and_correct_otp_still_works(client):
    person=create(client);code=person['employeeCode']
    assert client.post('/api/auth/signup/send-otp',json={'employeeCode':code}).json()['data']['stage']=='EMAIL'
    for left in (4,3,2):
        response=client.post('/api/auth/signup/verify-otp',json={'employeeCode':code,'otp':'000000'})
        assert response.status_code==401 and f'{left} attempts left' in response.json()['message']
    assert client.post('/api/auth/signup/verify-otp',json={'employeeCode':code,'otp':'123456'}).status_code==200


def test_locked_email_otp_can_be_resent_immediately(client):
    person=create(client);code=person['employeeCode']
    client.post('/api/auth/signup/send-otp',json={'employeeCode':code})
    for _ in range(5): client.post('/api/auth/signup/verify-otp',json={'employeeCode':code,'otp':'000000'})
    locked=client.post('/api/auth/signup/verify-otp',json={'employeeCode':code,'otp':'123456'})
    assert locked.status_code==401 and 'Resend' in locked.json()['message']
    assert client.post('/api/auth/signup/send-otp',json={'employeeCode':code}).status_code==200
    assert client.post('/api/auth/signup/verify-otp',json={'employeeCode':code,'otp':'123456'}).status_code==200


def test_phone_pending_employee_resumes_at_phone_step(client):
    person=create(client);old=password_stage(client,person)
    response=client.post('/api/auth/signup/send-otp',json={'employeeCode':person['employeeCode']})
    assert response.status_code==200
    data=response.json()['data']
    assert data['stage']=='PHONE' and '**' in data['maskedPhone'] and person['phone'] not in response.text
    assert client.post('/api/auth/signup/phone/send-otp',json=old).status_code==401
    request={'employeeCode':person['employeeCode'],'phoneVerificationToken':data['phoneVerificationToken']}
    assert client.post('/api/auth/signup/phone/send-otp',json=request).status_code==200
    wrong=client.post('/api/auth/signup/phone/verify-otp',json=request|{'otp':'000000'})
    assert wrong.status_code==401 and '4 attempts left' in wrong.json()['message']
    assert client.post('/api/auth/signup/phone/verify-otp',json=request|{'otp':'000000'}).status_code==401
    assert client.post('/api/auth/signup/phone/verify-otp',json=request|{'otp':'123456'}).status_code==200
    assert get('employees',person['id'])['activationStatus']=='ACTIVE'
