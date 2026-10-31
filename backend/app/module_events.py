"""Module progress and completion alerts committed with the work update."""
import time
from datetime import datetime, timezone
from google.cloud.firestore_v1.base_query import FieldFilter
from .store import db
from .mobile_contracts import effective_status

MILESTONES = (30, 60, 90, 100)


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
    # The caller reads the module in this transaction. Its markers serialize
    # simultaneous approvals without coupling progress to sibling modules.
    records = []
    module_update = None
    if (worked_seconds(after) > worked_seconds(before)
            and after.get('active', True) and not after.get('deleted')):
        project_ref = db.collection('projects').document(str(after['projectId']))
        project = project_ref.get(transaction=tx).to_dict() or {}
        if project.get('active') and not project.get('deleted'):
            estimate = (after.get('estimatedMinutes') or 0) * 60
            previous = worked_seconds(before)
            current = worked_seconds(after)
            notified = set(before.get('notifiedMilestones', []))
            crossed = [pct for pct in MILESTONES if pct not in notified
                       and estimate > 0 and previous * 100 < pct * estimate <= current * 100]
            if crossed:
                recipients = recipients_for(tx, [after])
                # A single update may skip multiple levels. Notify only the
                # latest level, but consume every crossed level atomically so
                # skipped reminders cannot arrive later or repeat on recrossing.
                pct = max(crossed)
                for person in recipients:
                    records.append({
                        'userId': person['id'], 'title': 'Module completed' if pct == 100 else f'Module {pct}% completed',
                        'message': f'{after["moduleName"]} has reached {pct}% of its estimated hours.',
                        'type': 'MODULE_MILESTONE_REACHED', 'milestonePercent': pct,
                        'moduleId': after['id'], 'moduleName': after['moduleName'],
                        'projectId': after['projectId'], 'projectName': project['projectName'],
                        'projectCode': project.get('projectCode', ''),
                        'estimatedMinutes': estimate // 60, 'workedMinutes': current // 60})
                module_update = (db.collection('modules').document(str(after['id'])), sorted(notified | set(crossed)))
    progress_completed = any(r.get('milestonePercent') == 100 for r in records)
    if (not progress_completed and effective_status(before) != 'COMPLETED'
            and effective_status(after) == 'COMPLETED'):
        for person in recipients_for(tx, [after]):
            records.append({
                'userId': person['id'], 'title': 'Module completed',
                'message': f'{after["moduleName"]} is completed.',
                'type': 'MODULE_MILESTONE_REACHED', 'moduleId': after['id'],
                'moduleName': after['moduleName'], 'projectId': after['projectId'],
                'projectName': after.get('projectName', ''), 'projectCode': after.get('projectCode', '')})
    if module_update:
        tx.update(module_update[0], {'notifiedMilestones': module_update[1]})
    base = time.time_ns() // 1000
    for offset, record in enumerate(records):
        key = base + offset
        tx.create(db.collection('notifications').document(str(key)), record | {
            'id': key, 'read': False, 'pushPending': True,
            'createdAt': datetime.now(timezone.utc).isoformat()})
    return base + len(records) - 1 if records else 0
