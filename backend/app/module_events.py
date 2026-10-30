"""Project progress and module completion alerts committed with the work update."""
import time
from datetime import datetime, timezone
from google.cloud.firestore_v1.base_query import FieldFilter
from .store import db
from .mobile_contracts import effective_status

MILESTONES = (25, 50, 75, 100)


def worked_seconds(module):
    return module.get('completedSeconds') if module.get('completedSeconds') is not None else (module.get('completedMinutes') or 0) * 60


def recipients_for(tx, modules):
    recipients = {s.to_dict()['id']: s.to_dict() for s in
                  db.collection('employees').where(filter=FieldFilter('role', 'in', ['CAPTAIN', 'PROJECT_CONTROLLER'])).stream(transaction=tx)}
    members = set()
    for module in modules:
        members.update(module.get('memberIds', []))
        if module.get('teamLeadId'):
            members.add(module['teamLeadId'])
    for uid in sorted(members):
        person = db.collection('employees').document(str(uid)).get(transaction=tx).to_dict()
        if person:
            recipients[uid] = person
    return [person for person in recipients.values() if person.get('active') and not person.get('deleted')]


def queue_progress_events(tx, before, after):
    # Finish every read before writing any alert, project or module. Parent
    # milestone markers serialize simultaneous approvals across its modules.
    records = []
    project_update = None
    if worked_seconds(after) > worked_seconds(before):
        project_ref = db.collection('projects').document(str(after['projectId']))
        project = project_ref.get(transaction=tx).to_dict() or {}
        if project.get('active') and not project.get('deleted'):
            modules = [s.to_dict() for s in db.collection('modules').where(
                filter=FieldFilter('projectId', '==', after['projectId'])).stream(transaction=tx)]
            modules = [m for m in modules if m.get('active', True) and not m.get('deleted')]
            estimate = sum((m.get('estimatedMinutes') or 0) * 60 for m in modules)
            previous = sum(worked_seconds(before if m['id'] == before['id'] else m) for m in modules)
            current = sum(worked_seconds(after if m['id'] == after['id'] else m) for m in modules)
            notified = set(project.get('notifiedMilestones', []))
            crossed = [pct for pct in MILESTONES if pct not in notified
                       and estimate > 0 and previous * 100 < pct * estimate <= current * 100]
            if crossed:
                recipients = recipients_for(tx, modules)
                for pct in crossed:
                    for person in recipients:
                        records.append({
                            'userId': person['id'], 'title': f'Project {pct}% completed',
                            'message': f'{project["projectName"]} has reached {pct}% of its combined estimated hours.',
                            'type': 'PROJECT_MILESTONE_REACHED', 'milestonePercent': pct,
                            'projectId': after['projectId'], 'projectName': project['projectName'],
                            'projectCode': project.get('projectCode', ''),
                            'estimatedMinutes': estimate // 60, 'workedMinutes': current // 60})
                project_update = (project_ref, sorted(notified | set(crossed)))
    if effective_status(before) != 'COMPLETED' and effective_status(after) == 'COMPLETED':
        for person in recipients_for(tx, [after]):
            records.append({
                'userId': person['id'], 'title': 'Module completed',
                'message': f'{after["moduleName"]} is completed.',
                'type': 'MODULE_MILESTONE_REACHED', 'moduleId': after['id'],
                'moduleName': after['moduleName'], 'projectId': after['projectId'],
                'projectName': after.get('projectName', ''), 'projectCode': after.get('projectCode', '')})
    if project_update:
        tx.update(project_update[0], {'notifiedMilestones': project_update[1]})
    base = time.time_ns() // 1000
    for offset, record in enumerate(records):
        key = base + offset
        tx.create(db.collection('notifications').document(str(key)), record | {
            'id': key, 'read': False, 'pushPending': True,
            'createdAt': datetime.now(timezone.utc).isoformat()})
