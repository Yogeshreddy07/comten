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
from .messaging import email, normalize_phone
from .email_templates import render
from .models import valid_password

router = APIRouter(prefix='/api/auth/signup')
MAX_ATTEMPTS = 5
EXPIRED = 'OTP has expired. Tap Resend OTP to get a new code.'
LOCKED = 'Too many incorrect attempts. Tap Resend OTP to get a new code.'


def wrong_otp(attempts):
    left = MAX_ATTEMPTS - attempts
    if left <= 0:
        return LOCKED
    return f'Incorrect OTP. {left} attempt{"s" if left != 1 else ""} left.'


def mask_email(value):
    local, _, domain = str(value).strip().partition('@')
    return local[:1] + '**' + (local[-1:] if len(local) > 2 else '') + '@' + domain


def mask_phone(value):
    phone = normalize_phone(value)
    return '+' + '*' * (len(phone) - 4) + phone[-4:]


def eligible(person):
    return bool(person and person.get('active') and not person.get('deleted')
                and person.get('activationStatus') != 'ACTIVE'
                and (person.get('activationStatus') in ('PENDING', 'PHONE_PENDING') or not person.get('phoneVerified'))
                and person.get('email'))


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
        # A locked-out OTP can be replaced immediately; the hourly cap still applies.
        if old.get('lastSent', 0) > now - 60 and old.get('attempts', 0) < MAX_ATTEMPTS:
            if (old.get('deliveryState') == 'ACCEPTED' and old.get('recipientHash') == recipient_hash(person)
                    and old.get('expires', 0) > now and old.get('otpHash') != 'consumed'):
                return False
            raise HTTPException(429, 'Wait one minute before requesting another OTP')
        if count >= 5:
            raise HTTPException(429, 'Too many OTP requests. Please try again later')
        tx.set(ref, {'generation': generation, 'otpHash': digest('activation:' + uid + ':' + otp),
                     'recipientHash': recipient_hash(person), 'expires': now + 600, 'attempts': 0,
                     'lastSent': now, 'sendCount': count + 1, 'sendWindow': old.get('sendWindow', now) if count else now,
                     'deliveryState': 'SENDING', 'proofHash': None}, merge=True)
        return True

    if not transact(reserve):
        return True
    try:
        if settings.environment != 'local':
            subject, html, text = render('activation_otp', person['name'], code=person['employeeCode'], otp=otp)
            await email(person['email'], person['name'], subject, html, text=text, delivery_key='activation-' + generation)
    except HTTPException as error:
        ref.update({'deliveryState': 'FAILED', 'otpHash': 'unavailable'})
        category = {
            'Resend API key is not configured': 'MISSING_RESEND_API_KEY',
            'Resend sender is not configured': 'MISSING_RESEND_SENDER',
            'Invalid Resend credential format': 'INVALID_RESEND_API_KEY',
            'Configure a verified Resend sender domain': 'RESEND_SENDER_DOMAIN',
            'External messaging is disabled in this environment': 'MESSAGING_DISABLED',
            'Dispatch requires an explicitly approved test recipient': 'DISPATCH_OR_RECIPIENT_DISABLED',
        }.get(error.detail, 'PROVIDER_UNAVAILABLE')
        logging.getLogger('crompton').warning('Activation email dispatch failed: status %s; category %s', error.status_code, category)
        raise HTTPException(503, 'Unable to send the verification email. Contact your administrator or retry after one minute.') from None
    ref.update({'deliveryState': 'ACCEPTED'})
    return True


def resume_phone(person):
    """Reissue the phone session for an employee whose email and password are already done."""
    if person.get('activationStatus') != 'PHONE_PENDING' or not person.get('emailVerified'):
        return None
    ref = db.collection('email-activation').document(str(person['id']))
    state = ref.get().to_dict() or {}
    phone = normalize_phone(person.get('phone', ''))
    # An email changed after password setup needs fresh email proof.
    if not state.get('passwordSetAt') or state.get('recipientHash') != recipient_hash(person):
        return None
    token = secrets.token_urlsafe(32)
    ref.update({'phoneTokenHash': digest(token), 'phoneExpires': time.time() + 1800,
                'phoneHash': digest('phone:' + phone)})
    return {'stage': 'PHONE', 'employeeCode': person['employeeCode'],
            'phoneVerificationToken': token, 'maskedPhone': mask_phone(phone)}


