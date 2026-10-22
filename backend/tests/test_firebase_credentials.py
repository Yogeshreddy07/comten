import json

import pytest

from app.firebase_credentials import hosting_credentials


def test_adc_is_preserved_when_json_is_absent(monkeypatch):
    monkeypatch.delenv('FIREBASE_SERVICE_ACCOUNT_JSON', raising=False)
    assert hosting_credentials('synthetic-project') is None


@pytest.mark.parametrize('raw', ['not-json-private-value', '[]',
    '{"type":"authorized_user"}',
    '{"type":"service_account","project_id":"other-project"}',
    '{"type":"service_account","project_id":"synthetic-project"}'])
def test_invalid_hosting_credentials_fail_without_echoing_secrets(monkeypatch, raw):
    monkeypatch.setenv('FIREBASE_SERVICE_ACCOUNT_JSON', raw)
    with pytest.raises(RuntimeError) as error:
        hosting_credentials('synthetic-project')
    assert raw not in str(error.value)


def test_matching_account_is_passed_to_firebase_without_disk_writes(monkeypatch):
    from app import firebase_credentials as module
    account = {'type': 'service_account', 'project_id': 'synthetic-project',
               'private_key': 'synthetic-private-key'}
    monkeypatch.setenv('FIREBASE_SERVICE_ACCOUNT_JSON', json.dumps(account))
    sentinel = object()
    def certificate(value):
        assert value == account
        return sentinel
    monkeypatch.setattr(module.credentials, 'Certificate', certificate)
    assert hosting_credentials('synthetic-project') is sentinel
