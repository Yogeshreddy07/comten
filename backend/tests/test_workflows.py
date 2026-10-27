import sys
import uuid
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import pytest
from conftest import activate_employee
from fastapi.testclient import TestClient
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app.main import app
from app.store import db,get
from app import storage
from app.reports import canonical_billing,module_billing,hours

client=TestClient(app)


@pytest.fixture(scope='module')
def tokens():
    result={}
    for role,code in [('captain','CAP001'),('controller','PC001'),('lead','TL001'),('employee','EMP001')]:
        response=client.post('/api/auth/login',json={'employeeCode':code,'password':'SyntheticPass123!'})
        assert response.status_code==200,response.text
        result[role]={'Authorization':'Bearer '+response.json()['data']['token']}
    return result


def test_firebase_auth_and_all_roles(tokens):
    assert client.get('/api/users/me').status_code==401
    assert client.get('/api/users/me',headers={'Authorization':'Bearer forged'}).status_code==401
    for role,headers in tokens.items():
        assert client.get('/api/users/me',headers=headers).status_code==200
        assert client.get('/api/reports/projects',headers=headers).status_code==(200 if role in ('captain','controller') else 403)
    assert client.post('/api/auth/login',json={'employeeCode':'unknown','password':'wrong'}).status_code==401


def test_employee_provisioning_permission_and_activation(tokens):
    body={'employeeCode':'SYN'+uuid.uuid4().hex[:10],'name':'Synthetic Employee','email':uuid.uuid4().hex+'@example.invalid','phone':'','role':'EMPLOYEE'}
    assert client.post('/api/employees',json=body,headers=tokens['employee']).status_code==403
    response=client.post('/api/employees',json=body,headers=tokens['captain'])
    assert response.status_code==200,response.text
    user=response.json()['data'];uid=user['id']
    assert 'temporaryPassword' not in user
    password=activate_employee(client,user['employeeCode'])
    assert client.post('/api/auth/login',json={'employeeCode':body['employeeCode'],'password':password}).status_code==200
    assert client.post('/api/auth/login',json={'employeeCode':body['email'],'password':password}).status_code==200
    assert client.put(f'/api/employees/{uid}',json={'name':'Updated synthetic'},headers=tokens['controller']).status_code==200
    db.collection('employees').document(str(uid)).update({'phoneVerified':True})
    assert client.put(f'/api/employees/{uid}',json={'phone':'9000000000'},headers=tokens['controller']).status_code==200
    assert get('employees',uid)['phoneVerified'] is False
    assert client.put(f'/api/employees/{uid}',json={'role':'CAPTAIN'},headers=tokens['controller']).status_code==403
    assert client.put(f'/api/employees/{uid}/deactivate',headers=tokens['captain']).status_code==200
    assert client.post('/api/auth/login',json={'employeeCode':body['employeeCode'],'password':password}).status_code==401
    assert client.put(f'/api/employees/{uid}/activate',headers=tokens['captain']).status_code==200


def test_project_module_change_and_financial_workflows(tokens):
    body={'projectCode':'SYN-'+uuid.uuid4().hex[:6],'projectName':'Synthetic workflow','moduleName':'Design','clientId':'TEST-CLIENT','teamLeadId':3,'memberIds':[4],'estimatedMinutes':1200}
    assert client.post('/api/projects',json=body,headers=tokens['employee']).status_code==403
    response=client.post('/api/projects',json=body,headers=tokens['controller']);assert response.status_code==200,response.text
    p=response.json()['data'];m=p['modules'][0];mid=m['id']
    assert client.put(f'/api/modules/{mid}',json={'estimatedMinutes':1},headers=tokens['controller']).status_code==422
    r=client.post('/api/module-change-requests',json={'moduleId':mid,'proposedEstimatedMinutes':1500},headers=tokens['controller']);assert r.status_code==200,r.text
    key=r.json()['data']['id']
    assert client.put(f'/api/module-change-requests/{key}/approve',json={},headers=tokens['controller']).status_code==403
    assert client.put(f'/api/module-change-requests/{key}/approve',json={},headers=tokens['captain']).status_code==200
    assert get('modules',mid)['estimatedMinutes']==1500
    assert client.put(f'/api/modules/{mid}/work-stage',json={'workStage':'BILLING'},headers=tokens['lead']).status_code==200
    assert client.put(f'/api/billing/{mid}',json={'status':'FULL_PAYMENT_RECEIVED','spocName':'DEMO'},headers=tokens['controller']).status_code==200
    r=client.put(f'/api/billing/{mid}',json={'status':'INVOICE_RAISED','spocName':'DEMO'},headers=tokens['controller'])
    assert r.status_code==200,r.text
    assert r.json()['data']['reversionPending']
    assert get('modules',mid)['billingStatus']=='FULL_PAYMENT_RECEIVED'
    # Re-submitting while the Captain has not decided must not queue a duplicate.
    pending=lambda:[q for q in db.collection('billing-status-change-requests').where('moduleId','==',mid).stream() if q.to_dict()['approvalStatus']=='PENDING']
    for _ in range(2):
        again=client.put(f'/api/billing/{mid}',json={'status':'INVOICE_RAISED','spocName':'DEMO'},headers=tokens['controller'])
        assert again.status_code==409 and 'already pending Captain approval' in again.json()['message']
    assert len(pending())==1
    listed=lambda:next(r for r in client.get('/api/billing',headers=tokens['controller']).json()['data'] if r['moduleId']==mid)
    assert listed()['reversionPending'] is True
    request_id=pending()[0].id
    assert client.put(f'/api/billing-status-change-requests/{request_id}/reject',json={'reason':'no'},headers=tokens['captain']).status_code==200
    assert listed()['reversionPending'] is False
    assert client.put(f'/api/billing/{mid}',json={'status':'INVOICE_RAISED','spocName':'DEMO'},headers=tokens['controller']).status_code==200
    assert len(pending())==1
    assert client.put(f'/api/billing/{mid}',json={'status':'bogus'},headers=tokens['captain']).status_code==422


