from app.config import Settings


def test_empty_provider_placeholders_preserve_saved_keys(tmp_path, monkeypatch):
    for key in ('MSG91_AUTH_KEY', 'ZEPTOMAIL_TOKEN', 'ZEPTOMAIL_API_KEY'):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv('MSG91_AUTH_KEY', '')
    saved = tmp_path/'saved.env'
    placeholders = tmp_path/'providers.env'
    saved.write_text('MSG91_AUTH_KEY=synthetic-key\nZEPTOMAIL_API_KEY=synthetic-mail\nR2_ACCESS_KEY=synthetic-r2\n')
    placeholders.write_text('MSG91_AUTH_KEY=\nZEPTOMAIL_TOKEN=\nR2_ACCESS_KEY=\nALLOW_REAL_MESSAGES=false\n')
    config = Settings(_env_file=(saved, placeholders))
    assert config.msg91_auth_key == 'synthetic-key'
    assert config.zeptomail_token == 'synthetic-mail'
    assert config.r2_access_key == 'synthetic-r2'
    assert not config.allow_real_messages


def test_process_dispatch_guard_wins_over_files(tmp_path, monkeypatch):
    saved = tmp_path/'saved.env'
    saved.write_text('ALLOW_REAL_MESSAGES=true\nMSG91_DISPATCH_ENABLED=true\nMSG91_AUTH_KEY=synthetic-old\n')
    monkeypatch.setenv('ALLOW_REAL_MESSAGES', 'false')
    monkeypatch.setenv('MSG91_DISPATCH_ENABLED', 'false')
    monkeypatch.setenv('MSG91_AUTH_KEY', 'synthetic-process')
    config = Settings(_env_file=(saved,))
    assert not config.allow_real_messages and not config.msg91_dispatch_enabled
    assert config.msg91_auth_key == 'synthetic-process'


def test_local_overrides_and_development_file_are_loaded(tmp_path, monkeypatch):
    import app.config as module
    monkeypatch.setattr(module, 'ROOT', tmp_path)
    monkeypatch.setenv('ENVIRONMENT', 'development')
    monkeypatch.delenv('MSG91_AUTH_KEY', raising=False)
    (tmp_path/'.local').mkdir()
    (tmp_path/'backend').mkdir()
    (tmp_path/'.env').write_text('MSG91_AUTH_KEY=synthetic-root\n')
    (tmp_path/'.env.local').write_text('MSG91_AUTH_KEY=synthetic-local\n')
    (tmp_path/'backend/.env.local').write_text('MSG91_AUTH_KEY=synthetic-backend\n')
    (tmp_path/'.local/providers.development.env').write_text('MSG91_AUTH_KEY=\nMSG91_WIDGET_ID=synthetic-widget\n')
    config = Settings()
    assert config.msg91_auth_key == 'synthetic-backend'
    assert config.msg91_widget_id == 'synthetic-widget'
