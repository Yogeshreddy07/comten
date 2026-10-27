"""Response-only enrichment for the existing Flutter success and edit screens."""
from .store import get_many,all_rows

SUMMARY_FIELDS = ['id', 'employeeCode', 'name', 'active', 'projectName', 'projectCode']

def module_keys(row):
    return [('projects', row['projectId'])] + [
        ('employees', uid) for uid in set(row.get('memberIds', [])) | (
            {row['teamLeadId']} if row.get('teamLeadId') is not None else set())] + [
        ('activities', uid) for category in ('billable', 'nonBillable')
        for uid in row.get(category + 'ActivityIds', [])]


def hours_exhausted(row):
    """An in-progress module with no pending hours left (worked >= estimate)."""
    estimate=row.get('estimatedMinutes') or 0
    return row.get('status')=='IN_PROGRESS' and estimate>0 and (row.get('completedMinutes') or 0)>=estimate


def effective_status(row):
    """Displayed module status: Completed once pending hours reach zero.

    Derived rather than stored so an approved estimate increase moves the
    module back to In Progress, and timesheet eligibility (stored status)
    is unaffected.
    """
    if not row.get('active',True): return 'INACTIVE'
    return 'COMPLETED' if hours_exhausted(row) else row.get('status','NOT_STARTED')


def module_response(row, records=None):
    if records is None:
        records = get_many(module_keys(row), fields=SUMMARY_FIELDS)
    def lookup(collection, key):
        return records.get((collection, str(key)))
    parent=lookup('projects',row['projectId']) or {}
    lead=lookup('employees',row.get('teamLeadId')) or {}
    members=[]
    for uid in row.get('memberIds',[]):
        person=lookup('employees',uid)
        if person:members.append({'userId':person['id'],'employeeCode':person['employeeCode'],'name':person['name']})
    return row|{'projectName':parent.get('projectName',row.get('projectName','')),'projectCode':parent.get('projectCode',row.get('projectCode','')),'teamLeadName':lead.get('name'),'members':members,'completedHours':row.get('completedHours',0),'completedMinutes':row.get('completedMinutes',0),'status':effective_status(row),'storedStatus':row.get('status'),**{category+'Activities':[a for uid in row.get(category+'ActivityIds',[]) if (a:=lookup('activities',uid))] for category in ('billable','nonBillable')}}

def project_response(row, source=None):
    if source is None:
        source=[m for m in all_rows('modules',[('projectId',row['id'])]) if not m.get('deleted')]
    records=get_many([key for m in source for key in module_keys(m) if key[0]!='projects'], fields=SUMMARY_FIELDS)
    records[('projects', str(row['id']))]=row
    modules=[module_response(m, records) for m in source]
    active=[m for m in modules if m.get('active',True)]
    states={m['status'] for m in active}
    estimate=sum(m.get('estimatedMinutes') or 0 for m in active)
    worked=sum(m.get('completedMinutes') or 0 for m in active)
    starts=[m['startDate'] for m in active if m.get('startDate')]
    ends=[m['endDate'] for m in active if m.get('endDate')]
    return row|{'modules':modules,'moduleCount':len(active),'status':'INACTIVE' if not row.get('active',True) else next(iter(states)) if len(states)==1 else 'IN_PROGRESS' if states else 'NOT_STARTED','estimatedMinutes':estimate,'workedMinutes':worked,'pendingMinutes':max(0,estimate-worked),'startDate':min(starts) if starts else None,'endDate':max(ends) if ends else None}
