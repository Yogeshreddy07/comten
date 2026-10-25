"""Finite project lifecycle benchmark against the owned local emulator only."""
import argparse
import json
import hashlib
import os
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runs', type=int, default=10)
    parser.add_argument('--members', type=int, default=10)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    from app.config import settings
    if (settings.environment != 'local' or settings.project_id != 'demo-crompton-pms'
            or not all(os.getenv(key, '').startswith(('127.0.0.1:', 'localhost:'))
                       for key in ('FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST'))):
        parser.error('Requires the owned demo-crompton-pms Auth and Firestore emulators')
    if not 1 <= args.runs <= 30 or not 1 <= args.members <= 100:
        parser.error('Use 1-30 runs and 1-100 members')
    from fastapi.testclient import TestClient
    from app.main import app
    from app.store import db
    client = TestClient(app)
    login = client.post('/api/auth/login', json={
        'employeeCode': 'CAP001', 'password': 'SyntheticPass123!'})
    login.raise_for_status()
    headers = {'Authorization': 'Bearer ' + login.json()['data']['token']}
    base = time.time_ns() // 1000
    refs = []
    samples = {key: [] for key in ('create_project', 'deactivate_project',
                                  'activate_project', 'activate_module')}

    def request(label, method, url, **kwargs):
        start = time.perf_counter()
        response = client.request(method, url, headers=headers, **kwargs)
        elapsed = (time.perf_counter() - start) * 1000
        response.raise_for_status()
        samples[label].append(elapsed)
        return response.json()['data']

    try:
        batch = db.batch()
        for index in range(args.members + 1):
            ref = db.collection('employees').document(str(base + index))
            refs.append(ref)
            batch.create(ref, {'id': base + index, 'name': 'Benchmark',
                              'employeeCode': 'BENCH' + str(base + index), 'active': True,
                              'role': 'TEAM_LEADER' if index == 0 else 'EMPLOYEE',
                              'permissionVersion': 1})
        batch.commit()
        for index in range(args.runs):
            project = request('create_project', 'POST', '/api/projects', json={
                'projectCode': f'BENCH-{base}-{index}', 'projectName': 'Local benchmark',
                'moduleName': 'Design', 'teamLeadId': base,
                'memberIds': list(range(base + 1, base + args.members + 1)),
                'billableActivityIds': [1], 'nonBillableActivityIds': [2]})
            pid, mid = project['id'], project['modules'][0]['id']
            refs.extend([db.collection('projects').document(str(pid)),
                         db.collection('modules').document(str(mid)),
                         db.collection('project-codes').document(hashlib.sha256(project['projectCode'].casefold().encode()).hexdigest())])
            request('deactivate_project', 'DELETE', f'/api/projects/{pid}')
            request('activate_project', 'PUT', f'/api/projects/{pid}/activate', json={})
            request('activate_module', 'PUT', f'/api/modules/{mid}/activate', json={})
            # Do not accumulate active modules/rosters across samples.
            client.delete(f'/api/projects/{pid}', headers=headers).raise_for_status()
    finally:
        batch = db.batch()
        for ref in refs:
            batch.delete(ref)
        batch.commit()
    result = {'scope': 'Local TestClient + real Firebase Auth/Firestore emulators; excludes device/network/cloud latency',
              'members': args.members, 'runs': args.runs, 'milliseconds': {
                  key: {'median': round(statistics.median(values), 1),
                        'p95': round(sorted(values)[max(0, int(len(values) * .95 + .999) - 1)], 1),
                        'max': round(max(values), 1)} for key, values in samples.items()}}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
