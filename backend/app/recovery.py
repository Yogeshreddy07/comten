import hashlib
import hmac
import secrets
import time
from fastapi import APIRouter, Depends, HTTPException
from firebase_admin import auth,firestore
from .config import settings
from .security import current_user
from .store import db,get,rows,transact
from .messaging import email,send_msg91,verify_msg91,normalize_phone
from .models import valid_password

router=APIRouter(prefix='/api')
GENERIC='If the supplied details match an active account, a verification code has been sent.'


def digest(value):
    key=settings.recovery_hmac_key or ('synthetic-emulator-only-key' if settings.environment=='local' else '')
    if not key: raise HTTPException(503,'Recovery is not configured')
    return hmac.new(key.encode(),value.encode(),hashlib.sha256).hexdigest()


def resolve(code):
    found=rows('employees',[('employeeCode',str(code).strip().upper())],2)
    return found[0] if len(found)==1 and found[0].get('active') and not found[0].get('deleted') else None


@router.post('/auth/forgot-password/send-otp')
async def send_otp(body: dict):
    person=resolve(body.get('employeeCode',''))
    if not person or person.get('activationStatus') in ('PENDING', 'PHONE_PENDING') or person.get('email','').strip().lower()!=str(body.get('email','')).strip().lower(): return {'success':True,'data':None,'message':GENERIC}
    uid=str(person['id']);ref=db.collection('recovery').document(uid);otp='123456' if settings.environment=='local' else str(secrets.randbelow(900000)+100000);now=time.time()
    challenge=secrets.token_hex(16)
    @firestore.transactional
    def reserve(tx):
        previous=ref.get(transaction=tx).to_dict() or {}
        count=previous.get('sendCount',0) if previous.get('sendWindow',0)>now-3600 else 0
        if previous.get('lastSent',0)>now-60:
            if previous.get('deliveryState') == 'ACCEPTED' and previous.get('recipientHash') == digest(person['email'].strip().lower()): return False
            raise HTTPException(429,'Wait one minute before requesting another OTP')
        if count>=5: raise HTTPException(429,'Too many OTP requests. Please try again later')
        tx.set(ref,{'otpHash':digest(uid+':'+otp),'recipientHash':digest(person['email'].strip().lower()),'expires':now+600,'attempts':0,'lastSent':now,'resetHash':None,'deliveryId':challenge,'deliveryState':'SENDING','sendCount':count+1,'sendWindow':previous.get('sendWindow',now) if count else now})
        return True
    if not transact(reserve): return {'success':True,'data':None,'message':GENERIC}
    try:
        if settings.environment!='local':
            from .email_templates import render
            subject,html,text=render('recovery',person['name'],otp=otp)
            await email(person['email'],person['name'],subject,html,text=text,delivery_key=challenge)
    except HTTPException:
        ref.update({'deliveryState':'FAILED','otpHash':'unavailable'})
        import logging
        logging.getLogger('crompton').warning('Password recovery email dispatch failed')
        raise HTTPException(503,'Unable to send the verification email. Contact your administrator or retry after one minute.') from None
    ref.update({'deliveryState':'ACCEPTED'})
    return {'success':True,'data':None,'message':GENERIC}


@router.post('/auth/forgot-password/verify-otp')
def verify_otp(body: dict):
    person=resolve(body.get('employeeCode',''))
    if not person or person.get('activationStatus') in ('PENDING', 'PHONE_PENDING') or person.get('email','').strip().lower()!=str(body.get('email','')).strip().lower(): raise HTTPException(401,'Invalid or expired verification code')
    uid=str(person['id']);ref=db.collection('recovery').document(uid);proof=secrets.token_urlsafe(32)
    @firestore.transactional
    def verify(tx):
        state=ref.get(transaction=tx).to_dict()
        if not state or state.get('recipientHash') != digest(person['email'].strip().lower()) or state.get('deliveryState')!='ACCEPTED' or state.get('expires',0)<time.time() or state.get('attempts',0)>=5 or state.get('resetHash'): return False
        valid=hmac.compare_digest(state['otpHash'],digest(uid+':'+str(body.get('otp',''))))
        tx.update(ref,{'attempts':state['attempts']+1,**({'resetHash':digest(proof),'otpHash':'consumed'} if valid else {})})
        return valid
    if not transact(verify): raise HTTPException(401,'Invalid or expired verification code')
    return {'success':True,'data':{'employeeCode':person['employeeCode'],'resetToken':proof},'message':'Code verified'}


