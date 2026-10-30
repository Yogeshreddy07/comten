"""Code casing is checked before contacting password authentication."""
import asyncio
from types import SimpleNamespace
import httpx
import pytest
from fastapi import HTTPException
from app.main import login


@pytest.mark.parametrize('code', ['emp012', 'eMp012', 'pc001', 'tL003'])
def test_lowercase_employee_codes_are_rejected_before_authentication(code):
    class NoAuthentication:
        async def post(self, *args, **kwargs):
            pytest.fail('Lowercase codes must not reach Firebase authentication')
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(auth_http_client=NoAuthentication())))
    with pytest.raises(HTTPException) as failure:
        asyncio.run(login({'employeeCode': code, 'password': 'MixedCase123!'}, request))
    assert failure.value.status_code == 401
    assert failure.value.detail == 'Employee code must be uppercase.'


def test_uppercase_code_reaches_password_authentication_without_changing_password():
    calls = []
    class Authentication:
        async def post(self, *args, **kwargs):
            calls.append(kwargs['json'])
            return httpx.Response(400, json={'error': {'message': 'INVALID_PASSWORD'}})
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(auth_http_client=Authentication())))
    with pytest.raises(HTTPException):
        asyncio.run(login({'employeeCode': 'EMP012', 'password': 'MixedCase123!'}, request))
    assert len(calls) == 1
    assert calls[0]['email'] == 'emp012@accounts.crompton.invalid'
    assert calls[0]['password'] == 'MixedCase123!'
