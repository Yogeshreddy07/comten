"""Serialize employee identity changes, including records created before this check."""
import re

from fastapi import HTTPException
from firebase_admin import firestore

from .models import normalize_phone
from .store import db, transact


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
        for snap in snapshots:
            if snap.id == str(uid):
                continue
            other = snap.to_dict()
            if str(other.get('employeeCode', '')).strip().upper() == str(candidate['employeeCode']).strip().upper():
                raise HTTPException(409, 'Employee code is already in use')
            if str(other.get('email', '')).strip().lower() == str(candidate['email']).strip().lower():
                raise HTTPException(409, 'Email address is already in use')
            try:
                phone = normalize_phone(other.get('phone'))
            except ValueError:
                phone = ''
            if candidate.get('phone') and phone == normalize_phone(candidate['phone']):
                raise HTTPException(409, 'Phone number is already in use')
        # Keep the counter even after a failed provisioning attempt so no
        # issued identity is reused. Existing employee codes never change.
        tx.set(lock, {'sequence': sequence, 'version': int(state.get('version', 0)) + 1})
        if creating:
            tx.create(ref, candidate)
        else:
            tx.update(ref, record)
        return candidate

    return transact(save)
