"""Initialize only the explicitly created, fresh Crompton development Firebase project."""
import json,os,secrets,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
project='crompton-pms-dev-20261015'
key=ROOT/'.local/development-service-account.json'
if not key.exists() or json.loads(key.read_text())['project_id']!=project:
    raise SystemExit('The dedicated development identity is required')
os.environ['ENVIRONMENT']='development';os.environ['PROJECT_ID']=project
os.environ['GOOGLE_APPLICATION_CREDENTIALS']=str(key)
for name in ('FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST'):os.environ.pop(name,None)
sys.path.insert(0,str(ROOT/'backend'))
from app.store import db,get
from firebase_admin import auth

login_file=ROOT/'.local/development-logins.json'
saved=json.loads(login_file.read_text()) if login_file.exists() else {}
for uid,code,role in [(1,'CAP001','CAPTAIN'),(2,'PC001','PROJECT_CONTROLLER'),(3,'TL001','TEAM_LEADER'),(4,'EMP001','EMPLOYEE')]:
    name='Synthetic Development '+role.replace('_',' ').title()
    try:
        existing=auth.get_user(str(uid))
        if existing.display_name!=name:raise SystemExit('Refusing to alter an unexpected development account')
        if code not in saved:raise SystemExit('Account already exists without a local credential record; recover it explicitly')
    except auth.UserNotFoundError:
        password='Aa1!'+secrets.token_urlsafe(20)
        auth.create_user(uid=str(uid),email=code.lower()+'@accounts.crompton.invalid',password=password,display_name=name)
        saved[code]={'employeeCode':code,'password':password,'role':role}
        login_file.write_text(json.dumps(saved,indent=2))
    auth.set_custom_user_claims(str(uid),{'role':role})
    if not get('employees',uid):db.collection('employees').document(str(uid)).create({'id':uid,'employeeCode':code,'name':name,'role':role,'email':code.lower()+'@example.invalid','phone':'','active':True,'deleted':False,'phoneVerified':True,'permissionVersion':1,'teamLeadIds':[3] if uid==4 else []})
project_row={'id':100,'projectCode':'SYN-DEV-001','projectName':'Synthetic Development Office','clientId':'DEMO-CLIENT','active':True,'deleted':False,'memberIds':[3,4]}
module={'id':101,'projectId':100,'projectCode':project_row['projectCode'],'projectName':project_row['projectName'],'moduleName':'Synthetic Design','teamLeadId':3,'memberIds':[3,4],'estimatedMinutes':6000,'startDate':'2026-10-01','endDate':'2026-12-31','status':'IN_PROGRESS','workStage':'WIP','active':True,'deleted':False,'buildingClassification':'COMMERCIAL','structureClassification':'RCC','numberOfFloors':3,'area':5000,'billableActivityIds':[1],'nonBillableActivityIds':[2]}
for collection,record in [('projects',project_row),('modules',module),('activities',{'id':1,'name':'Design','active':True}),('activities',{'id':2,'name':'Meeting','active':True})]:
    if not get(collection,record['id']):db.collection(collection).document(str(record['id'])).create(record)
from app.roster import refresh_project_roster
refresh_project_roster(100)
print('Dedicated cloud development synthetic accounts and records initialized. Credentials are only in ignored .local/development-logins.json.')
