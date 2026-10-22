"""No network provider dispatch: adapters are exercised with synthetic responses."""
import asyncio
import httpx
import pytest
from fastapi import HTTPException
from app import messaging as adapters


@pytest.fixture
def configured(monkeypatch):
    for key,value in {'allow_real_messages':True,'msg91_auth_key':'synthetic','msg91_widget_id':'synthetic-widget','zeptomail_token':'synthetic','zeptomail_from':'sender@example.invalid','msg91_dispatch_enabled':True,'approved_sms_recipients':'919000000000','zeptomail_dispatch_enabled':True,'approved_email_recipients':'test@example.invalid','zeptomail_verified_domain':'example.invalid'}.items():
        monkeypatch.setattr(adapters.settings,key,value)


def test_provider_dispatch_disabled_without_network(monkeypatch):
    monkeypatch.setattr(adapters.settings,'allow_real_messages',False)
    for operation in (adapters.email('synthetic@example.invalid','Synthetic','Test','<p>Test</p>'),adapters.send_msg91('919000000000'),adapters.verify_msg91('919000000000','000000','synthetic-request')):
        with pytest.raises(HTTPException) as error: asyncio.run(operation)
        assert error.value.status_code==503


@pytest.mark.parametrize('status,payload,expected',[(200,{'type':'success','message':'synthetic-request'},None),(400,{'type':'error'},502),(503,{},502),(200,None,502)])
def test_sms_send_contract(configured,monkeypatch,status,payload,expected):
    async def fake(method,url,**kw):
        assert method=='POST' and kw['json']=={'widgetId':'synthetic-widget','identifier':'919000000000'}
        return httpx.Response(status,json=payload) if payload is not None else httpx.Response(status,text='bad-json')
    monkeypatch.setattr(adapters,'provider_request',fake)
    if expected:
        with pytest.raises(HTTPException) as error: asyncio.run(adapters.send_msg91('919000000000'))
        assert error.value.status_code==expected
    else: asyncio.run(adapters.send_msg91('919000000000'))


def test_otp_verification_and_mail_contract(configured,monkeypatch):
    calls=[]
    async def fake(method,url,**kw):
        calls.append((method,url,kw))
        return httpx.Response(200,json={'type':'success','message':'919000000000' if url.endswith('verifyAccessToken') else 'synthetic-access-token-never-logged','request_id':'synthetic-request'})
    monkeypatch.setattr(adapters,'provider_request',fake)
    asyncio.run(adapters.verify_msg91('919000000000','000000','synthetic-request'))
    asyncio.run(adapters.email('test@example.invalid','Synthetic','Test','<p>Synthetic</p>'))
    assert calls[0][2]['json']=={'widgetId':'synthetic-widget','reqId':'synthetic-request','otp':'000000'}
    assert calls[1][1].endswith('/widget/verifyAccessToken')
    assert calls[2][2]['json']['to'][0]['email_address']['address']=='test@example.invalid'
    async def reject(*a,**kw): return httpx.Response(200,json={'type':'error'})
    monkeypatch.setattr(adapters,'provider_request',reject)
    with pytest.raises(HTTPException) as error: asyncio.run(adapters.verify_msg91('919000000000','999999','synthetic-request'))
    assert error.value.status_code==401


def test_network_timeout_is_sanitized(configured,monkeypatch):
    async def fail(*a,**kw): raise httpx.ConnectTimeout('secret-provider-url')
    monkeypatch.setattr(httpx.AsyncClient,'request',fail)
    with pytest.raises(HTTPException) as error: asyncio.run(adapters.send_msg91('919000000000'))
    assert error.value.status_code==502 and 'secret' not in error.value.detail


@pytest.mark.parametrize('configured_key',['synthetic-mail-key','  Zoho-enczapikey synthetic-mail-key  '])
def test_mail_dashboard_prefix_is_applied_exactly_once(configured,monkeypatch,configured_key):
    monkeypatch.setattr(adapters.settings,'zeptomail_token',configured_key)
    async def accepted(method,url,**kwargs):
        assert kwargs['headers']['Authorization']=='Zoho-enczapikey synthetic-mail-key'
        return httpx.Response(201,json={'request_id':'synthetic-prefix-test'})
    monkeypatch.setattr(adapters,'provider_request',accepted)
    asyncio.run(adapters.email('test@example.invalid','Synthetic','Test','<p>Test</p>'))


def test_fcm_retry_and_deep_link_payload(configured,monkeypatch):
    monkeypatch.setattr(adapters.settings,'environment','development')
    monkeypatch.setattr(adapters.settings,'fcm_dispatch_enabled',True)
    monkeypatch.setattr(adapters.settings,'approved_fcm_user_ids','4')
    notifications=[{'id':1,'userId':4,'type':'TIMESHEET_APPROVED','title':'Synthetic','message':'Test','moduleId':101,'projectId':100}]
    monkeypatch.setattr(adapters,'all_rows',lambda name,*args: notifications if name=='notifications' else [{'id':'token-doc','token':'synthetic'}])
    updates=[]
    class Document:
        def update(self,values): updates.append(values)
    class Collection:
        def document(self,key): return Document()
    class Database:
        def collection(self,name): return Collection()
    monkeypatch.setattr(adapters,'db',Database())
    def unavailable(message): raise RuntimeError('provider outage')
    monkeypatch.setattr(adapters.messaging,'send',unavailable)
    adapters.dispatch_pending()
    assert updates[-1]=={'pushPending':True}
    sent=[]
    monkeypatch.setattr(adapters.messaging,'send',lambda message:sent.append(message))
    adapters.dispatch_pending()
    assert updates[-1]=={'pushPending':False}
    assert sent[0].data['moduleId']=='101' and sent[0].data['notificationId']=='1'


