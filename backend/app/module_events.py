"""Completion alerts committed with the transition, retried by the push worker."""
import time
from datetime import datetime, timezone
from google.cloud.firestore_v1.base_query import FieldFilter
from .store import db
from .mobile_contracts import effective_status


def queue_completion(tx, before, after):
    # Call after all other reads and before writes. Repeated saves and further
    # approvals above the estimate must not emit another completion alert.
    if effective_status(before) == 'COMPLETED' or effective_status(after) != 'COMPLETED':
        return
    recipients = {s.to_dict()['id']: s.to_dict() for s in
                  db.collection('employees').where(filter=FieldFilter('role', 'in', ['CAPTAIN', 'PROJECT_CONTROLLER'])).stream(transaction=tx)}
    for uid in set(after.get('memberIds', [])) | ({after['teamLeadId']} if after.get('teamLeadId') else set()):
        person = db.collection('employees').document(str(uid)).get(transaction=tx).to_dict()
        if person:
            recipients[uid] = person
    base = time.time_ns() // 1000
    for offset, person in enumerate(recipients.values()):
        if not person.get('active') or person.get('deleted'):
            continue
        key = base + offset
        tx.create(db.collection('notifications').document(str(key)), {
            'id': key, 'userId': person['id'], 'title': 'Module completed',
            'message': f'{after["moduleName"]} is completed.',
            'type': 'MODULE_MILESTONE_REACHED', 'moduleId': after['id'],
            'moduleName': after['moduleName'], 'projectId': after['projectId'],
            'projectName': after.get('projectName', ''), 'projectCode': after.get('projectCode', ''),
            'read': False, 'pushPending': True, 'createdAt': datetime.now(timezone.utc).isoformat()})
