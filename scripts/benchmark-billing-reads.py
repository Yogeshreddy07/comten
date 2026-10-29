"""Finite, read-only comparison of legacy and batched billing enrichment.

Cloud mode is pinned to the existing development project. It does not exercise
HTTP authentication or the UI and cannot certify deployed latency.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cloud', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    os.environ.update(ENVIRONMENT='development' if args.cloud else 'local',
                      PROJECT_ID='crompton-pms-dev-20261015' if args.cloud else 'demo-crompton-pms',
                      ALLOW_REAL_MESSAGES='false', FCM_DISPATCH_ENABLED='false',
                      MSG91_DISPATCH_ENABLED='false', RESEND_DISPATCH_ENABLED='false')
    if args.cloud:
        identity = ROOT / '.local/development-service-account.json'
        assert json.loads(identity.read_text())['project_id'] == os.environ['PROJECT_ID']
        os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = str(identity)
        for name in ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']:
            os.environ.pop(name, None)
    else:
        os.environ['FIRESTORE_EMULATOR_HOST'] = '127.0.0.1:8086'
        os.environ['FIREBASE_AUTH_EMULATOR_HOST'] = '127.0.0.1:9099'
    sys.path.insert(0, str(ROOT / 'backend'))
    from app import operations
    from app.config import settings
    assert settings.project_id == os.environ['PROJECT_ID']
    def legacy():
        return [operations.billing_row(m) for m in operations.all_rows('modules')
                if not m.get('deleted') and m.get('workStage') == 'BILLING']
    def batched():
        return operations.billing({'role': 'CAPTAIN'})['data']
    samples = {'legacy': [], 'batched': []}
    for _ in range(5):
        rows = {}
        for name, operation in [('legacy', legacy), ('batched', batched)]:
            started = time.perf_counter()
            rows[name] = operation()
            samples[name].append((time.perf_counter() - started) * 1000)
        assert rows['legacy'] == rows['batched'], 'Billing responses differ; possible concurrent update'
    report = {'scope': 'development cloud reads' if args.cloud else 'local emulator reads',
              'excludes': 'HTTP authentication, hosted backend, mobile UI',
              'rows': len(rows['batched']), 'samples_ms': samples,
              'response_sha256': hashlib.sha256(json.dumps(rows['batched'], sort_keys=True, default=str).encode()).hexdigest(),
              'summary_ms': {k: {'median': statistics.median(v), 'max': max(v)} for k, v in samples.items()},
              'equal_responses': True, 'writes': 0}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
