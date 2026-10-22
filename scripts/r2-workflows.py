"""Finite real R2 checks in the dedicated development project; no messages.

Only synthetic objects and fixture documents created by this run are removed.
Exceptions, URLs, credentials and provider response bodies are never printed.
"""
import json
import base64
import os
from pathlib import Path
import sys
import time
import httpx

ROOT = Path(__file__).resolve().parents[1]
if os.getenv('ENVIRONMENT') != 'development' or os.getenv('PROJECT_ID') != 'crompton-pms-dev-20261015':
    raise SystemExit('Dedicated development environment required')
os.environ.setdefault('GOOGLE_APPLICATION_CREDENTIALS', str(ROOT/'.local/development-service-account.json'))
sys.path.insert(0, str(ROOT/'backend'))
from app.config import settings
from app.store import db, get
from app.storage import client, cleanup_abandoned

if settings.r2_bucket != 'crompton-pms-dev':
    raise SystemExit('Dedicated bucket required')
s3 = client()
checks = []
files = []
fixtures = []
run = int(time.time()*1000)
project, unrelated, module, log = run, run+1, run+2, run+3
pdf = b'%PDF-1.7 synthetic development fixture'
png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jY1kAAAAASUVORK5CYII=')
logins = json.loads((ROOT/'.local/development-logins.json').read_text())


def fixture(collection, key, data):
    ref = db.collection(collection).document(str(key))
    ref.create({'id': key, **data})
    fixtures.append(ref)


def absent(key):
    try:
        s3.head_object(Bucket=settings.r2_bucket, Key=key)
    except s3.exceptions.ClientError as error:
        if error.response['ResponseMetadata']['HTTPStatusCode'] == 404:
            return
        raise
    raise AssertionError('Synthetic object still exists')


def main():
    with httpx.Client(base_url='http://127.0.0.1:8007', timeout=30) as api:
        headers = {}
        for role in ('CAP001', 'TL001', 'EMP001'):
            item = logins[role]
            response = api.post('/api/auth/login', json={'employeeCode': role, 'password': item['password']})
            response.raise_for_status()
            headers[role] = {'Authorization': 'Bearer '+response.json()['data']['token']}
        fixture('projects', project, {'name':'Synthetic R2 workflow','active':True,'deleted':False,'memberIds':[3,4]})
        fixture('projects', unrelated, {'name':'Synthetic unrelated R2 scope','active':True,'deleted':False,'memberIds':[]})
        fixture('modules', module, {'projectId':project,'active':True,'teamLeadId':3})
        fixture('work-logs', log, {'moduleId':module,'employeeId':4})

        def upload(category, target, role='EMP001', complete=True):
            payload = png if category == 'profile_image' else pdf
            content_type = 'image/png' if category == 'profile_image' else 'application/pdf'
            body = {'name':'synthetic-live'+('.png' if category=='profile_image' else '.pdf'),
                    'size':len(payload),'contentType':content_type,'category':category,'targetId':target}
            response = api.post('/api/files/authorize-upload', json=body, headers=headers[role])
            response.raise_for_status()
            grant = response.json()['data']
            files.append((grant['id'],role))
            httpx.put(grant['url'], headers=grant['headers'], content=payload, timeout=30).raise_for_status()
            if complete:
                api.post('/api/files/'+grant['id']+'/complete', json={}, headers=headers[role]).raise_for_status()
                response = api.get('/api/files/'+grant['id']+'/download', headers=headers[role])
                response.raise_for_status()
                download = response.json()['data']
                result = httpx.get(download['url'], headers=download['headers'], timeout=30)
                assert result.status_code == 200 and result.content == payload
                response = api.get('/api/files', params={'category':category,'targetId':target}, headers=headers[role])
                response.raise_for_status()
                assert any(row['id']==grant['id'] for row in response.json()['data'])
                checks.append(category+' real PUT, confirm, listing and GET')
            return grant['id']

        employee_file = upload('employee_document',4)
        upload('profile_image',4)
        upload('project_attachment',project)
        timesheet = upload('timesheet_attachment',log)
        billing = upload('billing_document',project,'CAP001')
        foreign = upload('project_attachment',unrelated,'CAP001')
        assert api.get('/api/files/'+employee_file+'/download', headers=headers['TL001']).status_code == 404
        checks.append('Cross-user employee document access denied')
        assert api.get('/api/files/'+foreign+'/download', headers=headers['EMP001']).status_code == 404
        checks.append('Cross-project attachment access denied')
        assert api.get('/api/files/'+billing+'/download', headers=headers['EMP001']).status_code == 404
        checks.append('Employee billing document access denied')
        assert api.get('/api/files/'+timesheet+'/download', headers=headers['TL001']).status_code == 200
        assert api.delete('/api/files/'+timesheet, headers=headers['TL001']).status_code == 404
        checks.append('Assigned leader timesheet download allowed; deletion denied')
        db.collection('projects').document(str(project)).update({'memberIds':[3]})
        response = api.get('/api/files', params={'category':'project_attachment','targetId':project}, headers=headers['EMP001'])
        assert response.status_code == 404
        checks.append('Membership revocation immediately removes file access')
        db.collection('projects').document(str(project)).update({'memberIds':[3,4]})
        abandoned = upload('employee_document',4,complete=False)
        row = get('files',abandoned)
        # Advance only this disposable fixture's retention deadline, not the host clock.
        db.collection('files').document(abandoned).update({'expires':time.time()-3601})
        cleanup_abandoned()
        assert get('files',abandoned) is None
        absent(row['key'])
        checks.append('Abandoned real object and metadata removed after retention grace')
        for file_id,role in files:
            row = get('files',file_id)
            if row:
                api.delete('/api/files/'+file_id, headers=headers[role]).raise_for_status()
                absent(row['key'])
        checks.append('All run-owned synthetic objects deleted and HEAD absence verified')


passed = False
try:
    main()
    passed = True
finally:
    # Also runs after failed assertions; no unrelated files are removed.
    cleanup_ok = True
    for file_id,_ in files:
        row = get('files',file_id)
        if row:
            try:
                s3.delete_object(Bucket=settings.r2_bucket,Key=row['key'])
                absent(row['key'])
                db.collection('files').document(file_id).update({'state':'DELETING','scopeStateKey':row['scopeKey']+':DELETING'})
            except Exception:
                cleanup_ok = False
    for ref in reversed(fixtures):
        ref.delete()
    result={'provider':'LIVE_R2','checks':checks,'passed':passed,'syntheticObjectsRemoved':cleanup_ok}
    (ROOT/'tests/r2-live-workflows.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result))
    if not passed or not cleanup_ok:
        # Do not render an exception traceback that could contain signed URLs.
        sys.exit(1)
