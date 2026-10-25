import firebase_admin
from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from .config import settings
from google.auth.credentials import AnonymousCredentials
from firebase_admin import credentials
from .firebase_credentials import hosting_credentials


class EmulatorCredentials(credentials.Base):
    def get_credential(self):
        return AnonymousCredentials()

if not firebase_admin._apps:
    firebase_admin.initialize_app(EmulatorCredentials() if settings.environment == 'local' else hosting_credentials(settings.project_id), options={'projectId': settings.project_id})
db = firestore.client()


def get(collection, key):
    s = db.collection(collection).document(str(key)).get()
    return s.to_dict() if s.exists else None


def get_many(keys, fields=None):
    """Fetch distinct (collection, id) references in one database round trip."""
    refs = {db.collection(collection).document(str(key)) for collection, key in keys}
    return {(s.reference.parent.id, s.id): s.to_dict() for s in db.get_all(refs, field_paths=fields)
            if s.exists} if refs else {}


def rows(collection, filters=(), limit=200, after=None):
    q = db.collection(collection)
    for entry in filters:
        key, op, value = entry if len(entry)==3 else (entry[0], '==', entry[1])
        q = q.where(filter=FieldFilter(key, op, value))
    q = q.order_by('__name__')
    if after:
        q = q.start_after({'__name__': db.collection(collection).document(after)})
    return [{'id':s.id,**s.to_dict()} for s in q.limit(min(limit, 200)).stream()]


def all_rows(collection, filters=()):
    after = None
    while True:
        batch = rows(collection, filters, 200, after)
        if not batch:
            break
        yield from batch
        if len(batch) < 200:
            break
        after = str(batch[-1]['id'])


def transact(operation):
    """Retry conflicts during reads as well as commits using fresh transactions."""
    import time,secrets
    from google.api_core.exceptions import Aborted
    from fastapi import HTTPException
    for attempt in range(5):
        try: return operation(db.transaction(max_attempts=1))
        except (Aborted,ValueError) as error:
            if not isinstance(error,Aborted) and not isinstance(error.__cause__,Aborted): raise
            if attempt==4: raise HTTPException(409,'Record changed; refresh and retry') from None
            time.sleep((secrets.randbelow(100)+25)/1000*(attempt+1))
