"""Validate the preserved mobile form contracts before privileged writes."""
from datetime import date
from math import isfinite
from fastapi import HTTPException
from .store import get_many

MODULE_FIELDS={'moduleName','teamLeadId','startDate','endDate','estimatedMinutes','memberIds','billableActivityIds','nonBillableActivityIds','buildingClassification','structureClassification','numberOfFloors','area','remarks','status'}
STATUSES={'NOT_STARTED','IN_PROGRESS','ON_HOLD','COMPLETED'}
WORK_STAGES={'YET_TO_START','WIP','BILLING'}

def validate_module(body, existing=None, *, transaction=None):
    if set(body)-MODULE_FIELDS: raise HTTPException(422,'Invalid module fields')
    merged=(existing or {})|body
    for key in ('moduleName','buildingClassification','structureClassification','remarks'):
        if key in body and (not isinstance(body[key],str) or len(body[key])>1000 or (key=='moduleName' and not body[key].strip())):
            raise HTTPException(422,'Invalid module text')
    if 'status' in body and body['status'] not in STATUSES: raise HTTPException(422,'Invalid status')
    for key in ('estimatedMinutes','numberOfFloors'):
        if key in body and (type(body[key]) is not int or not 0<=body[key]<=10000000): raise HTTPException(422,'Invalid module quantity')
    if 'area' in body and (type(body['area']) not in (int,float) or not isfinite(body['area']) or body['area']<0): raise HTTPException(422,'Invalid area')
    try:
        start=date.fromisoformat(merged['startDate']) if merged.get('startDate') else None
        end=date.fromisoformat(merged['endDate']) if merged.get('endDate') else None
        if start and end and end<start: raise ValueError()
    except (ValueError,TypeError): raise HTTPException(422,'Invalid module dates') from None
    selections = []
    for key in ('memberIds','billableActivityIds','nonBillableActivityIds'):
        if key in body:
            value=body[key]
            if not isinstance(value,list) or len(value)>100 or any(type(i) is not int for i in value): raise HTTPException(422,'Invalid selection')
            selections.extend(('employees' if key=='memberIds' else 'activities', uid) for uid in value)
    if merged.get('teamLeadId') is not None:
        if type(merged['teamLeadId']) is not int: raise HTTPException(422,'Select an active team leader')
        selections.append(('employees', merged['teamLeadId']))
    records = get_many(selections, fields=['active', 'deleted', 'role'], transaction=transaction)
    for key in ('memberIds','billableActivityIds','nonBillableActivityIds'):
        if key in body:
            for uid in body[key]:
                record=records.get(('employees' if key=='memberIds' else 'activities',str(uid)))
                if not record or not record.get('active',True) or record.get('deleted'):
                    label = 'Employee' if key == 'memberIds' else 'Activity'
                    raise HTTPException(422,f'{label} selection is unavailable. Refresh the form and select an active {label.lower()}.')
    if merged.get('teamLeadId') is not None:
        lead=records.get(('employees',str(merged['teamLeadId'])))
        if type(merged['teamLeadId']) is not int or not lead or not lead.get('active') or lead['role']!='TEAM_LEADER': raise HTTPException(422,'Select an active team leader')
    changes=dict(body)
    if not existing or 'memberIds' in body or 'teamLeadId' in body:
        members=set(merged.get('memberIds',[]))
        if merged.get('teamLeadId'): members.add(merged['teamLeadId'])
        changes['memberIds']=sorted(members)
    return changes
