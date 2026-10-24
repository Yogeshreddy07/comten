"""Serialize employee identity changes, including records created before this check."""
import re

from fastapi import HTTPException
from firebase_admin import firestore

from .models import normalize_phone
from .store import db, transact


def identity_conflicts(records, candidate, exclude_uid=None):
    """Return field errors naming the owners, without exposing other contacts."""
    owners = {'employeeCode': [], 'email': [], 'phone': []}
    phone = normalize_phone(candidate.get('phone'))
    email = str(candidate.get('email', '')).strip().lower()
    code = str(candidate.get('employeeCode') or '').strip().upper()
    for other in records:
        if exclude_uid is not None and str(other.get('id')) == str(exclude_uid):
            continue
        label = f"{other.get('name', 'Employee')} ({other.get('employeeCode', other.get('id'))})"
        if code and str(other.get('employeeCode', '')).strip().upper() == code:
            owners['employeeCode'].append(label)
        if email and str(other.get('email', '')).strip().lower() == email:
            owners['email'].append(label)
        try:
            other_phone = normalize_phone(other.get('phone'))
        except ValueError:
            other_phone = ''
        if phone and other_phone == phone:
            owners['phone'].append(label)
    labels = {'employeeCode': 'Employee code', 'email': 'Email address', 'phone': 'Phone number'}
    return {field: f"{labels[field]} is already in use by {', '.join(names)}."
            for field, names in owners.items() if names}


def save_identity(uid, record, *, creating):
    # Every create/edit takes this shared lock. Checking and writing in one
    # transaction prevents two different accounts claiming the same contact.
    # Read legacy records too: they may store mixed-case mail or local phones.
    lock = db.collection('counters').document('employee-identities')
    ref = db.collection('employees').document(str(uid))

    @firestore.transactional
    def save(tx):
        state = lock.get(transaction=tx).to_dict() or {}
        snapshots = list(db.collection('employees').stream(transaction=tx))
        current = next((s.to_dict() for s in snapshots if s.id == str(uid)), None)
        if creating and current:
            raise HTTPException(409, 'Employee identifier already exists; retry')
        if not creating and not current:
            raise HTTPException(404, 'Employee not found')
        candidate = record.copy() if creating else current | record
        sequence = int(state.get('sequence', 0))
        for snap in snapshots:
            match = re.fullmatch(r'EMP(\d+)', str(snap.to_dict().get('employeeCode', '')).upper())
            if match:
                sequence = max(sequence, int(match[1]))
        if creating and not candidate.get('employeeCode'):
            sequence += 1
            candidate['employeeCode'] = f'EMP{sequence:03d}'
        conflicts = identity_conflicts([s.to_dict() | {'id': s.id} for s in snapshots], candidate, uid)
        if conflicts:
            raise HTTPException(409, ' '.join(conflicts.values()))
        # Keep the counter even after a failed provisioning attempt so no
        # issued identity is reused. Existing employee codes never change.
        tx.set(lock, {'sequence': sequence, 'version': int(state.get('version', 0)) + 1})
        if creating:
            tx.create(ref, candidate)
        else:
            tx.update(ref, record)
        return candidate

    return transact(save)
