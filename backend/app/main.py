import logging
import asyncio
from contextlib import asynccontextmanager, suppress
import os
import secrets
import time
from datetime import datetime, timezone, date
from typing import Any

import httpx
from fastapi import FastAPI, Depends, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from firebase_admin import auth, firestore
from pydantic import ValidationError
from botocore.exceptions import BotoCoreError, ClientError
from google.cloud.firestore_v1.base_query import FieldFilter
from google.api_core.exceptions import Aborted,AlreadyExists,ServiceUnavailable,DeadlineExceeded

from .config import settings
from .models import EmployeeCreate, EmployeeIdentityCheck
from .employee_identity import save_identity, identity_conflicts
from .security import current_user, manager, require
from .store import db, get, rows, all_rows
from .messaging import notify
from .mobile_contracts import module_response,project_response
from .roster import refresh_project_roster
from .module_validation import validate_module, MODULE_FIELDS, WORK_STAGES, STATUSES

@asynccontextmanager
async def lifespan(_app):
    from .delivery import email_worker
    worker = asyncio.create_task(email_worker()) if settings.environment != 'local' else None
    try:
        yield
    finally:
        if worker:
            worker.cancel()
            with suppress(asyncio.CancelledError): await worker


app = FastAPI(title='Crompton PMS', version='1.0.0', lifespan=lifespan)
local_origins=['http://127.0.0.1:3008','http://127.0.0.1:3009'] if settings.environment in ('local','development') else []
app.add_middleware(CORSMiddleware, allow_origins=[settings.web_origin, 'http://127.0.0.1:3000']+local_origins, allow_methods=['GET','POST','PUT','DELETE'], allow_headers=['Authorization','Content-Type','Idempotency-Key'])
log = logging.getLogger('crompton')


def ok(data=None, message='Success'):
    if isinstance(data,dict):
        if 'active' in data: data=data|{'isActive':data['active']}
        if 'deleted' in data: data=data|{'isDeleted':data['deleted']}
    return {'success': True, 'message': message, 'data': data}


@app.exception_handler(HTTPException)
async def error(_request, exc):
    return JSONResponse({'success':False,'message':str(exc.detail),'data':None},status_code=exc.status_code)


@app.exception_handler(RequestValidationError)
async def validation_error(_request, exc):
    # Never echo request bodies, passwords, OTPs or tokens.
    return JSONResponse({'success':False,'message':'Invalid request fields','data':None},status_code=422)


@app.exception_handler(BotoCoreError)
@app.exception_handler(ClientError)
async def storage_error(_request, exc):
    return JSONResponse({'success':False,'message':'File provider is temporarily unavailable','data':None},status_code=502)


@app.exception_handler(Aborted)
@app.exception_handler(AlreadyExists)
async def concurrent_change(_request, exc):
    return JSONResponse({'success':False,'message':'Record changed; refresh and retry','data':None},status_code=409)


@app.exception_handler(ServiceUnavailable)
@app.exception_handler(DeadlineExceeded)
async def database_unavailable(_request, exc):
    return JSONResponse({'success':False,'message':'Database is temporarily unavailable','data':None},status_code=503)


@app.middleware('http')
async def audit(request: Request, call_next):
    started = time.monotonic()
    response = await call_next(request)
    log.info('request method=%s status=%s elapsed_ms=%d',request.method,response.status_code,(time.monotonic()-started)*1000)
    return response


@app.get('/health')
def health(): return {'status':'ok','environment':settings.environment,'project':settings.project_id}


@app.post('/api/auth/login')
async def login(body: dict):
    identifier = str(body.get('employeeCode','')).strip().lower()
    if len(identifier)>254 or not body.get('password'): raise HTTPException(401,'Invalid credentials')
    # Firebase owns password verification, throttling and refresh token issuance.
    email = identifier if '@' in identifier else f'{identifier}@accounts.crompton.invalid'
    if '@' in identifier:
        matches=rows('employees',[('email',identifier)],2)
        if len(matches)>1: raise HTTPException(401,'Invalid credentials')
        if matches:email=matches[0]['employeeCode'].lower()+'@accounts.crompton.invalid'
    host = os.getenv('FIREBASE_AUTH_EMULATOR_HOST')
    base = f'http://{host}/identitytoolkit.googleapis.com' if host else 'https://identitytoolkit.googleapis.com'
    async with httpx.AsyncClient(timeout=20) as client:
        result = await client.post(f'{base}/v1/accounts:signInWithPassword',params={'key':settings.firebase_api_key},json={'email':email,'password':body.get('password'),'returnSecureToken':True})
    if result.status_code != 200: raise HTTPException(401,'Invalid credentials')
    data = result.json()
    user = get('employees',data['localId'])
    if not user or not user.get('active') or user.get('activationStatus') == 'PENDING': raise HTTPException(401,'Invalid credentials')
    return ok({**user,'userId':user['id'],'token':data['idToken']})


