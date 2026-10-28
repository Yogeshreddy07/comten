import calendar
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, Query
from .security import current_user, manager
from .store import all_rows, get, get_many
from .mobile_contracts import effective_status

router = APIRouter(prefix='/api/reports')
IST = timezone(timedelta(hours=5,minutes=30))


def now(): return datetime.now(IST)
def round2(x): return round(float(x)+1e-10,2)
def dt(value):
    if not value: return None
    parsed = value if isinstance(value,datetime) else datetime.fromisoformat(value.replace('Z','+00:00'))
    return parsed.replace(tzinfo=IST) if parsed.tzinfo is None else parsed.astimezone(IST)
def hours(row):
    start,end=dt(row.get('inTime')),dt(row.get('outTime'))
    if not start: return 0
    if not end:
        if start.date()!=now().date(): return 9.5
        end=now()
    return round2(max(0,int((end-start).total_seconds()//60)/60))
def employee(uid):
    row=get('employees',uid)
    if not row: raise HTTPException(404,'Employee not found')
    return {k:row[k] for k in ('id','employeeCode','name','role')}
def approved(filters=()): return [x for x in all_rows('work-logs',filters) if x.get('approvalStatus')=='APPROVED']
def split(logs): return (sum(x.get('billableDurationSeconds',0) or 0 for x in logs)/3600,sum(x.get('nonBillableDurationSeconds',0) or 0 for x in logs)/3600)
def envelope(data): return {'success':True,'message':'Report retrieved','data':data}
def attendance_rows(uid,start,end):
    return sorted([r for r in all_rows('attendance',[('employeeId',int(uid))]) if start<=date.fromisoformat(r['attendanceDate'])<=end],key=lambda x:x['attendanceDate'])


@router.get('/attendance/employees')
@router.get('/working-hours/employees')
def employees(user=Depends(current_user)):
    manager(user)
    return envelope(sorted([{k:e[k] for k in ('id','employeeCode','name','role')} for e in all_rows('employees',[('role','EMPLOYEE')]) if not e.get('deleted')],key=lambda x:x['name']))


@router.get('/attendance/employees/{uid}')
def attendance(uid: int,year: int|None=None,month: int|None=None,user=Depends(current_user)):
    manager(user)
    today=now().date(); year=year or today.year;month=month or today.month
    try: start=date(year,month,1); end=min(date(year,month,calendar.monthrange(year,month)[1]),today)
    except ValueError: raise HTTPException(422,'Invalid month') from None
    records=attendance_rows(uid,start,end) if end>=start else []
    days=[]
    for r in records:
        it,ot=dt(r.get('inTime')),dt(r.get('outTime'))
        days.append({'date':r['attendanceDate'],'inTime':it.isoformat() if it else None,'outTime':ot.isoformat() if ot else None,'late':bool(it and (it.hour,it.minute,it.second)>(10,0,0)),'earlyExit':bool(ot and (ot.hour,ot.minute,ot.second)<(17,0,0)),'hoursWorked':round2(hours(r))})
    count=max(0,(end-start).days+1);present=len(records); total=sum(hours(r) for r in records)
    trend=[]
    for i in range(5,-1,-1):
        n=year*12+month-1-i; y,m=divmod(n,12);m+=1
        a=date(y,m,1);b=min(date(y,m,calendar.monthrange(y,m)[1]),today)
        n_days=max(0,(b-a).days+1); p=len(attendance_rows(uid,a,b)) if b>=a else 0
        trend.append({'month':f'{y:04}-{m:02}','presentDays':p,'daysInPeriod':n_days,'percentage':round2(100*p/n_days) if n_days else 0})
    return envelope({'employee':employee(uid),'year':year,'month':month,'daysInPeriod':count,'presentDays':present,'leaveDays':max(0,count-present),'lateComings':sum(d['late'] for d in days),'earlyExits':sum(d['earlyExit'] for d in days),'attendancePercentage':round2(present*100/count) if count else 0,'totalHours':round2(total),'averageHoursPerPresentDay':round2(total/present) if present else 0,'days':days,'monthlyTrend':trend})


@router.get('/working-hours/employees/{uid}')
def working(uid: int,from_date: date|None=Query(None,alias='from'),to_date: date|None=Query(None,alias='to'),user=Depends(current_user)):
    return working_report(uid,from_date,to_date,user)


def working_report(uid,from_date,to_date,user):
    manager(user)
    end=to_date or now().date();start=from_date or end.replace(day=1)
    if end<start or (end-start).days>3660: raise HTTPException(422,'Invalid report range')
    records=attendance_rows(uid,start,end);daily=[];weekly=defaultdict(float);monthly=defaultdict(float)
    for r in records:
        h=hours(r);day=date.fromisoformat(r['attendanceDate'])
        daily.append({'date':str(day),'totalHours':round2(h),'regularHours':round2(min(h,9.5)),'overtimeHours':round2(max(0,h-9.5))})
        weekly[str(day-timedelta(days=day.weekday()))]+=h;monthly[str(day)[:7]]+=h
    logs=[l for l in approved([('employeeId',uid)]) if str(start)<=l['workDate']<=str(end)]
    bill,non=split(logs);total=sum(hours(r) for r in records)
    return envelope({'employee':employee(uid),'from':str(start),'to':str(end),'totalHours':round2(total),'regularHours':round2(sum(min(hours(r),9.5) for r in records)),'overtimeHours':round2(sum(max(0,hours(r)-9.5) for r in records)),'averageHoursPerDay':round2(total/len(records)) if records else 0,'billableHours':round2(bill),'nonBillableHours':round2(non),'utilizationPercentage':round2(min(100,100*bill/total)) if total else 0,'daily':daily,'weekly':[{'weekStart':k,'hours':round2(v)} for k,v in sorted(weekly.items())],'monthly':[{'month':k,'hours':round2(v)} for k,v in sorted(monthly.items())],'approvedLoggedHours':round2(bill+non)})


def employee_hours(logs,with_split=False,billable_only=False):
    groups=defaultdict(list)
    for l in logs: groups[l['employeeId']].append(l)
    result=[]
    records=get_many([('employees', uid) for uid in groups], fields=['id','employeeCode','name','role'])
    for uid,group in groups.items():
        e=records.get(('employees',str(uid)))
        if not e: raise HTTPException(404,'Employee not found')
        b,n=split(group)
        if billable_only and b<=0: continue
        result.append({'userId':uid,'employeeCode':e['employeeCode'],'name':e['name'],**({'billableHours':round2(b),'nonBillableHours':round2(n)} if with_split else {'hours':round2(b if billable_only else b+n)})})
    return sorted(result,key=lambda e:-(e.get('hours',0) if not with_split else e['billableHours']+e['nonBillableHours']))


def utilization(module,logs):
    planned=(module.get('estimatedMinutes') or 0)/60;b,n=split(logs)
    lead=get('employees',module.get('teamLeadId')) or {}
    return {'id':module['id'],'moduleName':module['moduleName'],'teamLeadName':lead.get('name',''),'teamLeadId':module.get('teamLeadId'),'status':effective_status(module) if module.get('active',True) else module.get('status','NOT_STARTED'),'startDate':module.get('startDate'),'endDate':module.get('endDate'),'plannedHours':round2(planned),'actualHours':round2(b),'remainingHours':round2(max(0,planned-b)),'progressPercentage':100 if effective_status(module)=='COMPLETED' else round2(min(100,b*100/planned)) if planned else 0,'billableHours':round2(b),'nonBillableHours':round2(n),'employeeHours':employee_hours(logs,True),**{k:module.get(k) for k in ('buildingClassification','structureClassification','numberOfFloors','area')}}


def project_data(pid):
    p=get('projects',pid)
    if not p or p.get('deleted'): raise HTTPException(404,'Project not found')
    modules=[m for m in all_rows('modules',[('projectId',int(pid))]) if not m.get('deleted')]
    mids={m['id'] for m in modules};logs=[l for l in approved([('projectId',int(pid))]) if l['moduleId'] in mids]
    us=[utilization(m,[l for l in logs if l['moduleId']==m['id']]) for m in modules]
    planned=sum(m['plannedHours'] for m in us);actual=sum(m['actualHours'] for m in us)
    starts=[m['startDate'] for m in us if m['startDate']];ends=[m['endDate'] for m in us if m['endDate']]
    summary={**p,'active':p.get('active',True),'moduleCount':len(modules),'plannedHours':round2(planned),'actualHours':round2(actual),'remainingHours':round2(max(0,planned-actual)),'progressPercentage':round2(min(100,actual*100/planned)) if planned else 0,'teamLeadNames':', '.join(sorted({m['teamLeadName'] for m in us if m['teamLeadName']})),'teamLeadIds':','.join(str(m['teamLeadId']) for m in us if m['teamLeadId']),'startDate':min(starts) if starts else None,'endDate':max(ends) if ends else None,'billableHours':round2(split(logs)[0]),'nonBillableHours':round2(split(logs)[1])}
    return summary,us,logs


@router.get('/projects')
def projects(user=Depends(current_user)):
    manager(user)
    return envelope([project_data(p['id'])[0] for p in all_rows('projects') if not p.get('deleted')])


@router.get('/projects/{pid}')
def project(pid: int,user=Depends(current_user)):
    manager(user);p,modules,logs=project_data(pid)
    return envelope({'project':p,'modules':modules,'employeeHours':employee_hours(logs)})


@router.get('/projects/{pid}/modules/{mid}')
def module_detail(pid: int,mid: int,user=Depends(current_user)):
    manager(user);p,modules,logs=project_data(pid)
    m=next((m for m in modules if m['id']==mid),None)
    if not m: raise HTTPException(404,'Module not found')
    logs=[l for l in logs if l['moduleId']==mid];monthly=defaultdict(float)
    for l in logs: monthly[l['workDate'][:7]]+=(l.get('billableDurationSeconds',0)+l.get('nonBillableDurationSeconds',0))/3600
    return envelope({'projectId':pid,'projectName':p['projectName'],'module':m,'employeeHours':employee_hours(logs),'monthlyHours':[{'month':k,'hours':round2(v)} for k,v in sorted(monthly.items())]})


def canonical_billing(m):
    status=m.get('billingStatus')
    if status: return {'INVOICE_RAISED':'BILLED','PART_PAYMENT_RECEIVED':'PARTLY_PAID','FULL_PAYMENT_RECEIVED':'PAID'}.get(status,'READY')
    if m.get('workStage')=='BILLING': return 'READY'
    return 'NOT_STARTED' if m.get('status')=='NOT_STARTED' else 'WIP'


def module_billing(m,logs):
    b,_=split(logs);status=canonical_billing(m);billed=b if status in ('BILLED','PARTLY_PAID','PAID') else 0
    allocated=(m.get('estimatedMinutes') or 0)/60
    return {'id':m['id'],'moduleName':m['moduleName'],'billingStatus':status,'spocName':m.get('spocName',''),'allocatedHours':round2(allocated),'billableHours':round2(b),'billedHours':round2(billed),'unbilledHours':round2(max(0,allocated-billed))}


@router.get('/billing/projects/{pid}')
def project_billing(pid: int,user=Depends(current_user)):
    manager(user);p,_,logs=project_data(pid)
    modules=[module_billing(m,[l for l in logs if l['moduleId']==m['id']]) for m in all_rows('modules',[('projectId',pid)]) if not m.get('deleted')]
    return envelope({'projectId':pid,'projectCode':p['projectCode'],'projectName':p['projectName'],'totalBillableHours':round2(sum(m['billableHours'] for m in modules)),'totalBilledHours':round2(sum(m['billedHours'] for m in modules)),'totalUnbilledHours':round2(sum(m['unbilledHours'] for m in modules)),'modules':modules,'billableHoursByEmployee':employee_hours(logs,billable_only=True)})


@router.get('/billing/modules/{mid}')
def billing_module(mid: int,user=Depends(current_user)):
    manager(user);m=get('modules',mid)
    if not m: raise HTTPException(404,'Module not found')
    logs=approved([('moduleId',mid)])
    return envelope({'projectId':m['projectId'],'projectName':m['projectName'],'module':module_billing(m,logs),'remarks':m.get('remarks',''),'updatedBy':m.get('updatedBy',''),'updatedAt':m.get('updatedAt'),'billableHoursByEmployee':employee_hours(logs,billable_only=True)})


@router.get('/clients')
def clients(user=Depends(current_user)):
    manager(user);groups=defaultdict(list)
    for p in all_rows('projects'):
        if not p.get('deleted'): groups[p.get('clientId') or 'UNASSIGNED'].append(project_data(p['id'])[0])
    return envelope([{'clientId':k,'projectCount':len(v),'moduleCount':sum(p['moduleCount'] for p in v),'allocatedHours':round2(sum(p['plannedHours'] for p in v)),'utilizedHours':round2(sum(p['actualHours'] for p in v))} for k,v in sorted(groups.items())])


@router.get('/clients/{cid}')
def client_detail(cid: str,user=Depends(current_user)):
    manager(user);result=[]
    for row in all_rows('projects'):
        if not row.get('deleted') and (row.get('clientId') or 'UNASSIGNED')==cid:
            p,modules,_=project_data(row['id']);result.append({**p,'allocatedHours':p['plannedHours'],'utilizedHours':p['actualHours'],'modules':modules})
    return envelope({'clientId':cid,'projects':result})


@router.get('/billing-status')
def billing_status(includeDeleted: bool=False,user=Depends(current_user)):
    manager(user);modules=[];billed=[];counts={'NOT_BILLED':0,'BILLED':0,'PARTLY_PAID':0}
    project_deleted={p['id']:p.get('deleted',False) for p in all_rows('projects')}
    for m in all_rows('modules'):
        if not includeDeleted and (m.get('deleted') or project_deleted.get(m['projectId'],True)): continue
        status=canonical_billing(m)
        category='PARTLY_PAID' if status=='PARTLY_PAID' else 'BILLED' if status in ('BILLED','PAID') else 'NOT_BILLED'
        counts[category]+=1
        modules.append({'moduleId':m['id'],'moduleName':m['moduleName'],'projectId':m['projectId'],'projectName':m['projectName'],'billingStatus':status,'category':category,'spocName':m.get('spocName','')})
        if category!='NOT_BILLED': billed.append({'moduleId':m['id'],'moduleName':m['moduleName'],'projectName':m['projectName'],'spocName':m.get('spocName',''),'status':status,'updatedAt':m.get('updatedAt')})
    return envelope({'summary':[{'category':k,'count':v} for k,v in counts.items()],'modules':modules,'billedModules':billed})
