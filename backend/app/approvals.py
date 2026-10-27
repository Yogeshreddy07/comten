"""One pending Captain approval per request type and target."""
from fastapi import HTTPException

from .store import db

PENDING_MESSAGES = {
    'billing-status-change-requests': 'A billing change for this module is already pending Captain approval.',
    'delay-requests': 'A reason for delay for this module is already pending approval.',
    'module-change-requests': 'A change request for this module is already pending Captain approval.',
    'project-deactivation-requests': 'Deactivation of this project is already pending Captain approval.',
}


def has_pending(collection, target_id):
    """Whether the target currently has a request awaiting a decision."""
    held = db.collection('pending-approvals').document(f'{collection}-{target_id}').get().to_dict() or {}
    if held.get('requestId') is None:
        return False
    existing = db.collection(collection).document(str(held['requestId'])).get().to_dict()
    return bool(existing and existing.get('approvalStatus') == 'PENDING')


def claim_pending(tx, collection, target_id, request_id):
    """Reserve the target for a new request inside `tx`, or raise 409.

    The lock document serializes concurrent submits; it goes stale on its own
    once the request it names is approved or rejected, so it is never deleted.
    """
    lock = db.collection('pending-approvals').document(f'{collection}-{target_id}')
    held = lock.get(transaction=tx).to_dict() or {}
    if held.get('requestId') is not None:
        existing = db.collection(collection).document(str(held['requestId'])).get(transaction=tx).to_dict()
        if existing and existing.get('approvalStatus') == 'PENDING':
            raise HTTPException(409, PENDING_MESSAGES[collection])
    tx.set(lock, {'collection': collection, 'targetId': target_id, 'requestId': request_id})
