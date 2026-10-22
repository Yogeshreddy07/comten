"""Synthetic emulator fixtures only; never seed a real Firebase project."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
from app.store import db, get
from app.config import settings
from firebase_admin import auth
from app.roster import refresh_project_roster

if settings.environment!='local' or settings.project_id!='demo-crompton-pms':
    raise SystemExit('Seeding is restricted to the owned demo emulator')

PASSWORD='SyntheticPass123!'
for uid,code,name,role in [(1,'CAP001','Demo Captain','CAPTAIN'),(2,'PC001','Demo Controller','PROJECT_CONTROLLER'),(3,'TL001','Demo Team Leader','TEAM_LEADER'),(4,'EMP001','Demo Employee','EMPLOYEE')]:
    try: auth.get_user(str(uid))
    except auth.UserNotFoundError: auth.create_user(uid=str(uid),email=code.lower()+'@accounts.crompton.invalid',password=PASSWORD,display_name=name)
    auth.set_custom_user_claims(str(uid),{'role':role})
    db.collection('employees').document(str(uid)).set({'id':uid,'employeeCode':code,'name':name,'role':role,'email':code.lower()+'@example.invalid','phone':'','active':True,'deleted':False,'permissionVersion':1,'phoneVerified':True,'teamLeadIds':[3] if uid==4 else []})
project={'id':100,'projectCode':'SYN-001','projectName':'Synthetic Office Project','clientId':'DEMO-CLIENT','active':True,'deleted':False,'memberIds':[3,4]}
module={'id':101,'projectId':100,'projectCode':'SYN-001','projectName':project['projectName'],'moduleName':'Structural Design','teamLeadId':3,'memberIds':[3,4],'estimatedMinutes':6000,'startDate':'2026-10-01','endDate':'2026-12-31','status':'IN_PROGRESS','workStage':'DESIGN','active':True,'deleted':False,'billingStatus':'INVOICE_YET_TO_BE_RAISED','buildingClassification':'COMMERCIAL','structureClassification':'RCC','numberOfFloors':3,'area':5000,'billableActivityIds':[1],'nonBillableActivityIds':[2]}
for collection,key,row in [('projects','100',project),('modules','101',module),('activities','1',{'id':1,'name':'Design','active':True}),('activities','2',{'id':2,'name':'Meeting','active':True})]:
    if not get(collection,key): db.collection(collection).document(key).set(row)
refresh_project_roster(100)
print('Seeded four synthetic roles and one project. Password: '+PASSWORD)
