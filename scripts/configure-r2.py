"""Read-only validation by default; explicit --apply-cors only changes this dev bucket."""
import argparse
import json
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'backend'))
parser=argparse.ArgumentParser()
parser.add_argument('--apply-cors',action='store_true')
args=parser.parse_args()
if os.environ.get('ENVIRONMENT')!='development':
    parser.error('Set ENVIRONMENT=development; only the dedicated development bucket is allowed')
from app.config import settings
from app.storage import client
if settings.project_id!='crompton-pms-dev-20261015' or settings.r2_bucket!='crompton-pms-dev':
    parser.error('Expected dedicated Crompton development project/bucket')
try:
    s3=client()
    s3.list_objects_v2(Bucket=settings.r2_bucket,Prefix='v1/',MaxKeys=1)
    if args.apply_cors:
        # Bucket configuration requires an owner/admin setup credential, beyond
        # the runtime bucket-scoped Object Read & Write permission. Prefer the
        # dashboard CORS editor rather than widening the application's key.
        s3.put_bucket_cors(Bucket=settings.r2_bucket, CORSConfiguration=json.loads((ROOT/'firebase/r2.cors.development.json').read_text()))
        actual=s3.get_bucket_cors(Bucket=settings.r2_bucket)
        expected=json.loads((ROOT/'firebase/r2.cors.development.json').read_text())
        if actual['CORSRules']!=expected['CORSRules']: raise RuntimeError('CORS differs from approved development origins')
    print('Dedicated bucket authentication verified. No objects uploaded; public access not enabled. CORS must be checked with the live preflight probe.')
except Exception:
    print('R2 validation failed. Check scoped credentials/bucket. CORS changes require owner setup permission: use bucket Settings > CORS Policy; do not widen the runtime key.',file=sys.stderr)
    sys.exit(1)