@router.post('/send-otp')
async def send(body: dict):
    person = resolve(body.get('employeeCode', ''))
    if not person:
        raise HTTPException(404, 'No employee found with this employee code. Check the code and try again.')
    if not eligible(person):
        status = person.get('activationStatus')
        if status == 'ACTIVE' or (status not in ('PENDING', 'PHONE_PENDING') and person.get('phoneVerified')):
            raise HTTPException(409, 'This employee is already activated. Please log in with your password.')
        raise HTTPException(422, 'No email is registered for this employee. Contact your administrator.')
    resumed = resume_phone(person)
    if resumed:
        return {'success': True, 'data': resumed,
                'message': 'Email and password are already set. Verify your enrolled phone to finish activation.'}
    await send_activation(person)
    return {'success': True, 'data': {'stage': 'EMAIL', 'maskedEmail': mask_email(person['email'])},
            'message': 'OTP sent to your registered email.'}


@router.post('/verify-otp')
def verify(body: dict):
    person = resolve(body.get('employeeCode', ''))
    if not eligible(person):
        raise HTTPException(401, EXPIRED)
    uid = str(person['id'])
    ref = db.collection('email-activation').document(uid)
    proof = secrets.token_urlsafe(32)

    @firestore.transactional
    def consume(tx):
        state = ref.get(transaction=tx).to_dict() or {}
        attempts = state.get('attempts', 0)
        if (state.get('deliveryState') != 'ACCEPTED' or state.get('expires', 0) < time.time()
                or state.get('recipientHash') != recipient_hash(person) or state.get('proofHash')):
            return EXPIRED
        if attempts >= MAX_ATTEMPTS:
            return LOCKED
        valid = hmac.compare_digest(state['otpHash'], digest('activation:' + uid + ':' + str(body.get('otp', '')).strip()))
        tx.update(ref, {'attempts': attempts + 1,
                       **({'otpHash': 'consumed', 'proofHash': digest(proof)} if valid else {})})
        return None if valid else wrong_otp(attempts + 1)

    failure = transact(consume)
    if failure:
        raise HTTPException(401, failure)
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
    phone = normalize_phone(person.get('phone', ''))
    uid = str(person['id'])
    ref = db.collection('email-activation').document(uid)
    employee = db.collection('employees').document(uid)
    claim_id = secrets.token_hex(16)
    phone_token = secrets.token_urlsafe(32)

    @firestore.transactional
    def claim(tx):
        state = ref.get(transaction=tx).to_dict() or {}
        if (state.get('expires', 0) < time.time() or state.get('busyUntil', 0) > time.time()
                or state.get('recipientHash') != recipient_hash(person) or not state.get('proofHash')
                or not hmac.compare_digest(state['proofHash'], digest(str(body.get('signupToken', ''))))):
            return False
        tx.update(ref, {'claim': claim_id, 'busyUntil': time.time() + 180})
        return True

    if not transact(claim):
        raise HTTPException(401, 'Invalid or expired activation session')
    try:
        auth.update_user(uid, password=password, disabled=True)
        auth.revoke_refresh_tokens(uid)

        @firestore.transactional
        def finish(tx):
            state = ref.get(transaction=tx).to_dict() or {}
            current = employee.get(transaction=tx).to_dict() or {}
            if (state.get('claim') != claim_id or not eligible(current)
                    or recipient_hash(current) != state.get('recipientHash')
                    or state.get('expires', 0) < time.time()):
                raise HTTPException(409, 'Account details changed. Request a new OTP.')
            if normalize_phone(current.get('phone', '')) != phone:
                raise HTTPException(409, 'Account details changed. Request a new OTP.')
            tx.update(employee, {'activationStatus': 'PHONE_PENDING', 'emailVerified': True, 'phoneVerified': False,
                                 'permissionVersion': firestore.Increment(1)})
            tx.update(ref, {'proofHash': None, 'expires': 0, 'busyUntil': 0,
                            'phoneTokenHash': digest(phone_token), 'phoneExpires': time.time() + 1800,
                            'phoneHash': digest('phone:' + phone), 'passwordSetAt': time.time()})
        transact(finish)
    except Exception as error:
        if person.get('activationStatus') == 'PENDING':
            auth.update_user(uid, disabled=True)
        ref.update({'busyUntil': 0})
        if isinstance(error, HTTPException): raise
        raise HTTPException(502, 'Password service is temporarily unavailable. Retry this activation session.') from None
    return {'success': True, 'data': {'employeeCode': person['employeeCode'],
            'phoneVerificationToken': phone_token, 'maskedPhone': mask_phone(phone)},
            'message': 'Password set successfully. Verify your enrolled phone to finish activation.'}


