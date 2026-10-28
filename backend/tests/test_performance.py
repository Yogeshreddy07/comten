import logging
import json

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from app.main import app
from app import reports


def test_report_batch_preserves_totals_sort_and_missing_employee(monkeypatch):
    calls = []
    def many(keys, fields=None):
        calls.append(list(keys))
        return {('employees', str(uid)): {'id':uid, 'employeeCode':str(uid), 'name':'Synthetic', 'role':'EMPLOYEE'}
                for _, uid in calls[-1] if uid != 99}
    monkeypatch.setattr(reports, 'get_many', many)
    logs = [{'employeeId':uid, 'billableDurationSeconds':bill, 'nonBillableDurationSeconds':non}
            for uid,bill,non in [(1,3600,1800),(2,7200,0),(1,0,1800)]]
    result = reports.employee_hours(logs, True)
    assert result[0]['billableHours'] == 1 and result[0]['nonBillableHours'] == 1
    assert len(calls) == 1 and len(calls[0]) == 2
    assert [r['hours'] for r in reports.employee_hours(logs, billable_only=True)] == [2,1]
    with pytest.raises(HTTPException) as exc:
        reports.employee_hours([{'employeeId':99}])
    assert exc.value.status_code == 404
    assert reports.employee_hours([]) == []


def test_trace_opt_in_redaction_and_error_status(monkeypatch, caplog):
    from app.config import settings
    monkeypatch.setenv('PERFORMANCE_TRACE', '1')
    monkeypatch.setattr(settings, 'environment', 'local')
    client = TestClient(app)
    with caplog.at_level(logging.INFO, logger='crompton.performance'):
        response = client.get('/api/users/me?password=never-log', headers={'X-Request-ID':'a'*32})
    assert response.status_code == 401
    assert response.headers['x-request-id'] == 'a'*32
    assert 'server-timing' in response.headers
    entries = [json.loads(r.message) for r in caplog.records if r.name == 'crompton.performance']
    assert entries[-1]['status'] == 401
    assert 'never-log' not in caplog.text
    response = client.get('/health', headers={'X-Request-ID':'private@example.invalid'})
    assert len(response.headers['x-request-id']) == 32
    monkeypatch.setattr(settings, 'environment', 'production')
    assert 'x-request-id' not in client.get('/health').headers


def test_concurrent_trace_isolation(monkeypatch, caplog):
    from concurrent.futures import ThreadPoolExecutor
    from app.config import settings
    monkeypatch.setattr(settings, 'environment', 'local')
    monkeypatch.setenv('PERFORMANCE_TRACE', '1')
    def request(value):
        with TestClient(app) as client:
            return client.get('/health', headers={'X-Request-ID':value}).headers['x-request-id']
    values = [str(i)*32 for i in range(1,5)]
    with ThreadPoolExecutor(4) as pool:
        assert list(pool.map(request, values)) == values


def test_login_pool_reused_and_closed_with_lifespan(monkeypatch):
    from app import main
    import httpx
    instances = []
    class SyntheticClient:
        def __init__(self, **kwargs):
            self.closed = False
            self.calls = 0
            instances.append(self)
        async def __aenter__(self): return self
        async def __aexit__(self, *args): self.closed = True
        async def post(self, url, **kwargs):
            self.calls += 1
            return httpx.Response(200, json={'localId':'1', 'idToken':'synthetic'})
    monkeypatch.setattr(main.httpx, 'AsyncClient', SyntheticClient)
    monkeypatch.setattr(main, 'get', lambda *args: {'id':1, 'active':True})
    with TestClient(app) as client:
        for _ in range(2):
            assert client.post('/api/auth/login', json={'employeeCode':'SYN', 'password':'synthetic'}).status_code == 200
        assert len(instances) == 1 and instances[0].calls == 2
        assert not instances[0].closed
    assert instances[0].closed
    assert app.state.auth_http_client is None