@pytest.mark.parametrize('raw,expected',[('+91 90000-00000','919000000000'),('9000000000','919000000000'),('+14155552671','14155552671')])
def test_phone_normalization(raw,expected):
    assert adapters.normalize_phone(raw)==expected

@pytest.mark.parametrize('raw',['not-a-phone','+910000000000','+0012345678','+919000000000?otp=1'])
def test_phone_rejects_invalid(raw):
    with pytest.raises(HTTPException): adapters.normalize_phone(raw)


def test_unapproved_recipient_never_calls_network(configured,monkeypatch):
    async def forbidden(*args,**kwargs): pytest.fail('Unapproved recipient reached provider')
    monkeypatch.setattr(adapters,'provider_request',forbidden)
    with pytest.raises(HTTPException) as error: asyncio.run(adapters.send_msg91('919999999999'))
    assert error.value.status_code==503


@pytest.mark.parametrize('kind',['invitation','activation','recovery','security','approval'])
def test_email_templates_escape_and_plain_text(kind):
    from app.email_templates import render
    subject,html,text=render(kind,'<script>synthetic</script>',otp='000000',code='SYN001',message='<img src=x>')
    assert '<script>' not in html and '&lt;script&gt;' in html
    assert '<img src=x>' not in html and 'Comten' in text and subject


def test_email_claim_prevents_duplicate_and_uncertain_retry(configured,monkeypatch):
    import uuid
    from app.store import db
    from app.delivery import reserve
    sent=[]
    async def fake(*a,**kw):
        sent.append(kw)
        return httpx.Response(201,json={'request_id':'synthetic-opaque-id'})
    monkeypatch.setattr(adapters,'provider_request',fake)
    key=uuid.uuid4().hex
    for _ in range(2): asyncio.run(adapters.email('test@example.invalid','Synthetic','Test','<p>Test</p>',text='Test',delivery_key=key))
    assert len(sent)==1
    uncertain=uuid.uuid4().hex
    ref,claimed=reserve('zeptomail',uncertain)
    assert claimed and ref.get().to_dict()['state']=='SENDING'
    ref.update({'state':'UNKNOWN'})
    with pytest.raises(HTTPException) as error: reserve('zeptomail',uncertain)
    assert error.value.status_code==409
    assert set(ref.get().to_dict()) <= {'id','channel','state','createdAt','expires'}


def test_email_invalid_domain_or_recipient_never_sends(configured,monkeypatch):
    async def forbidden(*a,**kw): pytest.fail('Invalid sender reached provider')
    monkeypatch.setattr(adapters,'provider_request',forbidden)
    monkeypatch.setattr(adapters.settings,'zeptomail_verified_domain','different.invalid')
    with pytest.raises(HTTPException) as error: asyncio.run(adapters.email('test@example.invalid','Test','Test','<p>Test</p>'))
    assert error.value.status_code==503


def test_email_read_timeout_is_not_retried_and_claim_is_retained(configured,monkeypatch):
    import uuid
    from app.delivery import reserve
    count=[];key=uuid.uuid4().hex
    async def timeout(*a,**kw): count.append(1);raise httpx.ReadTimeout('private-provider-data')
    monkeypatch.setattr(httpx.AsyncClient,'request',timeout)
    with pytest.raises(HTTPException) as error:
        asyncio.run(adapters.email('test@example.invalid','Synthetic','Test','<p>Test</p>',delivery_key=key))
    assert error.value.status_code==502 and 'private' not in error.value.detail and len(count)==1
    with pytest.raises(HTTPException) as error: reserve('zeptomail',key)
    assert error.value.status_code==409


@pytest.mark.parametrize('verified',['919999999999','not-a-phone',{'identifier':'919000000000'}])
def test_widget_proof_must_match_the_enrolled_phone(configured,monkeypatch,verified):
    calls=[]
    async def fake(method,url,**kw):
        assert method=='POST' and 'authkey' in kw['headers']
        calls.append(url)
        return httpx.Response(200,json={'type':'success','message':verified if url.endswith('verifyAccessToken') else 'synthetic-access-token-never-logged'})
    monkeypatch.setattr(adapters,'provider_request',fake)
    with pytest.raises(HTTPException) as error: asyncio.run(adapters.verify_msg91('919000000000','000000','synthetic-request'))
    assert error.value.status_code in (401,502) and len(calls)==2


def test_widget_rejects_missing_request_id_and_legacy_template_config(configured,monkeypatch):
    async def fake(*a,**kw): return httpx.Response(200,json={'type':'success'})
    monkeypatch.setattr(adapters,'provider_request',fake)
    with pytest.raises(HTTPException) as error: asyncio.run(adapters.send_msg91('919000000000'))
    assert error.value.status_code==502
    monkeypatch.setattr(adapters.settings,'msg91_widget_id','')
    with pytest.raises(HTTPException) as error: asyncio.run(adapters.send_msg91('919000000000'))
    assert error.value.status_code==503
