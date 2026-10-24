"""Email ownership proof for first password setup; no plaintext OTPs are stored."""
import hmac
import logging
import secrets
import time

from fastapi import APIRouter, HTTPException
from firebase_admin import auth, firestore
from .config import settings
from .store import db, get, transact
from .recovery import digest, resolve
from .messaging import email
from .email_templates import render
from .models import valid_password

router = APIRouter(prefix='/api/auth/signup')
GENERIC = 'If this account needs activation, an OTP has been sent to its registered email.'


def eligible(person):
    return bool(person and person.get('active') and not person.get('deleted')
                and person.get('activationStatus') != 'ACTIVE'
                and not person.get('phoneVerified') and person.get('email'))


def recipient_hash(person):
    return digest(str(person.get('email', '')).strip().lower())


async def send_activation(person):
    if not eligible(person):
        return False
    uid = str(person['id'])
    ref = db.collection('email-activation').document(uid)
    now = time.time()
    generation = secrets.token_hex(16)
    otp = '123456' if settings.environment == 'local' else str(secrets.randbelow(900000) + 100000)

    @firestore.transactional
    def reserve(tx):
        old = ref.get(transaction=tx).to_dict() or {}
        count = old.get('sendCount', 0) if old.get('sendWindow', 0) > now - 3600 else 0
        if old.get('lastSent', 0) > now - 60:
            if old.get('deliveryState') == 'ACCEPTED' and old.get('recipientHash') == recipient_hash(person):
                return False
            raise HTTPException(429, 'Wait one minute before requesting another OTP')
        if count >= 5:
            raise HTTPException(429, 'Too many OTP requests. Please try again later')
        tx.set(ref, {'generation': generation, 'otpHash': digest('activation:' + uid + ':' + otp),
                     'recipientHash': recipient_hash(person), 'expires': now + 600, 'attempts': 0,
                     'lastSent': now, 'sendCount': count + 1, 'sendWindow': old.get('sendWindow', now) if count else now,
                     'deliveryState': 'SENDING', 'proofHash': None})
        return True

    if not transact(reserve):
        return True
    try:
        if settings.environment != 'local':
            subject, html, text = render('activation_otp', person['name'], code=person['employeeCode'], otp=otp)
            await email(person['email'], person['name'], subject, html, text=text, delivery_key='activation-' + generation)
    except HTTPException as error:
        ref.update({'deliveryState': 'FAILED', 'otpHash': 'unavailable'})
        logging.getLogger('crompton').warning('Activation email dispatch failed: status %s', error.status_code)
        raise HTTPException(503, 'Unable to send the verification email. Contact your administrator or retry after one minute.') from None
    ref.update({'deliveryState': 'ACCEPTED'})
    return True


@router.post('/send-otp')
async def send(body: dict):
    person = resolve(body.get('employeeCode', ''))
    if eligible(person):
        await send_activation(person)
    return {'success': True, 'data': None, 'message': GENERIC}


@router.post('/verify-otp')
def verify(body: dict):
    person = resolve(body.get('employeeCode', ''))
    if not eligible(person):
        raise HTTPException(401, 'Invalid or expired verification code')
    uid = str(person['id'])
    ref = db.collection('email-activation').document(uid)
    proof = secrets.token_urlsafe(32)

    @firestore.transactional
    def consume(tx):
        state = ref.get(transaction=tx).to_dict() or {}
        if (state.get('deliveryState') != 'ACCEPTED' or state.get('expires', 0) < time.time()
                or state.get('recipientHash') != recipient_hash(person) or state.get('attempts', 0) >= 5
                or state.get('proofHash')):
            return False
        valid = hmac.compare_digest(state['otpHash'], digest('activation:' + uid + ':' + str(body.get('otp', ''))))
        tx.update(ref, {'attempts': state.get('attempts', 0) + 1,
                       **({'otpHash': 'consumed', 'proofHash': digest(proof)} if valid else {})})
        return valid

    if not transact(consume):
        raise HTTPException(401, 'Invalid or expired verification code')
    return {'success': True, 'message': 'Email verified. Set your password.',
            'data': {'employeeCode': person['employeeCode'], 'signupToken': proof}}


@router.post('/set-password')
def set_password(body: dict):
    person = resolve(body.get('employeeCode', ''))
    password = body.get('newPassword', '')
    if password != body.get('confirmPassword') or not valid_password(password):
        raise HTTPException(422, 'Use matching passwords with at least 8 characters, uppercase, lowercase, a number and a special character')
    if not eligible(person):
        raise HTTPException(401, 'Invalid or expired activation session')
    uid = str(person['id'])
    ref = db.collection('email-activation').document(uid)
    employee = db.collection('employees').document(uid)
    claim_id = secrets.token_hex(16)

    @firestore.transactional
    def claim(tx):
        state = ref.get(transaction=tx).to_dict() or {}
        if (state.get('expires', 0) < time.time() or state.get('busyUntil', 0) > time.time()
                or state.get('recipientHash') != recipient_hash(person) or not state.get('proofHash')
                or not hmac.compare_digest(state['proofHash'], digest(str(body.get('signupToken', ''))))):
            return False
        tx.update(ref, {'claim': claim_id, 'busyUntil': time.time() + 60})
        return True

    if not transact(claim):
        raise HTTPException(401, 'Invalid or expired activation session')
    try:
        auth.update_user(uid, password=password, disabled=False)
        auth.revoke_refresh_tokens(uid)

        @firestore.transactional
        def finish(tx):
            state = ref.get(transaction=tx).to_dict() or {}
            current = employee.get(transaction=tx).to_dict() or {}
            if (state.get('claim') != claim_id or not eligible(current)
                    or recipient_hash(current) != state.get('recipientHash')
                    or state.get('expires', 0) < time.time()):
                raise HTTPException(409, 'Account details changed. Request a new OTP.')
            tx.update(employee, {'activationStatus': 'ACTIVE', 'emailVerified': True,
                                 'permissionVersion': firestore.Increment(1)})
            tx.update(ref, {'proofHash': None, 'expires': 0, 'busyUntil': 0})
        transact(finish)
    except Exception as error:
        if person.get('activationStatus') == 'PENDING':
            auth.update_user(uid, disabled=True)
        ref.update({'busyUntil': 0})
        if isinstance(error, HTTPException): raise
        raise HTTPException(502, 'Password service is temporarily unavailable. Retry this activation session.') from None
    return {'success': True, 'data': None, 'message': 'Password set. Log in with your employee code and new password.'}