def test_timesheet_race_commits_once_and_uses_billable_progress(tokens):
    key=str(time.time_ns()//1000)
    m=get('modules',101);before=m.get('completedSeconds',0)
    db.collection('work-logs').document(key).set({'id':int(key),'employeeId':4,'employeeCode':'EMP001','employeeName':'Demo Employee','moduleId':101,'moduleName':'Structural Design','projectId':100,'projectCode':'SYN-001','projectName':'Synthetic Office Project','teamLeadId':3,'workDate':'2026-10-14','billableDurationSeconds':3600,'nonBillableDurationSeconds':1800,'approvalStatus':'PENDING'})
    assert client.put(f'/api/work-logs/{key}/approve',json={},headers=tokens['employee']).status_code==403
    with ThreadPoolExecutor(max_workers=2) as pool:
        results=list(pool.map(lambda _:client.put(f'/api/work-logs/{key}/approve',json={},headers=tokens['lead']).status_code,range(2)))
    assert sorted(results)==[200,409]
    assert get('modules',101)['completedSeconds']==before+3600
    assert get('work-logs',key)['approvalStatus']=='APPROVED'
    db.collection('work-logs').document(key).delete()
    db.collection('modules').document('101').update({'completedSeconds':before,'completedMinutes':before//60,'completedHours':before//3600})


def test_all_report_contracts_and_ranges(tokens):
    urls=['attendance/employees','attendance/employees/4?year=2026&month=10','working-hours/employees','working-hours/employees/4?from=2026-10-01&to=2026-10-15','projects','projects/100','projects/100/modules/101','billing/projects/100','billing/modules/101','clients','clients/DEMO-CLIENT','billing-status']
    for path in urls:
        r=client.get('/api/reports/'+path,headers=tokens['captain']);assert r.status_code==200,(path,r.text)
    assert client.get('/api/reports/attendance/employees/4?month=13',headers=tokens['captain']).status_code==422
    assert client.get('/api/reports/working-hours/employees/4?from=2026-10-15&to=2026-10-01',headers=tokens['captain']).status_code==422
    assert hours({'inTime':'2026-10-01T09:30:00+05:30','outTime':'2026-10-01T19:00:59+05:30'})==9.5
    assert canonical_billing({'billingStatus':'PART_PAYMENT_RECEIVED'})=='PARTLY_PAID'
    result=module_billing({'id':1,'moduleName':'Demo','estimatedMinutes':600,'billingStatus':'INVOICE_RAISED'},[{'billableDurationSeconds':3600}])
    assert result['billableHours']==1 and result['billedHours']==1 and result['unbilledHours']==9


def test_r2_ownership_and_fail_closed(tokens,monkeypatch):
    body={'name':'synthetic.pdf','contentType':'application/pdf','size':1024}
    assert client.post('/api/files/authorize-upload',json=body,headers=tokens['employee']).status_code==503
    assert client.post('/api/files/authorize-upload',json=body|{'name':'../../secret'},headers=tokens['employee']).status_code==422
    class S3:
        def generate_presigned_url(self,*args,**kw): return 'https://synthetic.r2.invalid/signed'
        def head_object(self,**kw): return {'ContentLength':1024,'ContentType':'application/pdf','ETag':'synthetic-etag'}
        def get_object(self,**kw):
            import io
            return {'Body':io.BytesIO(b'%PDF-1.7 synthetic')}
        def delete_object(self,**kw): return {}
    monkeypatch.setattr(storage,'client',lambda:S3())
    r=client.post('/api/files/authorize-upload',json=body,headers=tokens['employee']);assert r.status_code==200
    key=r.json()['data']['id']
    assert client.get(f'/api/files/{key}/download',headers=tokens['lead']).status_code==404
    assert client.get(f'/api/files/{key}/download',headers=tokens['employee']).status_code==409
    assert client.post(f'/api/files/{key}/complete',headers=tokens['employee']).status_code==200
    assert client.get(f'/api/files/{key}/download',headers=tokens['employee']).status_code==200
    assert client.delete(f'/api/files/{key}',headers=tokens['employee']).status_code==200


def test_validation_does_not_echo_secrets(tokens):
    r=client.post('/api/employees',json={'password':'NeverEchoThisSecret'},headers=tokens['captain'])
    assert r.status_code==422 and 'NeverEchoThisSecret' not in r.text


def test_recovery_is_single_use_and_counters_commit(tokens):
    code='REC'+uuid.uuid4().hex[:8]
    response=client.post('/api/employees',json={'employeeCode':code,'name':'Recovery synthetic','email':'recover@example.invalid','role':'EMPLOYEE'},headers=tokens['captain'])
    assert response.status_code==200,response.text
    uid=response.json()['data']['id']
    activate_employee(client,code)
    request={'employeeCode':code,'email':'recover@example.invalid'}
    assert client.post('/api/auth/forgot-password/send-otp',json=request).status_code==200
    otp='123456'
    assert 'otp' not in get('recovery',uid)
    assert client.post('/api/auth/forgot-password/verify-otp',json=request|{'otp':'000000'}).status_code==401
    assert get('recovery',uid)['attempts']==1
    result=client.post('/api/auth/forgot-password/verify-otp',json=request|{'otp':otp})
    assert result.status_code==200,result.text
    assert client.post('/api/auth/forgot-password/verify-otp',json=request|{'otp':otp}).status_code==401
    body={'employeeCode':code,'resetToken':result.json()['data']['resetToken'],'newPassword':'RecoveredSynthetic123!','confirmPassword':'RecoveredSynthetic123!'}
    assert client.post('/api/auth/forgot-password/reset',json=body).status_code==200
    assert client.post('/api/auth/forgot-password/reset',json=body).status_code==401
    assert client.post('/api/auth/login',json={'employeeCode':code,'password':'RecoveredSynthetic123!'}).status_code==200


def test_assignment_validation_lifecycle_and_stale_approval(tokens):
    response=client.post('/api/projects',json={'projectCode':'LIFE-'+uuid.uuid4().hex[:6],'projectName':'Lifecycle synthetic','moduleName':'Design','teamLeadId':3,'memberIds':[4],'estimatedMinutes':60},headers=tokens['controller'])
    assert response.status_code==200,response.text
    p=response.json()['data'];mid=p['modules'][0]['id']
    r=client.post('/api/modules',json={'projectId':p['id'],'moduleName':'Second','teamLeadId':3,'memberIds':[]},headers=tokens['controller'])
    assert r.status_code==200 and 3 in r.json()['data']['memberIds']
    for body in ({'teamLeadId':4},{'memberIds':['4']},{'area':-1},{'moduleName':''}):
        assert client.put(f'/api/modules/{mid}',json=body,headers=tokens['controller']).status_code==422
    assert client.put(f'/api/modules/{mid}/work-stage',json={'workStage':'INVALID'},headers=tokens['lead']).status_code==422
    assert client.put(f'/api/projects/{p["id"]}/work-stage',json={'workStage':'BILLING'},headers=tokens['lead']).status_code==404
    request={'moduleId':mid,'proposedEstimatedMinutes':90}
    first=client.post('/api/module-change-requests',json=request,headers=tokens['controller']).json()['data']['id']
    # Only one change request per module may await the Captain at a time.
    duplicate=client.post('/api/module-change-requests',json=request|{'proposedEstimatedMinutes':100},headers=tokens['controller'])
    assert duplicate.status_code==409 and 'already pending Captain approval' in duplicate.json()['message']
    assert client.put(f'/api/module-change-requests/{first}/approve',json={},headers=tokens['captain']).status_code==200
    second=client.post('/api/module-change-requests',json=request|{'proposedEstimatedMinutes':100},headers=tokens['controller']).json()['data']['id']
    db.collection('modules').document(str(mid)).update({'estimatedMinutes':95})
    assert client.put(f'/api/module-change-requests/{second}/approve',json={},headers=tokens['captain']).status_code==409
    assert client.put(f'/api/modules/{mid}/work-stage',json={'workStage':'BILLING'},headers=tokens['lead']).status_code==200
    assert client.delete(f'/api/projects/{p["id"]}',headers=tokens['captain']).status_code==200
    assert client.put(f'/api/billing/{mid}',json={'status':'INVOICE_RAISED'},headers=tokens['controller']).status_code==409
    assert client.post('/api/modules',json={'projectId':p['id'],'moduleName':'Forbidden'},headers=tokens['controller']).status_code==409
    assert client.put('/api/employees/4',json={'email':'invalid'},headers=tokens['captain']).status_code==422


def test_reassigned_leader_receives_pending_approval_scope(tokens):
    person=client.post('/api/employees',json={'employeeCode':'LEAD'+uuid.uuid4().hex[:8],'name':'Synthetic replacement lead','email':'lead@example.invalid','role':'TEAM_LEADER'},headers=tokens['controller']).json()['data']
    password=activate_employee(client,person['employeeCode'])
    p=client.post('/api/projects',json={'projectCode':'MOVE-'+uuid.uuid4().hex[:6],'projectName':'Synthetic reassignment','moduleName':'Design','teamLeadId':3,'memberIds':[4]},headers=tokens['controller']).json()['data']
    m=p['modules'][0];key=str(time.time_ns()//1000)
    db.collection('work-logs').document(key).set({'id':int(key),'employeeId':4,'moduleId':m['id'],'projectId':p['id'],'teamLeadId':3,'workDate':'2026-10-15','approvalStatus':'PENDING','billableDurationSeconds':60,'nonBillableDurationSeconds':0})
    r=client.put(f'/api/modules/{m["id"]}',json={'teamLeadId':person['id'],'memberIds':[4]},headers=tokens['controller'])
    assert r.status_code==200,r.text
    assert get('work-logs',key)['teamLeadId']==person['id']
    assert 3 not in get('modules',m['id'])['memberIds']
    assert client.put(f'/api/work-logs/{key}/approve',json={},headers=tokens['lead']).status_code==403
    replacement=client.post('/api/auth/login',json={'employeeCode':person['employeeCode'],'password':password}).json()['data']['token']
    assert client.put(f'/api/work-logs/{key}/approve',json={},headers={'Authorization':'Bearer '+replacement}).status_code==200



def test_phone_otp_cooldown_expiry_attempts_and_replay(tokens):
    from app.messaging import normalize_phone
    uid=4;person=get('employees',uid);old_phone=person.get('phone','')
    ref=db.collection('phone-challenges').document(str(uid))
    rate=db.collection('phone-rate-limits').document(__import__('hashlib').sha256(b'919000000001').hexdigest())
    rate.delete();ref.delete()
    db.collection('employees').document(str(uid)).update({'phone':'9000000001','phoneVerified':False})
    try:
        assert client.post('/api/auth/phone/send',json={'phone':'9000000002'},headers=tokens['employee']).status_code==403
        assert client.post('/api/auth/phone/send',json={'phone':'+91 90000 00001'},headers=tokens['employee']).status_code==200
        assert client.post('/api/auth/phone/send',json={'phone':'9000000001'},headers=tokens['employee']).status_code==429
        assert 'otp' not in ref.get().to_dict()
        for _ in range(5): assert client.post('/api/auth/phone/verify',json={'otp':'000000'},headers=tokens['employee']).status_code==401
        assert client.post('/api/auth/phone/verify',json={'otp':'123456'},headers=tokens['employee']).status_code==401
        assert ref.get().to_dict()['attempts']==5
        ref.update({'attempts':0,'expires':time.time()-1})
        assert client.post('/api/auth/phone/verify',json={'otp':'123456'},headers=tokens['employee']).status_code==401
        ref.update({'expires':time.time()+600})
        assert client.post('/api/auth/phone/verify',json={'otp':'123456'},headers=tokens['employee']).status_code==200
        assert client.post('/api/auth/phone/verify',json={'otp':'123456'},headers=tokens['employee']).status_code==401
        assert get('employees',uid)['phoneVerified'] is True
    finally:
        db.collection('employees').document(str(uid)).update({'phone':old_phone,'phoneVerified':person.get('phoneVerified',False)})
        ref.delete();rate.delete()


def test_msg91_firebase_linkage_concurrent_replay_and_changed_phone(tokens,monkeypatch):
    import asyncio
    from app import recovery
    person=get('employees',4);employee=db.collection('employees').document('4')
    ref=db.collection('phone-challenges').document('4');verified=[];minted=[]
    monkeypatch.setattr(recovery.settings,'environment','development')
    async def verify(phone,otp,request_id):
        assert phone=='919000000008' and otp=='123456'
        verified.append(phone);await asyncio.sleep(.15)
    def mint(uid):
        assert get('employees',uid)['phoneVerified'] is True
        minted.append(uid);return b'synthetic-custom-token'
    monkeypatch.setattr(recovery,'verify_msg91',verify)
    monkeypatch.setattr(recovery.auth,'create_custom_token',mint)
    def challenge():
        employee.update({'phone':'9000000008','phoneVerified':False})
        ref.set({'challengeId':uuid.uuid4().hex,'phone':'919000000008','sent':time.time(),'expires':time.time()+600,'attempts':0,'state':'SENT','widgetId':recovery.settings.msg91_widget_id,'providerRequestId':'synthetic-request'})
    try:
        challenge()
        assert client.post('/api/auth/phone/verify',json={'otp':'123456'}).status_code==401
        with ThreadPoolExecutor(max_workers=2) as pool:
            responses=list(pool.map(lambda _:client.post('/api/auth/phone/verify',json={'otp':'123456'},headers=tokens['employee']),range(2)))
        assert sorted(r.status_code for r in responses)==[200,401]
        assert verified==['919000000008'] and minted==['4']
        assert next(r for r in responses if r.status_code==200).json()['data']['customToken']=='synthetic-custom-token'
        challenge()
        async def changed_phone(phone,otp,request_id): employee.update({'phone':'9000000009','phoneVerified':False})
        monkeypatch.setattr(recovery,'verify_msg91',changed_phone)
        assert client.post('/api/auth/phone/verify',json={'otp':'123456'},headers=tokens['employee']).status_code==401
        assert minted==['4'] and get('employees',4)['phoneVerified'] is False
    finally:
        employee.update({'phone':person.get('phone',''),'phoneVerified':person.get('phoneVerified',False)});ref.delete()


def test_simultaneous_change_request_submits_create_one_request(tokens):
    body={'projectCode':'DUP-'+uuid.uuid4().hex[:6],'projectName':'Duplicate submit synthetic','moduleName':'Design','teamLeadId':3,'memberIds':[4],'estimatedMinutes':60}
    mid=client.post('/api/projects',json=body,headers=tokens['controller']).json()['data']['modules'][0]['id']
    request={'moduleId':mid,'proposedEstimatedMinutes':120}
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses=list(pool.map(lambda _:client.post('/api/module-change-requests',json=request,headers=tokens['controller']),range(4)))
    assert sorted(r.status_code for r in responses)==[200,409,409,409]
    assert len(list(db.collection('module-change-requests').where('moduleId','==',mid).stream()))==1


def test_delay_request_blocks_resubmission_until_decided(tokens):
    body={'projectCode':'DLY-'+uuid.uuid4().hex[:6],'projectName':'Delay request synthetic','moduleName':'Design','teamLeadId':3,'memberIds':[4],'estimatedMinutes':60}
    mid=client.post('/api/projects',json=body,headers=tokens['controller']).json()['data']['modules'][0]['id']
    submit=lambda:client.post('/api/notifications/delay-requests',json={'moduleId':mid,'reason':'Waiting on client inputs'},headers=tokens['lead'])
    first=submit()
    assert first.status_code==200,first.text
    rid=first.json()['data']['delayRequestId']
    again=submit()
    assert again.status_code==409 and 'already pending' in again.text
    assert client.put(f'/api/delay-requests/{rid}/approve',json={},headers=tokens['lead']).status_code==403
    approved=client.put(f'/api/delay-requests/{rid}/approve',json={},headers=tokens['controller'])
    assert approved.status_code==200 and approved.json()['data']['approvalStatus']=='APPROVED'
    assert client.put(f'/api/delay-requests/{rid}/reject',json={},headers=tokens['captain']).status_code==409
    second=submit()
    assert second.status_code==200,second.text
    rid2=second.json()['data']['delayRequestId']
    assert client.put(f'/api/delay-requests/{rid2}/reject',json={'reason':'Not justified'},headers=tokens['captain']).json()['data']['approvalStatus']=='REJECTED'
    assert submit().status_code==200
    decided=[n for n in db.collection('notifications').where('delayRequestId','in',[rid,rid2]).stream() if n.to_dict()['type'] in ('DELAY_APPROVED','DELAY_REJECTED')]
    assert sorted(n.to_dict()['type'] for n in decided)==['DELAY_APPROVED','DELAY_REJECTED']
