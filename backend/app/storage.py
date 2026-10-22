"""Private R2 capabilities: authorize by live application scope, never by file ID."""
import re
import secrets
import time
import io
import zipfile
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field, ConfigDict
import boto3
from botocore.config import Config
from firebase_admin import firestore
from .config import settings
from .security import current_user
from .store import db, get, rows, transact

router=APIRouter(prefix='/api/files')
Category=Literal['employee_document','project_attachment','timesheet_attachment','billing_document','profile_image']
MIMES={'application/pdf':b'%PDF-','image/jpeg':b'\xff\xd8\xff','image/png':b'\x89PNG\r\n\x1a\n','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':b'PK\x03\x04'}
class Upload(BaseModel):
    model_config=ConfigDict(extra='forbid')
    name: str=Field(min_length=1,max_length=150,pattern=r'^[\w. -]+$')
    contentType: str
    size: int=Field(gt=0,le=10*1024*1024)
    category: Category='employee_document'
    targetId: int|None=Field(default=None,gt=0)


def client():
    if not all((settings.r2_endpoint,settings.r2_bucket,settings.r2_access_key,settings.r2_secret_key)):
        raise HTTPException(503,'R2 is not configured')
    if not re.fullmatch(r'https://[a-f0-9]{32}(?:\.(?:eu|fedramp))?\.r2\.cloudflarestorage\.com',settings.r2_endpoint):
        raise HTTPException(503,'Invalid private R2 endpoint')
    if settings.environment=='development' and settings.r2_bucket!='crompton-pms-dev':
        raise HTTPException(503,'Development requires the dedicated Crompton bucket')
    return boto3.client('s3',endpoint_url=settings.r2_endpoint,aws_access_key_id=settings.r2_access_key,aws_secret_access_key=settings.r2_secret_key,region_name='auto',config=Config(signature_version='s3v4',connect_timeout=5,read_timeout=20,retries={'mode':'standard','max_attempts':2}))


def scope(category,target,user,write=False):
    manager=user['role'] in ('CAPTAIN','PROJECT_CONTROLLER')
    allowed=False
    if category in ('profile_image','employee_document'):
        person=get('employees',target)
        allowed=bool(person and person.get('active') and (target==user['id'] or category=='employee_document' and manager and (user['role']=='CAPTAIN' or person['role'] in ('EMPLOYEE','TEAM_LEADER'))))
    elif category in ('project_attachment','billing_document'):
        project=get('projects',target)
        allowed=bool(project and project.get('active') and not project.get('deleted') and (manager or category=='project_attachment' and user['id'] in project.get('memberIds',[])))
    elif category=='timesheet_attachment':
        log=get('work-logs',target)
        module=get('modules',log.get('moduleId')) if log else None
        project=get('projects',module.get('projectId')) if module else None
        allowed=bool(log and module and module.get('active') and project and project.get('active') and (manager or log.get('employeeId')==user['id'] or not write and user['role']=='TEAM_LEADER' and module.get('teamLeadId')==user['id']))
    if not allowed: raise HTTPException(404,'File scope not found')


def valid_key(row):
    return bool(re.fullmatch(r'v1/(employee_document|project_attachment|timesheet_attachment|billing_document|profile_image)/[0-9a-f]{64}',row.get('key','')))


def accessible(key,user,write=False):
    if not re.fullmatch(r'[a-f0-9]{32}',key): raise HTTPException(404,'File not found')
    row=get('files',key)
    if not row or not valid_key(row): raise HTTPException(404,'File not found')
    scope(row['category'],row['targetId'],user,write)
    if write and row['ownerId']!=user['id'] and user['role'] not in ('CAPTAIN','PROJECT_CONTROLLER'): raise HTTPException(404,'File not found')
    return row


def public(row):
    return {k:row[k] for k in ('id','ownerId','name','contentType','size','category','targetId','state','createdAt')}


@router.get('')
def listing(category: Category='employee_document',targetId: int|None=None,limit: int=Query(default=50,ge=1,le=100),after: str|None=None,user=Depends(current_user)):
    target=targetId or user['id'];scope(category,target,user)
    if after and not re.fullmatch(r'[a-f0-9]{32}',after): raise HTTPException(422,'Invalid cursor')
    result=rows('files',[('scopeStateKey',category+':'+str(target)+':READY')],limit,after)
    return {'success':True,'data':[public(row) for row in result if row['state']=='READY'],'message':'Files retrieved'}


