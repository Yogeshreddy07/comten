"""Read-only billing function timings against the dedicated development Firestore.

This does not deploy, mutate records, invoke notifications or measure Railway.
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
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--runs', type=int, default=5)
    args = parser.parse_args()
    if not 1 <= args.runs <= 10: parser.error('Use 1-10 finite read-only runs')
    identity = ROOT / '.local/development-service-account.json'
    account = json.loads(identity.read_text(encoding='utf-8-sig'))
    if account.get('project_id') != 'crompton-pms-dev-20261015':
        parser.error('Requires the dedicated development project identity')
    os.environ.update(ENVIRONMENT='development', PROJECT_ID='crompton-pms-dev-20261015',
                      GOOGLE_APPLICATION_CREDENTIALS=str(identity), ALLOW_REAL_MESSAGES='false',
                      MSG91_DISPATCH_ENABLED='false', ZEPTOMAIL_DISPATCH_ENABLED='false',
                      RESEND_DISPATCH_ENABLED='false', FCM_DISPATCH_ENABLED='false', PERFORMANCE_TRACE='0')
    for key in ('FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST'):
        os.environ.pop(key, None)
    sys.path.insert(0, str(ROOT / 'backend'))
    from app.config import settings
    if settings.environment != 'development' or settings.project_id != account['project_id']:
        raise SystemExit('Unexpected database environment')
    from app.operations import billing
    samples = []
    hashes = []
    for _ in range(args.runs):
        started = time.perf_counter()
        # Direct read function, not an authentication benchmark. The public API
        # continues to enforce its current_user dependency and manager role.
        rows = billing(user={'id':2, 'role':'PROJECT_CONTROLLER'})['data']
        samples.append(round((time.perf_counter()-started)*1000, 2))
        hashes.append(hashlib.sha256(json.dumps(sorted(rows, key=lambda r:r['moduleId']),
                                               sort_keys=True, default=str).encode()).hexdigest())
    result = {'scope':'Local function reading dedicated development Firestore; excludes Railway/API auth; no writes',
              'samples':samples,'median_ms':statistics.median(samples),'max_ms':max(samples),
              'row_count':len(rows),'response_hashes':hashes}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k != 'response_hashes'}, indent=2))


if __name__ == '__main__': main()
