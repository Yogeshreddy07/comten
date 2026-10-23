"""Verify an already-sent hosted phone OTP; no send or resend is performed.

Read the user-supplied code from PMS_TEST_OTP. Never persist the code or tokens.
The employee must have an existing challenge and enrolled phone number.
"""
import argparse
import json
import os
import time
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--employee-code', default='EMP001')
parser.add_argument('--resume-confirmation', action='store_true',
                    help='Finish confirmation after a previously recorded successful OTP/session exchange')
args = parser.parse_args()
code = os.environ.get('PMS_TEST_OTP', '')
if len(code) != 6 or not code.isdecimal():
    raise SystemExit('Set PMS_TEST_OTP to the six-digit code received by the user')
login = json.loads((ROOT / '.local/development-logins.json').read_text())[args.employee_code]
firebase = json.loads((ROOT / 'firebase/development.web.json').read_text())
origin = firebase['BASE_URL'].removesuffix('/api')
path = ROOT / '.local/railway-deployment/otp-live-results.json'
state = json.loads(path.read_text()) if path.exists() else {}


def expect(response, status, label):
    if response.status_code != status:
        raise SystemExit(label + ': unexpected HTTP ' + str(response.status_code))
    print(label + ': PASS', flush=True)
    return response


with httpx.Client(base_url=origin, timeout=45) as api:
    session = expect(api.post('/api/auth/login', json={
        'employeeCode': args.employee_code, 'password': login['password']}),
        200, 'Hosted employee login').json()['data']
    headers = {'Authorization': 'Bearer ' + session['token']}
    if args.resume_confirmation:
        if not (state.get('hostedOtpVerified') and state.get('firebaseSessionLinked')
                and state.get('account') == args.employee_code and session.get('phoneVerified')):
            raise SystemExit('No previously verified session is available to resume')
        id_token = session['token']
    else:
        result = expect(api.post('/api/auth/phone/verify', headers=headers,
                                json={'otp': code}),
                        200, 'Hosted MSG91 OTP verification').json()['data']
        firebase_session = expect(httpx.post(
            'https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken',
            params={'key': firebase['FIREBASE_API_KEY']}, json={
                'token': result['customToken'], 'returnSecureToken': True}, timeout=30),
            200, 'Firebase custom-token session linkage').json()
        id_token = firebase_session['idToken']
        state.update(account=args.employee_code, hostedOtpVerified=True,
                     firebaseSessionLinked=True)
        path.write_text(json.dumps(state, indent=2))
    headers = {'Authorization': 'Bearer ' + id_token}
    expect(api.post('/api/auth/signup/verify-phone', headers=headers, json={
        'employeeCode': args.employee_code, 'phoneNumber': session['phone'],
        'idToken': id_token}),
        200, 'Application activation phone confirmation')
    profile = expect(api.get('/api/users/me', headers=headers),
                     200, 'Verified profile retrieval').json()['data']
    if (not profile.get('phoneVerified') or profile['employeeCode'] != args.employee_code
            or str(profile['id']) != str(session['id'])):
        raise SystemExit('Phone verification state was not committed')
    expect(api.post('/api/auth/phone/verify', headers=headers, json={'otp': code}),
           401, 'Consumed OTP replay rejected')

state.update(account=args.employee_code, verificationComplete=True,
             firebaseSessionLinked=True, activationConfirmation=True,
             replayRejected=True, verifiedAt=time.time())
path.write_text(json.dumps(state, indent=2))
print('Real hosted phone verification completed. No OTP or tokens were persisted.')