@app.post('/api/auth/logout')
def logout(user=Depends(current_user)):
    auth.revoke_refresh_tokens(str(user['id']))
    return ok()


@app.get('/api/users/me')
def me(user=Depends(current_user)): return ok(user|{'userId':user['id']})


@app.post('/api/employees')
async def provision(body: EmployeeCreate, user=Depends(current_user)):
    manager(user)
    if body.role in ('CAPTAIN','PROJECT_CONTROLLER'): require(user,'CAPTAIN')
    uid = str(secrets.randbelow(900000)+100000)
    password = 'Aa1!'+secrets.token_urlsafe(32)
    record = body.model_dump(exclude={'password'}) | {'id':int(uid),'active':False,'provisioning':True,'deleted':False,'phoneVerified':False,'emailVerified':False,'activationStatus':'PENDING','permissionVersion':1}
    record = save_identity(uid, record, creating=True)
    code = record['employeeCode']
    alias = code.lower()+'@accounts.crompton.invalid'
    created_auth = False
    try:
        auth.create_user(uid=uid,email=alias,password=password,display_name=body.name,disabled=True)
        created_auth = True
        auth.set_custom_user_claims(uid,{'role':body.role})
        db.collection('employees').document(uid).update({'active':True,'provisioning':firestore.DELETE_FIELD})
    except Exception as exc:
        db.collection('employees').document(uid).delete()
        if created_auth: auth.delete_user(uid)
        if isinstance(exc, (auth.EmailAlreadyExistsError,auth.UidAlreadyExistsError)):
            raise HTTPException(409,'Employee code or identifier already exists; retry') from None
        raise
    record['active'] = True
    record.pop('provisioning', None)
    from .delivery import event
    event(int(uid),'invitation','employee-invited-'+uid,code=code)
    return ok(record | {'activationEmailSent':False}, 'Employee created. Enter the employee code in Activate Account and tap Send OTP to receive the verification email.')


@app.post('/api/employees/validate-identity')
def validate_employee_identity(body: EmployeeIdentityCheck, user=Depends(current_user)):
    manager(user)
    if body.excludeEmployeeId is not None:
        target = get('employees', body.excludeEmployeeId)
        if not target: raise HTTPException(404, 'Employee not found')
        if target['role'] in ('CAPTAIN', 'PROJECT_CONTROLLER'): require(user, 'CAPTAIN')
    conflicts = identity_conflicts(all_rows('employees'), body.model_dump(), body.excludeEmployeeId)
    return ok({'valid': not conflicts, 'errors': conflicts})


@app.put('/api/employees/{uid}')
def edit_employee(uid: str, body: dict, user=Depends(current_user)):
    manager(user)
    target = get('employees',uid)
    if not target: raise HTTPException(404,'Employee not found')
    if target['role'] in ('CAPTAIN','PROJECT_CONTROLLER') or body.get('role') in ('CAPTAIN','PROJECT_CONTROLLER'): require(user,'CAPTAIN')
    if 'role' in body and body['role'] not in ('CAPTAIN','PROJECT_CONTROLLER','TEAM_LEADER','EMPLOYEE'): raise HTTPException(422,'Invalid role')
    changes={k:v for k,v in body.items() if k in ('name','email','phone','role')}
    if set(body)-set(changes): raise HTTPException(422,'Invalid employee fields')
    # Reuse creation validation without accepting credential or identity changes.
    try: checked=EmployeeCreate.model_validate({k:target.get(k,'') for k in ('employeeCode','name','email','phone','role')}|changes)
    except ValidationError: raise HTTPException(422,'Invalid employee fields') from None
    changes={k:getattr(checked,k) for k in changes}
    if 'email' in changes:changes['email']=str(changes['email']).strip().lower()
    if 'phone' in changes and changes['phone']!=target.get('phone'):changes['phoneVerified']=False
    changes['permissionVersion']=firestore.Increment(1)
    save_identity(uid, changes, creating=False)
    if 'role' in changes: auth.set_custom_user_claims(uid,{'role':changes['role']})
    auth.revoke_refresh_tokens(uid)
    return ok(get('employees',uid))


