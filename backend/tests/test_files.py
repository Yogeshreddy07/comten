"""Synthetic R2 adapter plus real Firestore-emulator authorization/transactions."""
import io
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
import pytest
from test_workflows import tokens,client
from app import storage
from app.store import db,get


@pytest.fixture
def objects(monkeypatch):
    class S3:
        def __init__(self): self.objects={};self.signed=[];self.deleted=[]
        def generate_presigned_url(self,operation,**kw):
            self.signed.append((operation,kw))
            if operation=='put_object': self.objects[kw['Params']['Key']]={'body':b'%PDF-1.7 synthetic','type':'application/pdf','size':18,'etag':'"synthetic"'}
            return 'https://synthetic.r2.invalid/signed'
        def head_object(self,**kw):
            row=self.objects[kw['Key']];return {'ContentLength':row['size'],'ContentType':row['type'],'ETag':row['etag']}
        def get_object(self,**kw):
            row=self.objects[kw['Key']];assert kw['IfMatch']==row['etag'];return {'Body':io.BytesIO(row['body'])}
        def delete_object(self,**kw): self.deleted.append(kw['Key']);self.objects.pop(kw['Key'],None)
    s3=S3();monkeypatch.setattr(storage,'client',lambda:s3)
    # This quota belongs exclusively to the shared synthetic employee fixture.
    quota=db.collection('file-rate-limits').document('4');prior=quota.get().to_dict();quota.delete()
    before={s.id for s in db.collection('files').stream()}
    yield s3
    for snap in db.collection('files').stream():
        if snap.id not in before: snap.reference.delete()
    if prior: quota.set(prior)
    else: quota.delete()


def grant(tokens,**values):
    return client.post('/api/files/authorize-upload',json={'name':'synthetic.pdf','contentType':'application/pdf','size':18,**values},headers=tokens['employee'])


def test_object_capabilities_opaque_conditional_and_scoped(tokens,objects):
    response=grant(tokens);assert response.status_code==200,response.text
    data=response.json()['data'];row=get('files',data['id'])
    assert storage.valid_key(row) and 'synthetic.pdf' not in row['key']
    assert data['expiresIn']==300 and data['headers']['If-None-Match']=='*'
    assert objects.signed[0][1]['Params']['ContentLength']==18
    assert client.get('/api/files/'+data['id']+'/download',headers=tokens['lead']).status_code==404
    assert client.post('/api/files/'+data['id']+'/complete',headers=tokens['captain']).status_code==404
    assert client.post('/api/files/'+data['id']+'/complete',headers=tokens['employee']).status_code==200
    assert client.post('/api/files/'+data['id']+'/complete',headers=tokens['employee']).status_code==200
    files=client.get('/api/files',headers=tokens['employee']).json()['data']
    assert data['id'] in [row['id'] for row in files]
    assert client.get('/api/files/'+data['id']+'/download',headers=tokens['employee']).status_code==200
    assert objects.signed[-1][1]['Params']['IfMatch']=='"synthetic"'
    assert objects.signed[-1][1]['ExpiresIn']==120
    assert client.delete('/api/files/'+data['id'],headers=tokens['employee']).status_code==200
    assert client.post('/api/files/'+data['id']+'/complete',headers=tokens['employee']).status_code==409
    assert data['id'] not in [row['id'] for row in client.get('/api/files',headers=tokens['employee']).json()['data']]


@pytest.mark.parametrize('changes',[{'size':10*1024*1024+1},{'contentType':'text/html'},{'category':'public'},{'name':'../secret'},{'key':'arbitrary/path'},{'category':'profile_image'}])
def test_upload_rejects_untrusted_metadata(tokens,objects,changes):
    assert grant(tokens,**changes).status_code==422
    assert not objects.signed


@pytest.mark.parametrize('mutation',[{'type':'image/png'},{'size':999},{'body':b'HTML instead of PDF'}])
def test_invalid_object_is_rejected_and_deleted(tokens,objects,mutation):
    response=grant(tokens);key=response.json()['data']['id'];row=get('files',key)
    objects.objects[row['key']].update(mutation)
    assert client.post('/api/files/'+key+'/complete',headers=tokens['employee']).status_code==422
    assert row['key'] in objects.deleted
    assert get('files',key)['state']=='FAILED'


def test_expiry_cleanup_and_arbitrary_key_guard(tokens,objects):
    key=grant(tokens).json()['data']['id'];ref=db.collection('files').document(key);row=get('files',key)
    ref.update({'expires':time.time()-1})
    assert client.post('/api/files/'+key+'/complete',headers=tokens['employee']).status_code==409
    ref.update({'expires':time.time()-3601})
    storage.cleanup_abandoned()
    assert get('files',key) is None and row['key'] in objects.deleted
    assert client.get('/api/files/not-a-valid-id/download',headers=tokens['captain']).status_code==404
    assert client.get('/api/files/'+key+'/download').status_code==401


