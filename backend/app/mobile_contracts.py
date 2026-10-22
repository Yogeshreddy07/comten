"""Response-only enrichment for the existing Flutter success and edit screens."""
from .store import get,all_rows

def module_response(row):
    parent=get('projects',row['projectId']) or {}
    lead=get('employees',row.get('teamLeadId')) or {}
    members=[]
    for uid in row.get('memberIds',[]):
        person=get('employees',uid)
        if person:members.append({'userId':person['id'],'employeeCode':person['employeeCode'],'name':person['name']})
    return row|{'projectName':parent.get('projectName',row.get('projectName','')),'projectCode':parent.get('projectCode',row.get('projectCode','')),'teamLeadName':lead.get('name'),'members':members,'completedHours':row.get('completedHours',0),'completedMinutes':row.get('completedMinutes',0),'status':row.get('status','NOT_STARTED') if row.get('active',True) else 'INACTIVE',**{category+'Activities':[a for uid in row.get(category+'ActivityIds',[]) if (a:=get('activities',uid))] for category in ('billable','nonBillable')}}

def project_response(row):
    modules=[module_response(m) for m in all_rows('modules',[('projectId',row['id'])]) if not m.get('deleted')]
    active=[m for m in modules if m.get('active',True)]
    states={m['status'] for m in active}
    estimate=sum(m.get('estimatedMinutes') or 0 for m in active)
    worked=sum(m.get('completedMinutes') or 0 for m in active)
    starts=[m['startDate'] for m in active if m.get('startDate')]
    ends=[m['endDate'] for m in active if m.get('endDate')]
    return row|{'modules':modules,'moduleCount':len(active),'status':'INACTIVE' if not row.get('active',True) else next(iter(states)) if len(states)==1 else 'IN_PROGRESS' if states else 'NOT_STARTED','estimatedMinutes':estimate,'workedMinutes':worked,'pendingMinutes':max(0,estimate-worked),'startDate':min(starts) if starts else None,'endDate':max(ends) if ends else None}