@app.api_route('/api/employees/{uid}/{action}',methods=['PUT','DELETE'])
def employee_status(uid: str, action: str, user=Depends(current_user)):
    manager(user)
    target=get('employees',uid)
    if not target: raise HTTPException(404,'Employee not found')
    if target['role'] in ('CAPTAIN','PROJECT_CONTROLLER'): require(user,'CAPTAIN')
    if uid==str(user['id']): raise HTTPException(409,'Cannot deactivate your own account')
    if action not in ('activate','delete','deactivate'): raise HTTPException(404,'Unknown action')
    if action=='activate' and target.get('deleted'): raise HTTPException(409,'Deleted accounts cannot be reactivated')
    active = action=='activate'
    auth.update_user(uid,disabled=not active)
    auth.revoke_refresh_tokens(uid)
    db.collection('employees').document(uid).update({'active':active,'deleted':action=='delete','permissionVersion':firestore.Increment(1)})
    if active:
        from .delivery import event
        event(int(uid),'activation','employee-activated-'+uid+'-'+str(time.time_ns()))
    return ok(get('employees',uid))


@app.delete('/api/employees/{uid}')
def deactivate_employee(uid: str,user=Depends(current_user)):
    return employee_status(uid,'deactivate',user)


def next_id(): return time.time_ns()//1000


@app.post('/api/projects')
def create_project(body: dict, user=Depends(current_user)):
    manager(user)
    if set(body)-(MODULE_FIELDS|{'projectCode','projectName','clientId'}): raise HTTPException(422,'Invalid project fields')
    for key in ('projectCode','projectName','moduleName'):
        if not isinstance(body.get(key),str) or not body[key].strip(): raise HTTPException(422,f'{key} is required')
    pid,mid=next_id(),next_id()+1
    module=validate_module({k:v for k,v in body.items() if k in MODULE_FIELDS})
    members=module['memberIds']
    project={k:body.get(k) for k in ('projectCode','projectName','clientId')}
    project.update(id=pid,active=True,deleted=False,memberIds=members,createdAt=datetime.now(timezone.utc).isoformat())
    module.update(id=mid,projectId=pid,projectCode=body['projectCode'],projectName=body['projectName'],active=True,deleted=False,status='IN_PROGRESS',workStage='WIP',memberIds=members,billingStatus=None)
    batch=db.batch()
    batch.create(db.collection('projects').document(str(pid)),project)
    batch.create(db.collection('modules').document(str(mid)),module)
    batch.commit()
    refresh_project_roster(pid)
    return ok(project_response(project))


@app.post('/api/modules')
def create_module(body: dict, user=Depends(current_user)):
    manager(user)
    project=get('projects',body.get('projectId'))
    if not project or not body.get('moduleName'): raise HTTPException(422,'Project and module name required')
    if not project.get('active') or project.get('deleted'): raise HTTPException(409,'Project is inactive')
    record=validate_module({k:v for k,v in body.items() if k!='projectId'})
    mid=next_id()
    record.update(id=mid,projectId=project['id'],projectCode=project['projectCode'],projectName=project['projectName'],active=True,deleted=False,status='IN_PROGRESS',workStage='WIP',billingStatus=None)
    db.collection('modules').document(str(mid)).create(record)
    refresh_project_roster(project['id'])
    return ok(module_response(record))


