"""Explicit finite development probes. No dispatch occurs without a command flag.

Credentials/approved recipients are read only from ignored development config.
Never log provider responses, signed URLs, recipients, passwords or tokens.
"""
import argparse
import asyncio
import json
import os
from pathlib import Path
import sys
import time
import httpx

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--sms-send',action='store_true',help='Only after approval of the one configured number and charge')
parser.add_argument('--email-send',action='store_true',help='Only after approval of the one configured address and dispatch')
parser.add_argument('--r2-live',action='store_true',help='Finite synthetic operations in the dedicated bucket')
args=parser.parse_args()
if os.environ.get('ENVIRONMENT')!='development' or os.environ.get('PROJECT_ID')!='crompton-pms-dev-20261015': parser.error('Set ENVIRONMENT=development and PROJECT_ID=crompton-pms-dev-20261015')
os.environ.setdefault('GOOGLE_APPLICATION_CREDENTIALS',str(ROOT/'.local/development-service-account.json'))
sys.path.insert(0,str(ROOT/'backend'))
from app.config import settings
from app import messaging


async def messages():
    if args.sms_send:
        recipients=[v.strip() for v in settings.approved_sms_recipients.split(',') if v.strip()]
        if len(recipients)!=1: raise RuntimeError('Configure exactly one approved SMS test recipient')
        await messaging.send_msg91(recipients[0])
        print('SMS accepted by provider; delivery and entered-code verification are not yet certified.')
    if args.email_send:
        recipients=[v.strip() for v in settings.approved_email_recipients.split(',') if v.strip()]
        if len(recipients)!=1: raise RuntimeError('Configure exactly one approved email test recipient')
        from app.email_templates import render
        subject,html,text=render('security','Synthetic development test',message='This is the single authorized Crompton PMS development delivery test. No action is required.')
        await messaging.email(recipients[0],'Synthetic development test',subject,html,text=text)
        print('Email accepted by provider; actual inbox delivery must still be checked.')


def r2():
    from app.storage import client
    s3=client()
    if settings.r2_bucket!='crompton-pms-dev': raise RuntimeError('Dedicated development bucket required')
    logins=json.loads((ROOT/'.local/development-logins.json').read_text())
    if isinstance(logins,dict): logins=list(logins.values())
    employee=next(item for item in logins if item['employeeCode']=='EMP001')
    ids=[];checks=[];payload=b'%PDF-1.7 synthetic'
    with httpx.Client(base_url='http://127.0.0.1:8007',timeout=30) as api:
        response=api.post('/api/auth/login',json={'employeeCode':employee['employeeCode'],'password':employee['password']});response.raise_for_status()
        headers={'Authorization':'Bearer '+response.json()['data']['token']}
        body={'name':'synthetic-provider-test.pdf','size':len(payload),'contentType':'application/pdf','category':'employee_document'}
        def upload():
            result=api.post('/api/files/authorize-upload',json=body,headers=headers);result.raise_for_status();grant=result.json()['data'];ids.append(grant['id'])
            result=httpx.put(grant['url'],headers=grant['headers'],content=payload,timeout=30);result.raise_for_status()
            result=api.post('/api/files/'+grant['id']+'/complete',json={},headers=headers);result.raise_for_status()
            return grant
        try:
            grant=upload();checks.append('API authorization, direct PUT and metadata confirmation')
            duplicate=httpx.put(grant['url'],headers=grant['headers'],content=payload,timeout=30)
            assert duplicate.status_code in (409,412);checks.append('Conditional overwrite rejected')
            download=api.get('/api/files/'+grant['id']+'/download',headers=headers).json()['data']
            result=httpx.get(download['url'],headers=download['headers'],timeout=30);assert result.content==payload;checks.append('Private signed GET bytes match')
            assert api.get('/api/files/'+grant['id']+'/download').status_code==401;checks.append('Anonymous download denied')
            assert api.post('/api/files/authorize-upload',json=body|{'size':10*1024*1024+1},headers=headers).status_code==422;checks.append('Oversized authorization denied')
            assert api.post('/api/files/authorize-upload',json=body|{'contentType':'text/html'},headers=headers).status_code==422;checks.append('Wrong MIME denied')
            assert api.post('/api/files/authorize-upload',json=body|{'key':'arbitrary/path'},headers=headers).status_code==422;checks.append('Arbitrary key denied')
            # An independent one-second signature against an object this test owns.
            from app.store import get
            key=get('files',grant['id'])['key']
            short=s3.generate_presigned_url('get_object',Params={'Bucket':settings.r2_bucket,'Key':key},ExpiresIn=1)
            # Allow for the measured several-second development-host clock skew.
            time.sleep(20)
            assert httpx.get(short,timeout=30).status_code==403;checks.append('Expired capability rejected')
            origin='http://127.0.0.1:3008'
            cors=httpx.options(grant['url'],headers={'Origin':origin,'Access-Control-Request-Method':'PUT','Access-Control-Request-Headers':'content-type,if-none-match'},timeout=30)
            assert cors.status_code in (200,204) and cors.headers.get('access-control-allow-origin')==origin
            checks.append('Authorized development CORS preflight headers')
            blocked=httpx.options(grant['url'],headers={'Origin':'https://unapproved.invalid','Access-Control-Request-Method':'PUT'},timeout=30)
            assert blocked.headers.get('access-control-allow-origin') not in ('*','https://unapproved.invalid')
            checks.append('Unapproved origin has no CORS grant')
        except Exception:
            # Safe progress only: never print exceptions containing signed URLs.
            print(json.dumps({'provider':'LIVE_R2','completed_checks':checks,'passed':False}))
            raise
        finally:
            from app.store import get
            for file_id in ids:
                row=get('files',file_id)
                if row:
                    api.delete('/api/files/'+file_id,headers=headers).raise_for_status()
                    try: s3.head_object(Bucket=settings.r2_bucket,Key=row['key'])
                    except s3.exceptions.ClientError as error:
                        if error.response['ResponseMetadata']['HTTPStatusCode']!=404: raise
                    else: raise RuntimeError('Synthetic object cleanup failed')
            print('Synthetic R2 object cleanup verified; capability tombstones retained for scheduled cleanup.')
    print(json.dumps({'provider':'LIVE_R2','checks':checks,'passed':True}))


try:
    if not any((args.sms_send,args.email_send,args.r2_live)):
        print(json.dumps({'msg91Configured':bool(settings.msg91_auth_key and settings.msg91_widget_id),'emailProvider':settings.email_provider,'resendConfigured':bool(settings.resend_api_key and settings.resend_from and settings.resend_verified_domain),'zeptomailConfigured':bool(settings.zeptomail_token and settings.zeptomail_from and settings.zeptomail_verified_domain),'r2Configured':bool(settings.r2_access_key and settings.r2_secret_key and settings.r2_endpoint),'dispatchEnabled':settings.allow_real_messages}))
    else:
        asyncio.run(messages())
        if args.r2_live: r2()
except Exception:
    print('Provider probe failed; check approved development configuration and sanitized server delivery state. No provider response or credentials are displayed.',file=sys.stderr)
    sys.exit(1)
