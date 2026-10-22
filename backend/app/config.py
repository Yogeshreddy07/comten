import os
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict, DotEnvSettingsSource


ROOT = Path(__file__).resolve().parents[2]


class ProviderDotEnvSource(DotEnvSettingsSource):
    """Later files override earlier ones, but empty provider placeholders do not."""

    def __call__(self):
        merged = {}
        files = self.env_file
        if isinstance(files, (str, Path)):
            files = (files,)
        for path in files or ():
            values = DotEnvSettingsSource(self.settings_cls, env_file=path)()
            # Accept the old application's key name without copying its secrets.
            legacy = values.pop('zeptomail_api_key', None)
            if legacy and not values.get('zeptomail_token'):
                values['zeptomail_token'] = legacy
            for key, value in values.items():
                if key.startswith(('msg91_', 'zeptomail_', 'r2_')) and not str(value or '').strip():
                    continue
                merged[key] = value
        return merged


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, env_ignore_empty=True, extra='ignore')

    @classmethod
    def settings_customise_sources(cls, settings_cls, init_settings, env_settings, dotenv_settings, file_secret_settings):
        environment = os.environ.get('ENVIRONMENT', 'local')
        files = dotenv_settings.env_file
        if files is None:
            files = (ROOT/'.env', ROOT/'.env.local', ROOT/'backend/.env',
                     ROOT/'backend/.env.local', ROOT/'.local'/f'providers.{environment}.env')
        return (init_settings, env_settings,
                ProviderDotEnvSource(settings_cls, env_file=files), file_secret_settings)
    project_id: str = 'demo-crompton-pms'
    environment: str = 'local'
    firebase_api_key: str = 'demo-key'
    web_origin: str = 'http://localhost:3000'
    r2_endpoint: str = ''
    r2_bucket: str = ''
    r2_access_key: str = ''
    r2_secret_key: str = ''
    allow_real_messages: bool = False
    recovery_hmac_key: str = ''
    msg91_auth_key: str = ''
    msg91_widget_id: str = ''
    msg91_dispatch_enabled: bool = False
    approved_sms_recipients: str = ''
    zeptomail_dispatch_enabled: bool = False
    approved_email_recipients: str = ''
    fcm_dispatch_enabled: bool = False
    approved_fcm_user_ids: str = ''
    zeptomail_api_origin: str = 'https://cpaas.zoho.in'
    zeptomail_verified_domain: str = ''
    zeptomail_token: str = ''
    zeptomail_from: str = ''


settings = Settings()
if settings.environment == 'local':
    if not settings.project_id.startswith('demo-'):
        raise RuntimeError('Local mode requires a demo project')
    os.environ.setdefault('FIRESTORE_EMULATOR_HOST', '127.0.0.1:8086')
    os.environ.setdefault('FIREBASE_AUTH_EMULATOR_HOST', '127.0.0.1:9099')
elif any(os.getenv(k) for k in ('FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST')):
    raise RuntimeError('Emulator environment forbidden outside local mode')
