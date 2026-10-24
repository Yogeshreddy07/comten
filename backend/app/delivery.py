"""Durable send claims prevent duplicate dispatch after concurrent requests/timeouts.

Only delivery metadata is retained; no OTP, message body, token or raw recipient.
UNKNOWN means acceptance is uncertain and requires reconciliation, never auto retry.
"""
import hashlib
import time
from firebase_admin import firestore
from fastapi import HTTPException
from .store import db,transact


def reserve(channel, key):
    doc=hashlib.sha256((channel+':'+key).encode()).hexdigest()
    ref=db.collection('provider-deliveries').document(doc)
    @firestore.transactional
    def claim(tx):
        old=ref.get(transaction=tx).to_dict()
        if old:
            if old['state']=='ACCEPTED': return False
            raise HTTPException(409,'Delivery is already claimed; check provider status before retrying')
        tx.create(ref,{'id':doc,'channel':channel,'state':'SENDING','createdAt':time.time(),'expires':time.time()+30*86400})
        return True
    return ref,transact(claim)


def finish(ref,state,request_id=None):
    # Provider response strings can contain addresses/body content. Persist only opaque IDs.
    import re
    values={'state':state,'updatedAt':time.time()}
    if isinstance(request_id,str) and re.fullmatch(r'[A-Za-z0-9_.-]{1,150}',request_id): values['providerRequestId']=request_id
    ref.update(values)


def event(uid, kind, key, **values):
    from google.api_core.exceptions import GoogleAPICallError
    import logging
    try: return queue_event(uid,kind,key,**values)
    except GoogleAPICallError:
        # Optional email never reverses or disguises a committed business action.
        logging.getLogger(__name__).warning('Transactional email queue unavailable')


def queue_event(uid, kind, key, **values):
    from .config import settings
    from .store import get
    from .messaging import recipient_allowed,email_provider
    try: provider=email_provider()
    except HTTPException: return
    if not settings.allow_real_messages or not getattr(settings,provider+'_dispatch_enabled'): return
    person=get('employees',uid)
    if not person or not person.get('active') or not person.get('email'): return
    try: recipient_allowed(provider,person['email'])
    except HTTPException: return
    doc=hashlib.sha256(key.encode()).hexdigest()
    from google.api_core.exceptions import AlreadyExists
    try:
        db.collection('email-outbox').document(doc).create({'id':doc,'userId':uid,'recipientVersion':hashlib.sha256(person['email'].lower().encode()).hexdigest(),'kind':kind,'values':values,'state':'PENDING','createdAt':time.time(),'expires':time.time()+86400})
    except AlreadyExists: pass


async def dispatch_emails():
    from .store import all_rows,get
    from .email_templates import render
    from .messaging import email
    for row in all_rows('email-outbox',[('state','PENDING')]):
        ref=db.collection('email-outbox').document(row['id'])
        person=get('employees',row['userId'])
        if not person or not person.get('active') or row['expires']<time.time() or hashlib.sha256(person.get('email','').lower().encode()).hexdigest()!=row['recipientVersion']:
            ref.update({'state':'CANCELLED'});continue
        try:
            subject,html,text=render(row['kind'],person['name'],**row['values'])
            await email(person['email'],person['name'],subject,html,text=text,delivery_key=row['id'])
        except HTTPException as error:
            if error.status_code==503: continue
            ref.update({'state':'REVIEW_REQUIRED'});continue
        ref.update({'state':'ACCEPTED'})


async def email_worker():
    """Drain non-OTP notifications in the API service; provider claims deduplicate replicas."""
    import asyncio
    import logging
    while True:
        try:
            await asyncio.to_thread(lambda: asyncio.run(dispatch_emails()))
        except Exception:
            logging.getLogger('crompton').warning('Transactional email worker will retry')
        await asyncio.sleep(30)
