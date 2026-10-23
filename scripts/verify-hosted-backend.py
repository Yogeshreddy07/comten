"""Finite hosted-development checks; one owned file is uploaded then deleted.

Never sends SMS/email or prints passwords, tokens, or signed storage URLs.
"""
import argparse
import json
import uuid
from pathlib import Path
from urllib.parse import urlparse

import httpx

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--url', required=True, help='Public HTTPS API origin, without /api')
args = parser.parse_args()
origin = args.url.rstrip('/')
if urlparse(origin).scheme != 'https' or urlparse(origin).path:
    parser.error('Use an HTTPS origin without a path')
logins = json.loads((ROOT / '.local/development-logins.json').read_text())
results = []


def expect(response, status, name):
    passed = response.status_code == status
    results.append({'check': name, 'passed': passed, 'status': response.status_code})
    print(('PASS ' if passed else 'FAIL ') + name, flush=True)
    if not passed:
        raise RuntimeError(name + ': unexpected HTTP status ' + str(response.status_code))
    return response


def ensure(condition, name):
    results.append({'check': name, 'passed': bool(condition)})
    print(('PASS ' if condition else 'FAIL ') + name, flush=True)
    if not condition:
        raise RuntimeError(name)


tokens = {}
file_id = None
try:
    with httpx.Client(base_url=origin, timeout=60) as api:
        health = expect(api.get('/health'), 200, 'Public HTTPS health').json()
        ensure(health.get('environment') == 'development' and
               health.get('project') == 'crompton-pms-dev-20261015',
               'Dedicated development Firebase project')
        expect(api.get('/docs'), 200, 'API documentation')
        expect(api.get('/api/users/me'), 401, 'Anonymous profile rejected')
        expect(api.get('/api/reports/projects', headers={'Authorization': 'Bearer forged'}),
               401, 'Forged token rejected')
        expect(api.post('/api/auth/login', json={'employeeCode': 'EMP001', 'password': 'invalid'}),
               401, 'Incorrect password rejected')
        for code, role in [('CAP001', 'CAPTAIN'), ('PC001', 'PROJECT_CONTROLLER'),
                           ('TL001', 'TEAM_LEADER'), ('EMP001', 'EMPLOYEE')]:
            response = expect(api.post('/api/auth/login', json={
                'employeeCode': code, 'password': logins[code]['password']}),
                200, code + ' hosted Firebase login')
            tokens[code] = {'Authorization': 'Bearer ' + response.json()['data']['token']}
            profile = expect(api.get('/api/users/me', headers=tokens[code]),
                             200, code + ' authenticated Firestore profile').json()['data']
            ensure(profile['employeeCode'] == code and profile['role'] == role,
                   code + ' correct identity and role')
        for code in ('TL001', 'EMP001'):
            expect(api.get('/api/reports/projects', headers=tokens[code]),
                   403, code + ' manager reports denied')
            expect(api.post('/api/employees', json={'employeeCode': 'DENIED',
                'name': 'Synthetic denied', 'email': 'denied@example.invalid',
                'role': 'EMPLOYEE'}, headers=tokens[code]),
                403, code + ' employee provisioning denied')
        reports = ['attendance/employees', 'attendance/employees/4?year=2026&month=10',
                   'working-hours/employees',
                   'working-hours/employees/4?from=2026-10-01&to=2026-10-23',
                   'projects', 'projects/100', 'projects/100/modules/101',
                   'billing/projects/100', 'billing/modules/101', 'clients',
                   'clients/DEMO-CLIENT', 'billing-status']
        for code in ('CAP001', 'PC001'):
            for path in reports:
                response = expect(api.get('/api/reports/' + path, headers=tokens[code]),
                                  200, code + ' report ' + path)
                ensure(response.json().get('success') is True,
                       code + ' report response contract ' + path)
        expect(api.get('/api/reports/attendance/employees/4?month=13', headers=tokens['CAP001']),
               422, 'Invalid report range rejected')
        # All negative OTP checks stop before provider dispatch. No dummy
        # recipient is ever used in a send request.
        expect(api.post('/api/auth/phone/verify', json={'otp': '000000'}),
               401, 'Anonymous phone OTP verification denied')
        expect(api.post('/api/auth/forgot-password/verify-otp', json={
            'employeeCode': 'QAUNKNOWN' + uuid.uuid4().hex[:8],
            'email': 'unknown@example.invalid', 'otp': '000000'}),
               401, 'Unknown email OTP rejected')
        expect(api.post('/api/auth/forgot-password/reset', json={
            'employeeCode': 'EMP001', 'resetToken': 'invalid',
            'newPassword': 'UnusedSynthetic123!', 'confirmPassword': 'UnusedSynthetic123!'}),
               401, 'Invalid password reset proof rejected')
        payload = b'%PDF-1.7\nSynthetic hosted Railway storage probe\n%%EOF'
        headers = tokens['EMP001']
        try:
            grant = expect(api.post('/api/files/authorize-upload', headers=headers, json={
                'name': 'railway-probe-' + uuid.uuid4().hex[:8] + '.pdf',
                'contentType': 'application/pdf', 'size': len(payload),
                'category': 'employee_document'}), 200,
                'Hosted private R2 upload authorization').json()['data']
            file_id = grant['id']
            upload = httpx.put(grant['url'], headers=grant['headers'], content=payload, timeout=45)
            expect(upload, 200, 'Direct signed R2 upload')
            expect(api.post('/api/files/' + file_id + '/complete', headers=headers, json={}),
                   200, 'Hosted upload content verification')
            grant = expect(api.get('/api/files/' + file_id + '/download', headers=headers),
                           200, 'Hosted private R2 download authorization').json()['data']
            download = httpx.get(grant['url'], headers=grant['headers'], timeout=45)
            expect(download, 200, 'Direct signed R2 download')
            ensure(download.content == payload, 'Uploaded and downloaded bytes match')
            expect(api.get('/api/files/' + file_id + '/download'),
                   401, 'Anonymous private file download denied')
            expect(api.get('/api/files?category=employee_document', headers=headers),
                   200, 'Hosted file listing and Firestore index')
        finally:
            if file_id:
                expect(api.delete('/api/files/' + file_id, headers=headers),
                       200, 'Owned synthetic R2 object deleted')
                expect(api.get('/api/files/' + file_id + '/download', headers=headers),
                       409, 'Deleted file no longer downloadable')
finally:
    output = ROOT / '.local/railway-deployment/hosted-results.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({'origin': origin, 'checks': results,
        'otpDeliveryVerified': False, 'physicalDeviceTested': False}, indent=2))

print('All hosted backend checks passed. No SMS/email was sent.', flush=True)
