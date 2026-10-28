"""Provider secrets and dispatch live exclusively on the trusted server."""
from datetime import datetime, timedelta, timezone
import re
import secrets
import logging
import threading
import httpx
from firebase_admin import firestore, messaging
from fastapi import HTTPException
from .config import settings
from .store import db, all_rows


async def provider_request(method,url,**kwargs):
    # Only connection establishment failures are retryable: no HTTP request
    # reached the provider. Read/write timeouts may already have sent a message.
    for attempt in range(2):
        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(20,connect=5)) as client:
                return await client.request(method,url,**kwargs)
        except (httpx.ConnectError,httpx.ConnectTimeout):
            if attempt==0: continue
        except httpx.RequestError: pass
        raise HTTPException(502,'Messaging provider is temporarily unavailable') from None


def provider_success(result):
    try: return result.status_code==200 and result.json().get('type')=='success'
    except (ValueError,AttributeError): raise HTTPException(502,'Invalid messaging provider response') from None


def external_allowed():
    if not settings.allow_real_messages:
        raise HTTPException(503,'External messaging is disabled in this environment')


def normalize_phone(value: str):
    value=re.sub(r'[\s()-]','',str(value))
    if value.startswith('+'): value=value[1:]
    if len(value)==10: value='91'+value
    if not re.fullmatch(r'[1-9][0-9]{7,14}',value):
        raise HTTPException(422,'Use a valid international phone number')
    if value.startswith('91') and not re.fullmatch(r'91[6-9][0-9]{9}',value):
        raise HTTPException(422,'Use a valid Indian mobile number')
    return value


def recipient_allowed(channel, recipient):
    external_allowed()
    enabled=getattr(settings,channel+'_dispatch_enabled')
    allowed=settings.approved_sms_recipients if channel=='msg91' else settings.approved_email_recipients
    values={v.strip().lower() for v in allowed.split(',') if v.strip()}
    enrolled = False
    if channel == 'msg91' and enabled and settings.sms_registered_recipients_enabled:
        from .store import rows
        variants = ['+' + recipient, recipient]
        if recipient.startswith('91') and len(recipient) == 12: variants.append(recipient[2:])
        matches = rows('employees', [('phone', 'in', variants)], 2)
        enrolled = len(matches)==1 and matches[0].get('active') and not matches[0].get('deleted')
    if channel in ('resend','zeptomail') and settings.email_registered_recipients_enabled and not recipient.lower().endswith(('.invalid', '@example.com')):
        from .store import rows
        matches = rows('employees',[('email',recipient.strip().lower())],2)
        enrolled = len(matches)==1 and matches[0].get('active') and not matches[0].get('deleted')
    if not enabled or (recipient.lower() not in values and not enrolled):
        raise HTTPException(503,'Dispatch requires an explicitly approved test recipient')


EMAIL_PROVIDERS=('resend','zeptomail')


def email_provider():
    provider=settings.email_provider.strip().lower()
    if provider not in EMAIL_PROVIDERS: raise HTTPException(503,'Unknown email provider')
    return provider


def sender_verified(sender,domain):
    return bool(domain) and sender.rsplit('@',1)[-1].lower()==domain.strip().lower()


async def email(to: str, name: str, subject: str, html: str, *, text: str='', delivery_key: str|None=None):
    provider=email_provider()
    send=resend_email if provider=='resend' else zeptomail_email
    await send(to,name,subject,html,text=text,delivery_key=delivery_key)