@router.post('/authorize-upload')
def upload(body: Upload,user=Depends(current_user)):
    target=body.targetId or user['id'];scope(body.category,target,user,True)
    if body.contentType not in MIMES or body.category=='profile_image' and body.contentType not in ('image/jpeg','image/png'): raise HTTPException(422,'Unsupported file type')
    s3=client();token=secrets.token_hex(16);key=f'v1/{body.category}/{secrets.token_hex(32)}'
    now=time.time();ref=db.collection('files').document(token)
    quota=db.collection('file-rate-limits').document(str(user['id']))
    @firestore.transactional
    def reserve(tx):
        old=quota.get(transaction=tx).to_dict() or {}
        count=old.get('count',0) if old.get('window',0)>now-3600 else 0
        if count>=30: raise HTTPException(429,'Hourly upload limit reached')
        tx.set(quota,{'count':count+1,'window':old.get('window',now) if count else now,'expires':now+86400})
        tx.create(ref,{'id':token,'key':key,'ownerId':user['id'],'name':body.name,'contentType':body.contentType,'size':body.size,'category':body.category,'targetId':target,'scopeKey':body.category+':'+str(target),'state':'PENDING','createdAt':now,'expires':now+300})
    transact(reserve)
    try:
        url=s3.generate_presigned_url('put_object',Params={'Bucket':settings.r2_bucket,'Key':key,'ContentType':body.contentType,'ContentLength':body.size,'IfNoneMatch':'*'},ExpiresIn=300)
    except Exception:
        ref.update({'state':'FAILED'});raise
    return {'success':True,'data':{'id':token,'url':url,'expiresIn':300,'headers':{'Content-Type':body.contentType,'If-None-Match':'*'}},'message':'Upload authorized'}


@router.post('/{key}/complete')
def complete(key: str,user=Depends(current_user)):
    row=accessible(key,user,True)
    if row['ownerId']!=user['id']: raise HTTPException(404,'File not found')
    if row['state']=='READY': return {'success':True,'data':public(row),'message':'Upload verified'}
    if row['state']!='PENDING' or row['expires']<time.time(): raise HTTPException(409,'Upload authorization expired; select the file again')
    s3=client();meta=s3.head_object(Bucket=settings.r2_bucket,Key=row['key'])
    if meta['ContentLength']!=row['size'] or meta['ContentType']!=row['contentType']:
        db.collection('files').document(key).update({'state':'FAILED'})
        s3.delete_object(Bucket=settings.r2_bucket,Key=row['key']);raise HTTPException(422,'Uploaded file does not match authorization')
    etag=meta['ETag']
    stream=s3.get_object(Bucket=settings.r2_bucket,Key=row['key'],IfMatch=etag,Range='bytes=0-'+str(row['size']-1 if row['contentType'].endswith('spreadsheetml.sheet') else 8191))['Body']
    try: payload=stream.read(10*1024*1024+1)
    finally: stream.close()
    valid=payload.startswith(MIMES[row['contentType']]) and len(payload)<=10*1024*1024
    if valid and row['contentType'].endswith('spreadsheetml.sheet'):
        try:
            with zipfile.ZipFile(io.BytesIO(payload)) as workbook:
                names=set(workbook.namelist());entries=workbook.infolist()
                valid={'[Content_Types].xml','xl/workbook.xml'}<=names and len(entries)<=5000 and sum(item.file_size for item in entries)<=50*1024*1024 and not any(item.flag_bits&1 or '..' in item.filename.split('/') or item.filename.lower().endswith('vbaproject.bin') for item in entries)
        except (zipfile.BadZipFile,ValueError): valid=False
    if not valid:
        db.collection('files').document(key).update({'state':'FAILED'})
        s3.delete_object(Bucket=settings.r2_bucket,Key=row['key']);raise HTTPException(422,'File signature does not match its type')
    ref=db.collection('files').document(key)
    @firestore.transactional
    def finish(tx):
        current=ref.get(transaction=tx).to_dict()
        if not current or current['state'] not in ('PENDING','READY'): raise HTTPException(409,'Upload was cancelled')
        tx.update(ref,{'state':'READY','etag':etag,'scopeStateKey':row['scopeKey']+':READY'})
    transact(finish)
    return {'success':True,'data':public(get('files',key)),'message':'Upload verified'}


@router.get('/{key}/download')
def download(key: str,user=Depends(current_user)):
    row=accessible(key,user)
    if row['state']!='READY': raise HTTPException(409,'Upload not finalized')
    return {'success':True,'data':{'url':client().generate_presigned_url('get_object',Params={'Bucket':settings.r2_bucket,'Key':row['key'],'IfMatch':row['etag'],'ResponseContentDisposition':'attachment; filename="'+row['name']+'"'},ExpiresIn=120),'headers':{'If-Match':row['etag']},'expiresIn':120},'message':'Download authorized'}


@router.delete('/{key}')
def delete(key: str,user=Depends(current_user)):
    row=accessible(key,user,True);s3=client()
    db.collection('files').document(key).update({'state':'DELETING','scopeStateKey':row['scopeKey']+':DELETING'})
    # A PUT capability may still be in flight. Retain its tombstone beyond expiry.
    s3.delete_object(Bucket=settings.r2_bucket,Key=row['key'])
    return {'success':True,'data':None,'message':'File deleted'}


def cleanup_abandoned():
    from .store import all_rows
    s3=client();now=time.time()
    for row in all_rows('files'):
        if row.get('state') not in ('PENDING','FAILED','DELETING') or now<row.get('expires',now)+3600: continue
        if not valid_key(row): continue
        s3.delete_object(Bucket=settings.r2_bucket,Key=row['key'])
        db.collection('files').document(row['id']).delete()
