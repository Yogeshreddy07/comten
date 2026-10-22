"""Read hosting credentials without writing private key material to disk."""
import json
import os

from firebase_admin import credentials


def hosting_credentials(project_id):
    raw = os.environ.get('FIREBASE_SERVICE_ACCOUNT_JSON', '').strip()
    if not raw:
        # Existing GOOGLE_APPLICATION_CREDENTIALS / Application Default
        # Credentials continue to work for local cloud development.
        return None
    try:
        account = json.loads(raw)
    except (ValueError, TypeError):
        raise RuntimeError('FIREBASE_SERVICE_ACCOUNT_JSON must contain valid JSON') from None
    if not isinstance(account, dict) or account.get('type') != 'service_account':
        raise RuntimeError('FIREBASE_SERVICE_ACCOUNT_JSON must be a service account')
    if account.get('project_id') != project_id:
        raise RuntimeError('Firebase service account does not match PROJECT_ID')
    try:
        return credentials.Certificate(account)
    except (ValueError, TypeError, KeyError):
        raise RuntimeError('Firebase service account credentials are invalid') from None