async def resend_email(to: str, name: str, subject: str, html: str, *, text: str='', delivery_key: str|None=None):
    recipient_allowed('resend',to)
    key=settings.resend_api_key.strip();sender=settings.resend_from.strip()
    if not key: raise HTTPException(503,'Resend API key is not configured')
    if not sender: raise HTTPException(503,'Resend sender is not configured')
    if not re.fullmatch(r're_[A-Za-z0-9_]+',key): raise HTTPException(503,'Invalid Resend credential format')
    if not sender_verified(sender,settings.resend_verified_domain):
        raise HTTPException(503,'Configure a verified Resend sender domain')
    from .delivery import reserve,finish
    reference=delivery_key or secrets.token_hex(16)
    ref,claimed=reserve('resend',reference)
    if not claimed: return
    try:
        # Resend's idempotency key also deduplicates provider-side for 24 hours.
        result=await provider_request('POST','https://api.resend.com/emails',headers={'Authorization':'Bearer '+key,'Idempotency-Key':ref.id},json={'from':f'Comten <{sender}>','to':[to],'subject':subject,'html':html,'text':text})
        if result.status_code!=200:
            finish(ref,'UNKNOWN' if result.status_code>=500 or result.status_code==429 else 'REJECTED')
            logging.getLogger('crompton').warning('Resend send rejected: HTTP %s',result.status_code)
            raise HTTPException(502,'Email provider rejected dispatch')
        try: request_id=result.json().get('id')
        except (ValueError,AttributeError):
            finish(ref,'UNKNOWN');raise HTTPException(502,'Invalid email provider response') from None
        if not request_id:
            finish(ref,'UNKNOWN');raise HTTPException(502,'Invalid email provider response')
        finish(ref,'ACCEPTED',request_id)
    except HTTPException:
        if ref.get().to_dict().get('state')=='SENDING': finish(ref,'UNKNOWN')
        raise


async def zeptomail_email(to: str, name: str, subject: str, html: str, *, text: str='', delivery_key: str|None=None):
    recipient_allowed('zeptomail',to)
    key=settings.zeptomail_token.strip();sender=settings.zeptomail_from
    # Match the original integration: the dashboard may include this prefix.
    key=re.sub(r'^Zoho-enczapikey\s+', '', key, flags=re.IGNORECASE)
    if not key or not sender: raise HTTPException(503,'ZeptoMail is not configured')
    if re.search(r'\s',key): raise HTTPException(503,'Invalid ZeptoMail credential format')
    origins={f'https://{host}{suffix}' for host in ('api.zeptomail','cpaas.zoho') for suffix in ('.com','.in','.eu','.com.au','.jp','.cn')}
    origin=settings.zeptomail_api_origin
    if origin not in origins or not sender_verified(sender,settings.zeptomail_verified_domain):
        raise HTTPException(503,'Configure a verified sender domain and regional API origin')
    from .delivery import reserve,finish
    reference=delivery_key or secrets.token_hex(16)
    ref,claimed=reserve('zeptomail',reference)
    if not claimed: return
    try:
        result=await provider_request('POST',origin+'/v1.1/email',headers={'Authorization':'Zoho-enczapikey '+key},json={'from':{'address':sender,'name':'Comten'},'to':[{'email_address':{'address':to,'name':name}}],'subject':subject,'htmlbody':html,'textbody':text,'client_reference':ref.id,'track_clicks':False,'track_opens':False})
        if result.status_code not in (200,201):
            finish(ref,'UNKNOWN' if result.status_code>=500 else 'REJECTED')
            raise HTTPException(502,'Email provider rejected dispatch')
        try: request_id=result.json().get('request_id')
        except (ValueError,AttributeError):
            finish(ref,'UNKNOWN');raise HTTPException(502,'Invalid email provider response') from None
        if not request_id:
            finish(ref,'UNKNOWN');raise HTTPException(502,'Invalid email provider response')
        finish(ref,'ACCEPTED',request_id)
    except HTTPException:
        # Retain uncertain acceptance rather than risk delivering a second OTP/email.
        if ref.get().to_dict().get('state')=='SENDING': finish(ref,'UNKNOWN')
        raise


def widget_config():
    if not settings.msg91_auth_key or not settings.msg91_widget_id:
        raise HTTPException(503,'MSG91 Widget is not configured')
    return {'authkey':settings.msg91_auth_key,'content-type':'application/json'}


