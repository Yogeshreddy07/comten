"""Finite local billing-list benchmark with actual Auth/Firestore emulators."""
import argparse
import json
import os
from pathlib import Path
import statistics
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    from app.config import settings
    if (settings.environment != 'local' or settings.project_id != 'demo-crompton-pms'
            or not all(os.getenv(k, '').startswith(('127.0.0.1:', 'localhost:'))
                       for k in ('FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST'))):
        parser.error('Requires owned local demo emulators')
    from fastapi.testclient import TestClient
    from app.main import app
    from app.store import db
    base = time.time_ns() // 1000
    refs = []
    samples = []
    try:
        batch = db.batch()
        for i in range(7):
            key = base + i
            ref = db.collection('modules').document(str(key))
            refs.append(ref)
            batch.create(ref, {'id':key, 'projectId':100, 'projectName':'Synthetic',
                              'moduleName':'Synthetic', 'teamLeadId':3, 'active':True,
                              'workStage':'BILLING', 'billingStatus':'INVOICE_RAISED'})
            if i < 2:
                lock = db.collection('pending-approvals').document(f'billing-status-change-requests-{key}')
                request = db.collection('billing-status-change-requests').document(str(key))
                refs.extend([lock, request])
                batch.create(lock, {'requestId':key})
                batch.create(request, {'approvalStatus':'PENDING' if i == 0 else 'APPROVED'})
        batch.commit()
        with TestClient(app) as client:
            response = client.post('/api/auth/login', json={'employeeCode':'CAP001', 'password':'SyntheticPass123!'})
            response.raise_for_status()
            headers = {'Authorization':'Bearer '+response.json()['data']['token']}
            for _ in range(10):
                started = time.perf_counter()
                response = client.get('/api/billing', headers=headers)
                response.raise_for_status()
                samples.append(round((time.perf_counter()-started)*1000, 2))
                rows = {row['moduleId']:row for row in response.json()['data']}
                assert all(rows[base+i]['reversionPending'] == (i == 0) for i in range(7))
                assert all(rows[base+i]['editable'] for i in range(7))
        result = {'scope':'7 billing modules, 10 authenticated local TestClient requests; includes pending/stale locks; excludes device/cloud',
                  'median_ms':statistics.median(samples), 'p95_ms':max(samples), 'max_ms':max(samples),
                  'samples':samples, 'errors':0}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2)+'\n')
        print(json.dumps(result, indent=2))
    finally:
        batch = db.batch()
        for ref in refs: batch.delete(ref)
        batch.commit()


if __name__ == '__main__': main()