@router.post('/auth/forgot-password/reset')
def reset(body: dict):
    person=resolve(body.get('employeeCode',''));password=body.get('newPassword','')
    if not person or password!=body.get('confirmPassword') or not valid_password(password): raise HTTPException(422,'Use matching passwords with at least 8 characters, uppercase, lowercase, a number and a special character')
    ref=db.collection('recovery').document(str(person['id']))
    @firestore.transactional
    def claim(tx):
        state=ref.get(transaction=tx).to_dict()
        if not state or state.get('recipientHash') != digest(person['email'].strip().lower()) or state.get('expires',0)<time.time() or state.get('resetBusyUntil',0)>time.time() or not state.get('resetHash') or not hmac.compare_digest(state['resetHash'],digest(str(body.get('resetToken','')))): return False
        tx.update(ref,{'resetBusyUntil':time.time()+60})
        return True
    if not transact(claim): raise HTTPException(401,'Invalid or expired reset session')
    try:
        auth.update_user(str(person['id']),password=password);auth.revoke_refresh_tokens(str(person['id']))
    except Exception:
        ref.update({'resetBusyUntil':0})
        raise HTTPException(502,'Password service is temporarily unavailable; retry this reset session') from None
    ref.update({'resetHash':None,'expires':0,'resetBusyUntil':0})
    from .delivery import event
    event(person['id'],'security','password-reset-'+str(person['id'])+'-'+str(time.time_ns()))
    return {'success':True,'data':None,'message':'Password updated. Sign in again.'}


@router.get('/users/phone-number/{code}')
def phone_number(code: str,user=Depends(current_user)):
    if user['employeeCode'].lower()!=code.lower(): raise HTTPException(403,'Permission denied')
    return {'success':True,'data':{'phoneNumber':user.get('phone','')},'message':'Phone number retrieved'}


@router.post('/auth/phone/send')
async def phone_send(body: dict,user=Depends(current_user)):
    phone=normalize_phone(body.get('phone',''))
    if phone!=normalize_phone(user.get('phone','')): raise HTTPException(403,'Use the enrolled phone number')
    uid=str(user['id']);ref=db.collection('phone-challenges').document(uid)
    throttle=db.collection('phone-rate-limits').document(hashlib.sha256(phone.encode()).hexdigest())
    now=time.time();challenge=secrets.token_hex(16)
    @firestore.transactional
    def reserve(tx):
        old=ref.get(transaction=tx).to_dict() or {}
        rate=throttle.get(transaction=tx).to_dict() or {}
        count=rate.get('count',0) if rate.get('window',0)>now-3600 else 0
        # A locked-out code can be replaced immediately; the hourly cap still applies.
        locked=old.get('attempts',0)>=5 and old.get('phone')==phone
        if count>=5:
            wait=max(1,int(rate.get('window',now)+3600-now)+1)
            raise HTTPException(429,'Too many OTP requests. Please try again later.',headers={'Retry-After':str(wait)})
        if not locked and (old.get('sent',0)>now-60 or rate.get('lastSent',0)>now-60):
            wait=max(1,int(max(old.get('sent',0),rate.get('lastSent',0))+60-now)+1)
            raise HTTPException(429,f'Please wait {wait} seconds before requesting another code.',headers={'Retry-After':str(wait)})
        tx.set(ref,{'challengeId':challenge,'sent':now,'expires':now+600,'attempts':0,'phone':phone,'state':'SENDING'})
        tx.set(throttle,{'lastSent':now,'count':count+1,'window':rate.get('window',now) if count else now,'expires':now+86400})
        return True
    if not transact(reserve): raise HTTPException(429,'Wait before requesting another code')
    try:
        request_id=await send_msg91(phone) if settings.environment!='local' else 'synthetic'
    except HTTPException:
        ref.update({'state':'SEND_FAILED'})
        raise
    ref.update({'state':'SENT','providerRequestId':request_id,'widgetId':settings.msg91_widget_id})
    return {'success':True,'data':{'resendAfterSeconds':60},'message':'Verification code requested'}