async def send_msg91(phone: str):
    phone=normalize_phone(phone);recipient_allowed('msg91',phone)
    headers=widget_config()
    result=await provider_request('POST','https://api.msg91.com/api/v5/widget/sendOtp',headers=headers,json={'widgetId':settings.msg91_widget_id,'identifier':phone})
    if not provider_success(result):
        # Classify provider failures for hosted diagnostics without logging
        # recipient numbers, credentials, request IDs or raw response bodies.
        try:
            reason=str(result.json().get('message','')).lower()
        except (ValueError,AttributeError):
            reason=''
        category='PROVIDER_REJECTION'
        for marker,label in [('web requests','WIDGET_PLATFORM'),('ip','IP_RESTRICTION'),
                             ('auth','AUTHENTICATION'),('domain','DOMAIN_RESTRICTION'),
                             ('balance','BALANCE'),('credit','BALANCE'),
                             ('limit','RATE_LIMIT'),('template','TEMPLATE')]:
            if marker in reason:
                category=label;break
        logging.getLogger('crompton').warning('MSG91 send rejected: HTTP %s; category %s',result.status_code,category)
        raise HTTPException(502,'SMS widget rejected dispatch')
    request_id=result.json().get('message')
    if not isinstance(request_id,str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,150}',request_id): raise HTTPException(502,'Invalid SMS widget response')
    return request_id


async def verify_msg91(phone: str, otp: str, request_id: str):
    phone=normalize_phone(phone);recipient_allowed('msg91',phone)
    if not re.fullmatch(r'[0-9]{6}',otp) or not re.fullmatch(r'[A-Za-z0-9_-]{1,150}',str(request_id)):
        raise HTTPException(401,'Invalid or expired verification code')
    headers=widget_config()
    result=await provider_request('POST','https://api.msg91.com/api/v5/widget/verifyOtp',headers=headers,json={'widgetId':settings.msg91_widget_id,'reqId':request_id,'otp':otp})
    if result.status_code in (401,403,429) or result.status_code>=500: raise HTTPException(502,'SMS widget is temporarily unavailable')
    if not provider_success(result):
        try: reason=str(result.json().get('message','')).lower()
        except (ValueError,AttributeError): reason=''
        # The widget retires a request after expiry or its own retry cap; a
        # correct code cannot succeed then, so ask for a fresh one.
        if any(marker in reason for marker in ('expire','limit','max','exceed')):
            raise HTTPException(401,'OTP has expired. Tap Resend OTP to get a new code.')
        raise HTTPException(401,'Invalid or expired verification code')
    access_token=result.json().get('message')
    if not isinstance(access_token,str) or not 16<=len(access_token)<=8192:
        raise HTTPException(502,'Invalid SMS widget verification response')
    # Never trust decoded JWT contents or a client assertion. Ask MSG91 to
    # validate its access token, then bind the verified identifier to this user.
    proof=await provider_request('POST','https://api.msg91.com/api/v5/widget/verifyAccessToken',headers=headers,json={'access-token':access_token})
    if not provider_success(proof): raise HTTPException(401,'Invalid or expired verification session')
    identifier=proof.json().get('message')
    if not isinstance(identifier,str): raise HTTPException(502,'Invalid verified identifier response')
    try: matched=normalize_phone(identifier)==phone
    except HTTPException: matched=False
    if not matched: raise HTTPException(401,'Verified phone does not match this session')


def notify(uid: int,title: str,body: str,kind: str,key: int,**details):
    record={**details,'id':key,'userId':uid,'title':title,'message':body,'type':kind,'read':False,'pushPending':True,'createdAt':datetime.now(timezone.utc).isoformat()}
    db.collection('notifications').document(str(key)).set(record)
    # Push straight away rather than waiting for the next worker pass; the
    # record stays pushPending until delivered, so the worker still retries.
    if push_enabled():
        threading.Thread(target=deliver_push,args=(key,),daemon=True).start()
    return record


