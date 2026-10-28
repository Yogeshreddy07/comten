"""Finite, synthetic report benchmark; refuses nonlocal databases."""
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
            or not os.getenv('FIRESTORE_EMULATOR_HOST', '').startswith(('127.0.0.1:', 'localhost:'))):
        parser.error('Requires owned local demo emulator')
    from app.store import db
    from app.reports import employee_hours
    base = time.time_ns() // 1000
    refs = []
    logs = []
    try:
        batch = db.batch()
        for i in range(100):
            uid = base + i
            ref = db.collection('employees').document(str(uid))
            refs.append(ref)
            batch.create(ref, {'id': uid, 'employeeCode': 'BENCH', 'name': 'Synthetic', 'role': 'EMPLOYEE'})
            logs.append({'employeeId': uid, 'billableDurationSeconds': 3600, 'nonBillableDurationSeconds': 1800})
        batch.commit()
        samples = []
        for _ in range(10):
            start = time.perf_counter()
            result = employee_hours(logs, True)
            samples.append((time.perf_counter() - start) * 1000)
            assert len(result) == 100 and all(r['billableHours'] == 1 and r['nonBillableHours'] == .5 for r in result)
        report = {'scope': '100 employee report enrichment, local Firestore emulator, 10 warm-process runs; excludes HTTP/UI',
                  'milliseconds': {'median': statistics.median(samples), 'p95': max(samples), 'max': max(samples)},
                  'samples': samples, 'errors': 0}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))
    finally:
        batch = db.batch()
        for ref in refs:
            batch.delete(ref)
        batch.commit()


if __name__ == '__main__':
    main()
