from datetime import datetime,timezone
from fastapi import APIRouter,Depends,HTTPException,Request
from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from .store import db,get,get_many,rows,all_rows,transact
from .approvals import claim_pending,has_pending
from .security import current_user,manager,require
from .messaging import notify
from .roster import refresh_project_roster
from .module_validation import validate_module
from .mobile_contracts import module_response

router=APIRouter(prefix='/api')


def billing_row(m, records=None, pending=None):
    project=(records.get(('projects',str(m['projectId']))) if records is not None else get('projects',m['projectId'])) or {}
    lead=(records.get(('employees',str(m['teamLeadId']))) if records is not None else get('employees',m['teamLeadId'])) if m.get('teamLeadId') else None
    status=m.get('billingStatus')
    stage='COMPLETED' if status=='FULL_PAYMENT_RECEIVED' else 'TO_BE_BILLED' if not status or status=='INVOICE_YET_TO_BE_RAISED' else 'PENDING'
    return {**m,'moduleId':m['id'],'moduleStatus':m.get('status'),'status':status,'stage':stage,'editable':bool(m.get('active',True) and project.get('active') and not project.get('deleted')),'teamLeadName':lead.get('name') if lead else None,'updatedByName':m.get('updatedByName'),'reversionPending':pending.get(m['id'],False) if pending is not None else has_pending('billing-status-change-requests',m['id'])}


def billing_rows(modules):
    """Enrich the list in two batch reads, including stale-lock verification."""
    keys=[]
    for m in modules:
        keys.extend([('projects',m['projectId']),
                     ('pending-approvals',f"billing-status-change-requests-{m['id']}")])
        if m.get('teamLeadId'): keys.append(('employees',m['teamLeadId']))
    records=get_many(keys, fields=['active','deleted','name','requestId'])
    held={m['id']:records.get(('pending-approvals',f"billing-status-change-requests-{m['id']}"),{}).get('requestId') for m in modules}
    requests=get_many([('billing-status-change-requests',key) for key in held.values() if key is not None],fields=['approvalStatus'])
    pending={mid:requests.get(('billing-status-change-requests',str(key)),{}).get('approvalStatus')=='PENDING' for mid,key in held.items()}
    return [billing_row(m, records, pending) for m in modules]


@router.get('/billing')
def billing(user=Depends(current_user)):
    manager(user)
    modules=[m for m in all_rows('modules',[('workStage','BILLING')]) if not m.get('deleted')]
    return {'success':True,'message':'Billing loaded','data':billing_rows(modules)}


@router.put('/billing/{mid}')
def update_billing(mid: int,body: dict,user=Depends(current_user)):
    manager(user)
    statuses=['INVOICE_YET_TO_BE_RAISED','INVOICE_RAISED','PART_PAYMENT_RECEIVED','FULL_PAYMENT_RECEIVED']
    if body.get('status') not in statuses: raise HTTPException(422,'Invalid billing status')
    ref=db.collection('modules').document(str(mid))
    @firestore.transactional
    def update(tx):
        snap=ref.get(transaction=tx)
        if not snap.exists: raise HTTPException(404,'Module not found')
        m=snap.to_dict()
        p=db.collection('projects').document(str(m['projectId'])).get(transaction=tx).to_dict()
        if not p or not p.get('active') or p.get('deleted') or not m.get('active',True) or m.get('deleted') or m.get('workStage')!='BILLING': raise HTTPException(409,'Module is not editable for billing')
        if m.get('billingStatus')=='FULL_PAYMENT_RECEIVED' and body['status']!='FULL_PAYMENT_RECEIVED' and user['role']!='CAPTAIN':
            key=int(datetime.now(timezone.utc).timestamp()*1000000)
            claim_pending(tx,'billing-status-change-requests',mid,key)
            tx.create(db.collection('billing-status-change-requests').document(str(key)),{'id':key,'moduleId':mid,'moduleName':m['moduleName'],'projectId':m['projectId'],'projectCode':m['projectCode'],'projectName':m['projectName'],'requestedById':user['id'],'requestedByName':user['name'],'requestedStatus':body['status'],'proposedStatus':body['status'],'proposedSpocName':body.get('spocName',''),'currentStatus':m['billingStatus'],'approvalStatus':'PENDING','status':'PENDING','remarks':body.get('remarks',''),'createdAt':datetime.now(timezone.utc).isoformat()})
            return billing_row(m)|{'reversionPending':True,'requestId':key}
        changes={'billingStatus':body['status'],'spocName':str(body.get('spocName',''))[:100],'remarks':str(body.get('remarks',''))[:1000],'updatedById':user['id'],'updatedByName':user['name'],'updatedAt':datetime.now(timezone.utc).isoformat()}
        tx.update(ref,changes);return billing_row(m|changes)
    result=update(db.transaction())
    request_id=result.pop('requestId',None)
    if request_id:
        for captain in all_rows('employees',[('role','CAPTAIN')]):
            if captain.get('active'): notify(captain['id'],'Billing approval requested',result['moduleName'],'BILLING_REVERSION_REQUESTED',request_id+captain['id'],billingChangeRequestId=request_id,moduleId=mid,moduleName=result['moduleName'],projectId=result['projectId'],projectName=result['projectName'],senderId=user['id'],senderName=user['name'])
    return {'success':True,'message':'Billing updated','data':result}


