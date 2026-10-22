"""Reset only the four known synthetic development accounts for tester handoff.

Set PMS_TESTER_PASSWORD in the process environment. Never targets production or
sends messages. Blank phones get synthetic placeholder numbers for this handoff.
"""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = 'crompton-pms-dev-20261015'
identity = ROOT / '.local/development-service-account.json'
if json.loads(identity.read_text())['project_id'] != PROJECT:
    raise SystemExit('Expected the dedicated development identity')
password = os.environ.get('PMS_TESTER_PASSWORD', '')
os.environ.update(ENVIRONMENT='development', PROJECT_ID=PROJECT,
                  GOOGLE_APPLICATION_CREDENTIALS=str(identity))
for key in ('FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST'):
    os.environ.pop(key, None)
sys.path.insert(0, str(ROOT / 'backend'))
from app.models import valid_password
from app.store import db, get, rows
from firebase_admin import auth
import httpx

if not valid_password(password):
    raise SystemExit('Set PMS_TESTER_PASSWORD to a valid test password')
records = ROOT / '.local/development-logins.json'
saved = json.loads(records.read_text())
roles = [(1, 'CAP001', 'CAPTAIN'), (2, 'PC001', 'PROJECT_CONTROLLER'),
         (3, 'TL001', 'TEAM_LEADER'), (4, 'EMP001', 'EMPLOYEE')]
# Check every identity before changing any password.
for uid, code, role in roles:
    user = auth.get_user(str(uid))
    profile = get('employees', uid)
    if (user.display_name != 'Synthetic Development ' + role.replace('_', ' ').title()
            or user.email != code.lower() + '@accounts.crompton.invalid'
            or user.disabled or not profile or not profile.get('active')
            or profile.get('employeeCode') != code or profile.get('role') != role
            or code not in saved):
        raise SystemExit('Unexpected synthetic identity: ' + code)
    if not profile.get('phone'):
        dummy = '900000000' + str(uid)
        if rows('employees', [('phone', dummy)], 1):
            raise SystemExit('Placeholder phone is already assigned: ' + code)
api_key = json.loads((ROOT / 'firebase/development.web.json').read_text())['FIREBASE_API_KEY']
results = []
for uid, code, role in roles:
    if not get('employees', uid).get('phone'):
        # Preserve the existing preverified synthetic fixture status. This is
        # not evidence of SMS receipt and must never be used for live dispatch.
        db.collection('employees').document(str(uid)).update({'phone': '900000000' + str(uid)})
    auth.update_user(str(uid), password=password)
    auth.revoke_refresh_tokens(str(uid))
    saved[code]['password'] = password
    records.write_text(json.dumps(saved, indent=2))
    response = httpx.post(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword',
        params={'key': api_key},
        json={'email': code.lower() + '@accounts.crompton.invalid',
              'password': password, 'returnSecureToken': True}, timeout=30)
    data = response.json()
    if response.status_code != 200 or data.get('localId') != str(uid):
        raise SystemExit('Cloud login verification failed for ' + code)
    claims = auth.verify_id_token(data['idToken'])
    if claims.get('role') != role:
        raise SystemExit('Role claim mismatch for ' + code)
    profile = get('employees', uid)
    results.append({'employeeCode': code, 'role': role, 'cloudLogin': 'PASS',
                    'phone': profile.get('phone', ''),
                    'phoneVerified': profile.get('phoneVerified', False),
                    'email': profile.get('email', '')})
output = ROOT / 'tests/tester-accounts.json'
output.write_text(json.dumps({'project': PROJECT, 'accounts': results}, indent=2))
print('All four development passwords updated; real Firebase login and role claims PASS.')