# A push older than this when first seen is history, not news - never send it
# (e.g. the backlog queued while push dispatch was switched off).
PUSH_MAX_AGE = timedelta(hours=1)
# A delivery claim older than this is from a crashed/stalled sender and may be retaken.
PUSH_CLAIM_TTL = timedelta(minutes=2)


def push_enabled():
    return settings.environment!='local' and settings.allow_real_messages and settings.fcm_dispatch_enabled


def push_recipient_allowed(uid):
    """Every active employee once registered-recipient push is on; otherwise
    only the explicit APPROVED_FCM_USER_IDS test allowlist."""
    if str(uid) in {v.strip() for v in settings.approved_fcm_user_ids.split(',') if v.strip()}:
        return True
    if not settings.fcm_registered_recipients_enabled:
        return False
    person=db.collection('employees').document(str(uid)).get().to_dict()
    return bool(person and person.get('active') and not person.get('deleted'))


def _created_at(item):
    created=item.get('createdAt')
    if isinstance(created,str):
        try: created=datetime.fromisoformat(created.replace('Z','+00:00'))
        except ValueError: return None
    return created if isinstance(created,datetime) else None


def _claim_push(ref):
    """Atomically take the right to send this push, so the immediate sender,
    the worker and other replicas never deliver the same notification twice."""
    @firestore.transactional
    def claim(tx):
        snap=ref.get(transaction=tx)
        item=snap.to_dict() if snap.exists else None
        if not item or not item.get('pushPending'): return None
        claimed=item.get('pushClaimedAt')
        now=datetime.now(timezone.utc)
        if isinstance(claimed,datetime) and now-claimed<PUSH_CLAIM_TTL: return None
        tx.update(ref,{'pushClaimedAt':now})
        return item
    return claim(db.transaction())


def _send_push(item):
    """Keep pending until at least one registered device accepts the push.

    An empty token list is not a successful delivery: registration may still
    be recovering on the phone. The existing age limit bounds these retries.
    """
    failed=False
    delivered=False
    payload={k:str(item[k]) for k in ('type','projectId','moduleId','milestonePercent') if item.get(k) is not None}
    payload['notificationId']=str(item['id'])
    android=messaging.AndroidConfig(priority='high',notification=messaging.AndroidNotification(
        channel_id='comten_notifications', tag=str(item['id']), sticky=True))
    for token in all_rows('device-tokens',[('userId',item['userId'])]):
        try:
            messaging.send(messaging.Message(token=token['token'],notification=messaging.Notification(title=item['title'],body=item['message']),data=payload,android=android))
            delivered=True
        except messaging.UnregisteredError:
            # Delete only this registered document; never another account's token.
            db.collection('device-tokens').document(str(token['id'])).delete()
        except Exception:
            failed=True
            logging.getLogger('crompton').warning('Push delivery failed; will retry')
    return failed or not delivered


def deliver_push(key):
    """Deliver one pending notification as a phone push. Never raises."""
    try:
        ref=db.collection('notifications').document(str(key))
        item=_claim_push(ref)
        if item is None: return
        created=_created_at(item)
        if created is None or datetime.now(timezone.utc)-created>PUSH_MAX_AGE:
            ref.update({'pushPending':False,'pushClaimedAt':firestore.DELETE_FIELD,'pushSkipped':'stale'})
            return
        if not push_recipient_allowed(item['userId']):
            ref.update({'pushPending':False,'pushClaimedAt':firestore.DELETE_FIELD,'pushSkipped':'not-approved'})
            return
        failed=_send_push(item)
        ref.update({'pushPending':failed,'pushClaimedAt':firestore.DELETE_FIELD})
    except Exception:
        logging.getLogger('crompton').warning('Push dispatch error; will retry')


def dispatch_pending():
    """Deliver every pending push - notifications written directly by the
    mobile app (e.g. Timesheet submitted) and retries of failed sends."""
    if not push_enabled(): return
    for item in list(all_rows('notifications',[('pushPending',True)])):
        deliver_push(item['id'])
