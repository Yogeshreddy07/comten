"""Bounded real-development smoke checks. No messages, uploads or historical data."""
import json
from pathlib import Path
import httpx

root=Path(__file__).resolve().parents[1]
logins=json.loads((root/'.local/development-logins.json').read_text())
api='http://127.0.0.1:8007'
checks=[]
def check(value,name):
    if not value:raise RuntimeError(name)
    checks.append(name)
with httpx.Client(timeout=30) as client:
    r=client.post(api+'/api/auth/login',json=logins['CAP001']);check(r.status_code==200,'Cloud Firebase Captain login')
    captain=r.json()['data']['token']
    r=client.get(api+'/api/reports/projects',headers={'Authorization':'Bearer '+captain});check(r.status_code==200 and any(p['id']==100 for p in r.json()['data']),'FastAPI reads cloud Firestore report')
    r=client.post(api+'/api/auth/login',json=logins['EMP001']);check(r.status_code==200,'Cloud Firebase employee login')
    employee=r.json()['data']['token']
    r=client.get(api+'/api/reports/projects',headers={'Authorization':'Bearer '+employee});check(r.status_code==403,'Cloud role rejection')
    firestore='https://firestore.googleapis.com/v1/projects/crompton-pms-dev-20261015/databases/(default)/documents'
    r=client.get(firestore+'/projects/100',headers={'Authorization':'Bearer '+employee});check(r.status_code==200,'Direct cloud Firestore assigned project read')
    r=client.get(firestore+'/projects/100');check(r.status_code in (401,403),'Cloud anonymous access rejected')
    r=client.patch(firestore+'/employees/4',params={'updateMask.fieldPaths':'role'},json={'fields':{'role':{'stringValue':'CAPTAIN'}}},headers={'Authorization':'Bearer '+employee});check(r.status_code==403,'Cloud client privilege escalation rejected')
(root/'tests/development-smoke.json').write_text(json.dumps({'project':'crompton-pms-dev-20261015','checks':checks},indent=2))
print(json.dumps(checks,indent=2))