def phone_session(body):
    person = resolve(body.get('employeeCode', ''))
    if not person or person.get('activationStatus') != 'PHONE_PENDING' or not person.get('emailVerified'):
        raise HTTPException(401, 'Phone verification session expired. Enter your employee code on Activate Account to continue.')
    ref = db.collection('email-activation').document(str(person['id']))
    state = ref.get().to_dict() or {}
    token_hash = digest(str(body.get('phoneVerificationToken', '')))
    if (not state.get('phoneTokenHash') or not hmac.compare_digest(state['phoneTokenHash'], token_hash)
            or state.get('phoneExpires', 0) < time.time()
            or state.get('recipientHash') != recipient_hash(person)
            or state.get('phoneHash') != digest('phone:' + normalize_phone(person.get('phone', '')))):
        raise HTTPException(401, 'Phone verification session expired. Enter your employee code on Activate Account to continue.')
    return person, ref, state


@router.post('/phone/send-otp')
async def send_phone(body: dict):
    from .recovery import phone_send
    person, _, _ = phone_session(body)
    # The destination always comes from the enrolled record, never from input.
    result = await phone_send({'phone': person['phone']}, user=person)
    result['data'] = {'maskedPhone': mask_phone(person['phone'])}
    return result


@router.post('/phone/verify-otp')
async def verify_phone(body: dict):
    from .recovery import phone_verify
    person, ref, state = phone_session(body)
    uid = str(person['id'])
    challenge_ref = db.collection('phone-challenges').document(uid)
    challenge = challenge_ref.get().to_dict() or {}
    # A verified SMS may be retried after a transient account-enable failure.
    completed = (person.get('phoneVerified') and challenge.get('state') == 'CONSUMED'
                 and challenge.get('verifiedAt', 0) >= state.get('passwordSetAt', time.time()))
    if not completed:
        await phone_verify({'otp': body.get('otp', '')}, user=person | {'_activationSession': True})
    employee_ref = db.collection('employees').document(uid)
    enable_claim = secrets.token_hex(16)

    @firestore.transactional
    def claim_enable(tx):
        session = ref.get(transaction=tx).to_dict() or {}
        if (session.get('phoneTokenHash') != digest(str(body.get('phoneVerificationToken', '')))
                or session.get('phoneExpires', 0) < time.time()
                or session.get('enableBusyUntil', 0) > time.time()):
            raise HTTPException(409, 'Activation is already completing. Wait and try logging in.')
        tx.update(ref, {'enableClaim': enable_claim, 'enableBusyUntil': time.time() + 180})
    transact(claim_enable)
    try:
        auth.update_user(uid, disabled=False)

        @firestore.transactional
        def finish(tx):
            current = employee_ref.get(transaction=tx).to_dict() or {}
            session = ref.get(transaction=tx).to_dict() or {}
            verified = challenge_ref.get(transaction=tx).to_dict() or {}
            if (session.get('enableClaim') != enable_claim
                    or not current.get('active') or current.get('deleted') or not current.get('emailVerified')
                    or not current.get('phoneVerified') or current.get('activationStatus') != 'PHONE_PENDING'
                    or session.get('phoneTokenHash') != digest(str(body.get('phoneVerificationToken', '')))
                    or session.get('phoneExpires', 0) < time.time()
                    or session.get('recipientHash') != recipient_hash(current)
                    or session.get('phoneHash') != digest('phone:' + normalize_phone(current.get('phone', '')))
                    or verified.get('state') != 'CONSUMED'
                    or verified.get('verifiedAt', 0) < session.get('passwordSetAt', time.time())
                    or verified.get('phone') != normalize_phone(current.get('phone', ''))):
                raise HTTPException(409, 'Activation details changed. Enter your employee code on Activate Account to continue.')
            tx.update(employee_ref, {'activationStatus': 'ACTIVE', 'permissionVersion': firestore.Increment(1)})
            tx.update(ref, {'phoneTokenHash': None, 'phoneExpires': 0, 'enableBusyUntil': 0})
        transact(finish)
    except Exception as error:
        if get('employees', uid).get('activationStatus') != 'ACTIVE':
            auth.update_user(uid, disabled=True)
        @firestore.transactional
        def release(tx):
            current = ref.get(transaction=tx).to_dict() or {}
            if current.get('enableClaim') == enable_claim: tx.update(ref, {'enableBusyUntil': 0})
        transact(release)
        if isinstance(error, HTTPException): raise
        raise HTTPException(502, 'Activation could not finish. Please retry phone verification.') from None
    return {'success': True, 'data': None, 'message': 'Email and phone verified. Account activated. You can now log in.'}