@router.put('/modules/{mid}')
def update_module(mid: int,body: dict,user=Depends(current_user)):
    manager(user)
    m=get('modules',mid)
    if not m: raise HTTPException(404,'Module not found')
    allowed={'moduleName','teamLeadId','status','memberIds','billableActivityIds','nonBillableActivityIds','remarks','buildingClassification','structureClassification','numberOfFloors','area'}
    if any(k not in allowed for k in body): raise HTTPException(422,'Budget and timeline changes require approval')
    ref=db.collection('modules').document(str(mid))
    @firestore.transactional
    def update(tx):
        current=ref.get(transaction=tx).to_dict()
        if not current: raise HTTPException(404,'Module not found')
        changes=validate_module(body,current,transaction=tx)
        pending=[]
        if 'teamLeadId' in changes and changes['teamLeadId']!=current.get('teamLeadId'):
            # Read the query before writes so simultaneous submissions conflict
            # and retry against the same authoritative leader assignment.
            pending=[s for s in db.collection('work-logs').where(filter=FieldFilter('moduleId','==',mid)).stream(transaction=tx) if s.to_dict().get('approvalStatus')=='PENDING']
        tx.update(ref,changes)
        for snapshot in pending: tx.update(snapshot.reference,{'teamLeadId':changes['teamLeadId']})
        return changes
    body=update(db.transaction())
    if 'memberIds' in body or 'teamLeadId' in body:
        refresh_project_roster(m['projectId'])
    return {'success':True,'message':'Module updated','data':module_response(get('modules',mid))}


@router.delete('/modules/{key}')
@router.delete('/projects/{key}')
def deactivate(key: str,request: Request,user=Depends(current_user)):
    manager(user)
    collection=request.url.path.split('/')[2]
    record=get(collection,key)
    if not record: raise HTTPException(404,'Record not found')
    if collection=='projects' and user['role']=='PROJECT_CONTROLLER':
        modules=list(all_rows('modules',[('projectId',int(key))]))
        if any(m.get('workStage')=='BILLING' for m in modules):
            p=record;request_id=int(datetime.now(timezone.utc).timestamp()*1000000)
            @firestore.transactional
            def submit(tx):
                claim_pending(tx,'project-deactivation-requests',p['id'],request_id)
                tx.create(db.collection('project-deactivation-requests').document(str(request_id)),{'id':request_id,'projectId':p['id'],'projectName':p['projectName'],'projectCode':p['projectCode'],'requestedById':user['id'],'requestedByName':user['name'],'approvalStatus':'PENDING','status':'PENDING','createdAt':datetime.now(timezone.utc).isoformat()})
            transact(submit)
            return {'success':True,'message':'Deactivation submitted for Captain approval','data':p}
    ref=db.collection(collection).document(key)
    @firestore.transactional
    def disable(tx):
        children=list(db.collection('modules').where(filter=FieldFilter('projectId','==',int(key))).stream(transaction=tx)) if collection=='projects' else []
        tx.update(ref,{'active':False})
        for child in children: tx.update(child.reference,{'active':False})
    disable(db.transaction())
    refresh_project_roster(record['projectId'] if collection=='modules' else record['id'])
    return {'success':True,'message':'Deactivated','data':record|{'active':False}}


@router.post('/notifications/delay-requests')
def delay(body: dict,user=Depends(current_user)):
    require(user,'TEAM_LEADER')
    m=get('modules',body.get('moduleId'))
    if not m or m.get('teamLeadId')!=user['id']: raise HTTPException(403,'Permission denied')
    if not isinstance(body.get('reason'),str) or not body['reason'].strip() or len(body['reason'])>1000: raise HTTPException(422,'Reason is required')
    key=int(datetime.now(timezone.utc).timestamp()*1000000)
    record={'id':key,'moduleId':m['id'],'moduleName':m['moduleName'],'projectId':m['projectId'],'projectName':m['projectName'],'projectCode':m['projectCode'],'reason':body['reason'],'requestedById':user['id'],'requestedByName':user['name'],'approvalStatus':'PENDING','status':'PENDING','createdAt':datetime.now(timezone.utc).isoformat()}
    # One open delay request per module until a Captain/Project Controller decides it.
    @firestore.transactional
    def submit(tx):
        claim_pending(tx,'delay-requests',m['id'],key)
        tx.create(db.collection('delay-requests').document(str(key)),record)
    transact(submit)
    result=None
    for captain in all_rows('employees'):
        if captain.get('active') and captain['role'] in ('CAPTAIN','PROJECT_CONTROLLER'):
            result=notify(captain['id'],'Reason for delay',body['reason'],'DELAY_REQUESTED',key+captain['id'],delayRequestId=key,moduleId=m['id'],moduleName=m['moduleName'],projectId=m['projectId'],projectName=m['projectName'],projectCode=m['projectCode'],senderId=user['id'],senderName=user['name'],reason=body['reason'])
    return {'success':True,'message':'Delay reported','data':result}