@app.put('/api/work-logs/{key}/{action}')
def decide_worklog(key: str, action: str, body: dict, user=Depends(current_user)):
    if action not in ('approve','reject'): raise HTTPException(404,'Unknown action')
    ref=db.collection('work-logs').document(key)
    @firestore.transactional
    def decide(tx):
        snapshot=ref.get(transaction=tx)
        if not snapshot.exists: raise HTTPException(404,'Work log not found')
        row=snapshot.to_dict()
        module_ref=db.collection('modules').document(str(row['moduleId']))
        module=module_ref.get(transaction=tx).to_dict()
        day=date.fromisoformat(row['workDate'])
        day_id=row['employeeId']*100000000+day.year*10000+day.month*100+day.day
        ledger_ref=db.collection('work-log-days').document(str(day_id))
        ledger=ledger_ref.get(transaction=tx).to_dict()
        if row['employeeId']==user['id']: raise HTTPException(403,'Cannot approve your own work')
        if user['role'] not in ('CAPTAIN','PROJECT_CONTROLLER') and not (user['role']=='TEAM_LEADER' and module and module.get('teamLeadId')==user['id']): raise HTTPException(403,'Permission denied')
        if row['approvalStatus']!='PENDING': raise HTTPException(409,'Already decided')
        changes={'approvalStatus':'APPROVED' if action=='approve' else 'REJECTED','rejectionReason':str(body.get('rejectionReason',''))[:1000],'approvedById':user['id'],'approvedByName':user['name'],'approvedAt':datetime.now(timezone.utc).isoformat()}
        tx.update(ref,changes)
        if action=='approve' and module:
            total=(module.get('completedSeconds') or 0)+(row.get('billableDurationSeconds') or 0)
            tx.update(module_ref,{'completedSeconds':total,'completedMinutes':total//60,'completedHours':total//3600})
        if action=='reject' and ledger:
            tx.update(ledger_ref,{'totalSeconds':max(0,ledger['totalSeconds']-(row.get('billableDurationSeconds') or 0)-(row.get('nonBillableDurationSeconds') or 0))})
        notification_id=next_id()
        tx.create(db.collection('notifications').document(str(notification_id)),{'id':notification_id,'userId':row['employeeId'],'title':'Timesheet '+changes['approvalStatus'].lower(),'message':row.get('moduleName','Timesheet'),'type':'TIMESHEET_APPROVED' if action=='approve' else 'TIMESHEET_REJECTED','moduleId':row['moduleId'],'moduleName':row.get('moduleName',''),'projectId':row['projectId'],'read':False,'pushPending':True,'createdAt':datetime.now(timezone.utc).isoformat()})
        return row|changes
    # The emulator and pessimistic cloud transactions may abort during reads,
    # which the SDK's commit-only retry loop does not retry. Start a fresh
    # transaction with jitter, preserving the decision's atomic/idempotent guard.
    for attempt in range(4):
        try: return ok(decide(db.transaction(max_attempts=1)))
        except (Aborted,ValueError) as exc:
            if not isinstance(exc,Aborted) and not isinstance(exc.__cause__,Aborted): raise
            if attempt==3: raise HTTPException(409,'Record changed; refresh and retry') from None
            time.sleep((secrets.randbelow(100)+25)/1000*(attempt+1))


from .storage import router as storage_router
app.include_router(storage_router)
from .recovery import router as recovery_router
app.include_router(recovery_router)
from .email_activation import router as email_activation_router
app.include_router(email_activation_router)


@app.api_route('/api/{collection}/{key}/{action}',methods=['PUT','POST'])
def privileged_action(collection: str,key: str,action: str,body: dict,user=Depends(current_user)):
    if action!='work-stage': manager(user)
    allowed={'modules','projects','module-change-requests','project-deactivation-requests','billing-status-change-requests'}
    if collection not in allowed: raise HTTPException(404,'Not found')
    if action in ('activate','delete') and collection not in ('projects','modules'): raise HTTPException(404,'Unknown action')
    if action=='work-stage' and collection!='modules': raise HTTPException(404,'Unknown action')
    if action in ('approve','reject') and not collection.endswith('requests'): raise HTTPException(404,'Unknown action')
    ref=db.collection(collection).document(key)
    @firestore.transactional
    def mutate(tx):
        snap=ref.get(transaction=tx)
        if not snap.exists: raise HTTPException(404,'Not found')
        row=snap.to_dict()
        children=list(db.collection('modules').where(filter=FieldFilter('projectId','==',row['id'])).stream(transaction=tx)) if collection=='projects' and action=='delete' else []
        if action=='work-stage':
            if user['role'] not in ('CAPTAIN','PROJECT_CONTROLLER') and not (user['role']=='TEAM_LEADER' and row.get('teamLeadId')==user['id']): raise HTTPException(403,'Permission denied')
        changes={}
        if action in ('activate','delete'):
            if action=='activate' and row.get('deleted'): raise HTTPException(409,'Deleted records cannot be reactivated')
            if collection=='modules' and action=='activate':
                parent=db.collection('projects').document(str(row['projectId'])).get(transaction=tx).to_dict()
                if not parent or not parent.get('active') or parent.get('deleted'): raise HTTPException(409,'Activate the project first')
            changes={'active':action=='activate','deleted':action=='delete'}
        elif action=='work-stage':
            if set(body)!={'workStage'} or body['workStage'] not in ('WIP','BILLING'): raise HTTPException(422,'Invalid work stage')
            parent=db.collection('projects').document(str(row['projectId'])).get(transaction=tx).to_dict()
            if not row.get('active') or row.get('deleted') or not parent or not parent.get('active') or parent.get('deleted'): raise HTTPException(409,'Module is inactive')
            if row.get('status')=='COMPLETED' and body['workStage']=='WIP': raise HTTPException(409,'Completed modules cannot return to WIP')
            changes={'workStage':body['workStage']}
        elif action in ('approve','reject'):
            require(user,'CAPTAIN')
            if row.get('requestedById')==user['id']: raise HTTPException(403,'Cannot approve your own request')
            if row.get('approvalStatus')!='PENDING': raise HTTPException(409,'Already decided')
            reason=body.get('reason',body.get('rejectionReason',''))
            if not isinstance(reason,str) or len(reason)>1000: raise HTTPException(422,'Invalid decision reason')
            changes={'approvalStatus':'APPROVED' if action=='approve' else 'REJECTED','status':'APPROVED' if action=='approve' else 'REJECTED','approvedById':user['id'],'decidedById':user['id'],'decidedByName':user['name'],'decidedAt':datetime.now(timezone.utc).isoformat(),'rejectionReason':reason,'decisionReason':reason}
            if action=='approve':
                target_collection='projects' if collection=='project-deactivation-requests' else 'modules'
                target_id=row['projectId'] if target_collection=='projects' else row['moduleId']
                target_ref=db.collection(target_collection).document(str(target_id))
                target=target_ref.get(transaction=tx).to_dict()
                if not target: raise HTTPException(409,'Request target no longer exists')
                if collection=='billing-status-change-requests':
                    require(user,'CAPTAIN')
                    if target.get('billingStatus')!=row['currentStatus']: raise HTTPException(409,'Billing changed; submit a new request')
                    tx.update(target_ref,{'billingStatus':row['requestedStatus'],'spocName':row.get('proposedSpocName',target.get('spocName','')),'remarks':row.get('remarks',''),'updatedById':user['id'],'updatedByName':user['name'],'updatedAt':changes['decidedAt']})
                elif collection=='project-deactivation-requests':
                    children=list(db.collection('modules').where(filter=FieldFilter('projectId','==',row['projectId'])).stream(transaction=tx))
                    tx.update(target_ref,{'active':False})
                elif collection=='module-change-requests':
                    if target.get('endDate')!=row.get('currentEndDate') or target.get('estimatedMinutes')!=row.get('currentEstimatedMinutes'): raise HTTPException(409,'Module changed; submit a new request')
                    edits={dst:row[src] for src,dst in [('proposedEndDate','endDate'),('proposedEstimatedMinutes','estimatedMinutes')] if row.get(src) is not None}
                    tx.update(target_ref,edits)
        else: raise HTTPException(404,'Unknown action')
        tx.update(ref,changes)
        for child in children: tx.update(child.reference,{'active':False})
        return row|changes
    result=mutate(db.transaction())
    if collection in ('projects','modules'): refresh_project_roster(result['id'] if collection=='projects' else result['projectId'])
    if collection=='project-deactivation-requests' and action=='approve': refresh_project_roster(result['projectId'])
    if collection in ('module-change-requests','billing-status-change-requests') and action in ('approve','reject'):
        kind=('PROJECT_CHANGE_' if collection=='module-change-requests' else 'BILLING_REVERSION_')+('APPROVED' if action=='approve' else 'REJECTED')
        link='changeRequestId' if collection=='module-change-requests' else 'billingChangeRequestId'
        notify(result['requestedById'],'Request '+action+'d',result.get('moduleName','Module request'),kind,next_id(),**{link:result['id']},moduleId=result.get('moduleId'),projectId=result['projectId'],projectName=result.get('projectName'),senderId=user['id'],senderName=user['name'])
    if collection=='modules' and action=='work-stage' and result['workStage']=='BILLING':
        for recipient in all_rows('employees'):
            if recipient.get('active') and recipient['role'] in ('CAPTAIN','PROJECT_CONTROLLER'):
                notify(recipient['id'],'Module submitted for billing',result['moduleName'],'PROJECT_SUBMITTED_FOR_BILLING',next_id(),moduleId=result['id'],moduleName=result['moduleName'],projectId=result['projectId'],projectName=result['projectName'],projectCode=result['projectCode'],senderId=user['id'],senderName=user['name'])
    return ok(result)


@app.post('/api/{collection}')
def create_request(collection: str,body: dict,user=Depends(current_user)):
    if collection not in ('module-change-requests','project-deactivation-requests','billing-status-change-requests'): raise HTTPException(404,'Not found')
    require(user,'CAPTAIN','PROJECT_CONTROLLER','TEAM_LEADER')
    if collection=='billing-status-change-requests': manager(user)
    key=next_id()
    if collection=='module-change-requests':
        manager(user)
        if any(k not in ('moduleId','proposedEndDate','proposedEstimatedMinutes','remarks') for k in body): raise HTTPException(422,'Invalid change request')
        m=get('modules',body.get('moduleId'))
        if not m: raise HTTPException(404,'Module not found')
        proposed={dst:body[src] for src,dst in [('proposedEndDate','endDate'),('proposedEstimatedMinutes','estimatedMinutes')] if body.get(src) is not None}
        if not proposed: raise HTTPException(422,'Propose a timeline or hours change')
        validate_module(proposed,m)
        record={**body,'moduleName':m['moduleName'],'projectId':m['projectId'],'projectCode':m['projectCode'],'projectName':m['projectName'],'currentEndDate':m.get('endDate'),'currentEstimatedMinutes':m.get('estimatedMinutes')}
    else:
        manager(user)
        target_key='projectId' if collection=='project-deactivation-requests' else 'moduleId'
        permitted={target_key,'remarks'}|({'requestedStatus'} if target_key=='moduleId' else set())
        if set(body)-permitted: raise HTTPException(422,'Invalid request fields')
        target=get('projects' if target_key=='projectId' else 'modules',body.get(target_key))
        if not target: raise HTTPException(404,'Request target not found')
        record={k:target[k] for k in ('projectId','projectCode','projectName','moduleName') if k in target}|body
        if target_key=='projectId': record.update(projectId=target['id'],projectCode=target['projectCode'],projectName=target['projectName'])
        else:
            if body.get('requestedStatus') not in ('INVOICE_YET_TO_BE_RAISED','INVOICE_RAISED','PART_PAYMENT_RECEIVED','FULL_PAYMENT_RECEIVED'): raise HTTPException(422,'Invalid billing status')
            record['currentStatus']=target.get('billingStatus')
            record['proposedStatus']=body['requestedStatus']
    record.update(id=key,requestedById=user['id'],requestedByName=user['name'],approvalStatus='PENDING',status='PENDING',createdAt=datetime.now(timezone.utc).isoformat())
    db.collection(collection).document(str(key)).create(record)
    if collection in ('module-change-requests','billing-status-change-requests'):
        for captain in all_rows('employees',[('role','CAPTAIN')]):
            if captain.get('active'):
                link='changeRequestId' if collection=='module-change-requests' else 'billingChangeRequestId'
                kind='PROJECT_CHANGE_REQUESTED' if collection=='module-change-requests' else 'BILLING_REVERSION_REQUESTED'
                notify(captain['id'],'Approval requested',record['moduleName'],kind,next_id(),**{link:key},moduleId=record['moduleId'],moduleName=record['moduleName'],projectId=record['projectId'],projectName=record['projectName'],senderId=user['id'],senderName=user['name'])
    return ok(record)


from .operations import router as operations_router
app.include_router(operations_router)


@app.get('/api/{collection}')
def listing(collection: str,request: Request,user=Depends(current_user),limit: int=100,after: str|None=None):
    if collection not in ('employees','projects','modules','activities','attendance','work-logs','notifications','module-change-requests','project-deactivation-requests','billing-status-change-requests'): raise HTTPException(404,'Not found')
    filters=[]
    if collection in ('employees','attendance','work-logs'): manager(user)
    if collection=='notifications': filters.append(('userId',user['id']))
    for k in ('role','moduleId','projectId','approvalStatus'):
        if k in request.query_params: filters.append((k,int(request.query_params[k]) if k.endswith('Id') else request.query_params[k]))
    if user['role'] not in ('CAPTAIN','PROJECT_CONTROLLER') and collection not in ('notifications','activities'):
        raise HTTPException(403,'Use scoped mobile access')
    return ok(rows(collection,filters,max(1,min(limit,200)),after))


from .reports import router as reports_router
app.include_router(reports_router)