def test_project_membership_billing_and_revocation(tokens,objects):
    pid=time.time_ns()//1000;ref=db.collection('projects').document(str(pid))
    ref.create({'id':pid,'active':True,'deleted':False,'memberIds':[4]})
    try:
        assert grant(tokens,category='project_attachment',targetId=pid).status_code==200
        assert grant(tokens,category='billing_document',targetId=pid).status_code==404
        ref.update({'memberIds':[]})
        assert grant(tokens,category='project_attachment',targetId=pid).status_code==404
        assert client.get(f'/api/files?category=project_attachment&targetId={pid}',headers=tokens['employee']).status_code==404
        assert client.get(f'/api/files?category=billing_document&targetId={pid}',headers=tokens['captain']).status_code==200
    finally: ref.delete()


def test_concurrent_uploads_unique_and_quota_commits(tokens,objects):
    with ThreadPoolExecutor(max_workers=3) as pool:
        responses=list(pool.map(lambda _:grant(tokens),range(3)))
    assert [r.status_code for r in responses]==[200]*3
    ids=[r.json()['data']['id'] for r in responses]
    assert len(set(ids))==3 and len({get('files',key)['key'] for key in ids})==3
    ref=db.collection('file-rate-limits').document('4')
    assert ref.get().to_dict()['count']==3
    ref.update({'count':30})
    assert grant(tokens).status_code==429


def test_real_sdk_signature_contains_create_once_and_size(monkeypatch):
    # Actual boto3 signing, no network operations or credentials.
    for key,value in {'r2_endpoint':'https://'+'a'*32+'.r2.cloudflarestorage.com','r2_bucket':'crompton-pms-dev','r2_access_key':'synthetic','r2_secret_key':'synthetic'}.items(): monkeypatch.setattr(storage.settings,key,value)
    url=storage.client().generate_presigned_url('put_object',Params={'Bucket':'crompton-pms-dev','Key':'v1/project_attachment/'+'b'*64,'ContentLength':18,'ContentType':'application/pdf','IfNoneMatch':'*'},ExpiresIn=300)
    query=urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
    signed=query['X-Amz-SignedHeaders'][0]
    assert 'if-none-match' in signed and 'content-length' in signed and 'content-type' in signed
    assert query['X-Amz-Expires']==['300']


def test_timesheet_owner_and_assigned_leader_read_scope(tokens,objects):
    wid=time.time_ns()//1000;ref=db.collection('work-logs').document(str(wid))
    ref.create({'id':wid,'employeeId':4,'moduleId':101})
    try:
        response=grant(tokens,category='timesheet_attachment',targetId=wid);assert response.status_code==200
        key=response.json()['data']['id']
        assert client.post('/api/files/'+key+'/complete',headers=tokens['employee']).status_code==200
        assert client.get('/api/files/'+key+'/download',headers=tokens['lead']).status_code==200
        assert client.delete('/api/files/'+key,headers=tokens['lead']).status_code==404
        assert grant(tokens,category='timesheet_attachment',targetId=wid+1).status_code==404
    finally: ref.delete()


def test_profile_image_metadata_and_signature(tokens,objects):
    response=grant(tokens,category='profile_image',name='synthetic.png',contentType='image/png');assert response.status_code==200
    key=response.json()['data']['id'];row=get('files',key)
    objects.objects[row['key']].update({'type':'image/png','body':b'\x89PNG\r\n\x1a\nsynthetic'})
    assert client.post('/api/files/'+key+'/complete',headers=tokens['employee']).status_code==200
    assert client.get('/api/files/'+key+'/download',headers=tokens['captain']).status_code==404


@pytest.mark.parametrize('valid',[True,False])
def test_workbook_is_valid_container_not_just_zip_magic(tokens,objects,valid):
    import zipfile
    content=io.BytesIO()
    with zipfile.ZipFile(content,'w') as archive:
        if valid:
            archive.writestr('[Content_Types].xml','<Types/>');archive.writestr('xl/workbook.xml','<workbook/>')
        else: archive.writestr('unrelated.txt','synthetic')
    payload=content.getvalue()
    response=grant(tokens,name='synthetic.xlsx',size=len(payload),contentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    key=response.json()['data']['id'];row=get('files',key)
    objects.objects[row['key']].update({'type':row['contentType'],'size':len(payload),'body':payload})
    assert client.post('/api/files/'+key+'/complete',headers=tokens['employee']).status_code==(200 if valid else 422)