@router.post('/auth/phone/verify')
async def phone_verify(body: dict,user=Depends(current_user)):
    uid=str(user['id']);ref=db.collection('phone-challenges').document(uid)
    employee=db.collection('employees').document(uid);claim_id=secrets.token_hex(16)
    @firestore.transactional
    def claim(tx):
        row=ref.get(transaction=tx).to_dict()
        if not row or row.get('state')!='SENT': return 'OTP has expired. Tap Resend OTP to get a new code.'
        if row.get('retiredMessage'): return row['retiredMessage']
        if row['expires']<time.time(): return 'OTP has expired. Tap Resend OTP to get a new code.'
        if row['attempts']>=5: return 'Too many incorrect attempts. Tap Resend OTP to get a new code.'
        if row.get('busyUntil',0)>time.time(): return 'Verification already in progress. Please wait a moment and retry.'
        tx.update(ref,{'attempts':row['attempts']+1,'claim':claim_id,'busyUntil':time.time()+60})
        return row
    row=transact(claim)
    if isinstance(row,str): raise HTTPException(401,row)
    try:
        if settings.environment=='local':
            if str(body.get('otp','')).strip()!='123456': raise HTTPException(401,'Invalid or expired verification code')
        else:
            if row.get('widgetId')!=settings.msg91_widget_id: raise HTTPException(401,'Widget configuration changed; request another code')
            await verify_msg91(row['phone'],str(body.get('otp','')).strip(),row['providerRequestId'])
    except Exception as error:
        rejected=isinstance(error,HTTPException) and error.status_code==401
        wrong=rejected and error.detail=='Invalid or expired verification code'
        retired=rejected and str(error.detail).startswith(('OTP has expired','Too many incorrect attempts'))
        # Always release the claim so the next try is evaluated. Provider
        # outages do not count against the user's attempts, and a code the
        # provider retired is closed so a new one can be sent at once.
        @firestore.transactional
        def release(tx):
            current=ref.get(transaction=tx).to_dict() or {}
            if current.get('claim')!=claim_id: return
            change={'busyUntil':0}
            if retired: change|={'attempts':5,'expires':0,'retiredMessage':str(error.detail)}
            elif not rejected: change['attempts']=max(current.get('attempts',1)-1,0)
            tx.update(ref,change)
        transact(release)
        if wrong:
            left=5-row['attempts']-1
            raise HTTPException(401,f'Incorrect OTP. {left} attempt{"s" if left!=1 else ""} left.' if left>0 else 'Too many incorrect attempts. Tap Resend OTP to get a new code.') from None
        if isinstance(error,HTTPException): raise
        raise HTTPException(502,'SMS verification is temporarily unavailable. Please retry.') from None
    @firestore.transactional
    def consume(tx):
        current=ref.get(transaction=tx).to_dict() or {}
        person=employee.get(transaction=tx).to_dict() or {}
        if current.get('challengeId')!=row['challengeId'] or current.get('claim')!=claim_id or current.get('state')!='SENT': return False
        if current.get('expires',0)<time.time() or not person.get('active') or normalize_phone(person.get('phone',''))!=row['phone']: return False
        tx.update(employee,{'phoneVerified':True})
        tx.update(ref,{'state':'CONSUMED','busyUntil':0,'verifiedAt':time.time()})
        return True
    if not transact(consume): raise HTTPException(401,'Verification session changed; request another code')
    result={}
    if settings.environment!='local' and not user.get('_activationSession'): result['customToken']=auth.create_custom_token(uid).decode()
    return {'success':True,'data':result,'message':'Phone verified'}


@router.post('/auth/signup/verify-phone')
def confirm_phone(body: dict,user=Depends(current_user)):
    try: token=auth.verify_id_token(str(body.get('idToken','')),check_revoked=True)
    except Exception: raise HTTPException(401,'Invalid verification session') from None
    if token['uid']!=str(user['id']) or not get('employees',user['id']).get('phoneVerified'): raise HTTPException(403,'Phone verification required')
    return {'success':True,'data':user|{'phoneVerified':True},'message':'Phone verified'}
