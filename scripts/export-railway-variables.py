"""Prepare an ignored private JSON map for Railway's Variables Raw Editor."""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = 'crompton-pms-dev-20261015'
os.environ['ENVIRONMENT'] = 'development'
sys.path.insert(0, str(ROOT / 'backend'))
from app.config import Settings

settings = Settings()
account = json.loads((ROOT / '.local/development-service-account.json').read_text())
if account.get('project_id') != PROJECT:
    raise SystemExit('Expected the dedicated development service account')
values = {
    'ENVIRONMENT': 'development',
    'PROJECT_ID': PROJECT,
    'FIREBASE_API_KEY': json.loads((ROOT / 'firebase/development.web.json').read_text())['FIREBASE_API_KEY'],
    'FIREBASE_SERVICE_ACCOUNT_JSON': json.dumps(account),
    'RECOVERY_HMAC_KEY': (ROOT / '.local/development-recovery.key').read_text().strip(),
    'WEB_ORIGIN': 'http://127.0.0.1:3000',
    'ALLOW_REAL_MESSAGES': 'false',
    'MSG91_DISPATCH_ENABLED': 'false',
    'ZEPTOMAIL_DISPATCH_ENABLED': 'false',
    'FCM_DISPATCH_ENABLED': 'false',
    'APPROVED_SMS_RECIPIENTS': '',
    'APPROVED_EMAIL_RECIPIENTS': '',
    'APPROVED_FCM_USER_IDS': '',
}
for key in ('r2_endpoint', 'r2_bucket', 'r2_access_key', 'r2_secret_key',
            'msg91_auth_key', 'msg91_widget_id', 'zeptomail_token',
            'zeptomail_from', 'zeptomail_verified_domain', 'zeptomail_api_origin'):
    value = getattr(settings, key)
    if value:
        values[key.upper()] = value
output = ROOT / '.local/railway-variables.json'
output.write_text(json.dumps(values, indent=2))
print('Private Railway variable map written to .local/railway-variables.json; message dispatch remains off.')
