"""Opt-in local/development spans. Labels never include bodies, IDs or URLs."""
from contextvars import ContextVar
from contextlib import contextmanager
from functools import wraps
import json
import logging
import os
import re
import threading
import time
import uuid

_trace = ContextVar('performance_trace', default=None)
log = logging.getLogger('crompton.performance')


def enabled():
    from .config import settings
    return settings.environment in ('local', 'development') and os.getenv('PERFORMANCE_TRACE') == '1'


@contextmanager
def span(label):
    trace = _trace.get()
    if trace is None:
        yield
        return
    start = time.perf_counter()
    try:
        yield
    finally:
        with trace['lock']:
            value = trace['spans'].setdefault(label, {'calls': 0, 'ms': 0})
            value['calls'] += 1
            value['ms'] += (time.perf_counter() - start) * 1000


def count(label, amount):
    trace = _trace.get()
    if trace is not None:
        with trace['lock']:
            trace['counts'][label] = trace['counts'].get(label, 0) + amount


def install_firestore_spans():
    """Time consumed streams, not just generator construction; never wrap twice."""
    if not enabled():
        return
    from google.cloud.firestore_v1.document import DocumentReference
    from google.cloud.firestore_v1.query import Query
    from google.cloud.firestore_v1.client import Client
    from google.cloud.firestore_v1.batch import WriteBatch
    from google.cloud.firestore_v1.transaction import Transaction
    for cls, names in ((DocumentReference, ('get', 'set', 'create', 'update', 'delete')),
                       (Query, ('stream',)), (Client, ('get_all',)),
                       (WriteBatch, ('commit',)), (Transaction, ('_commit',))):
        for name in names:
            original = getattr(cls, name)
            if getattr(original, '_performance_wrapped', False):
                continue
            def wrap(fn, label, streamed):
                if streamed:
                    @wraps(fn)
                    def measured(*args, **kwargs):
                        with span(label):
                            for item in fn(*args, **kwargs):
                                count('firestore.documents_returned', 1)
                                yield item
                else:
                    @wraps(fn)
                    def measured(*args, **kwargs):
                        with span(label):
                            result = fn(*args, **kwargs)
                            if label.endswith('.get'):
                                count('firestore.document_gets', 1)
                            elif label.endswith('commit'):
                                count('firestore.committed_writes', len(result))
                            return result
                measured._performance_wrapped = True
                return measured
            setattr(cls, name, wrap(original, 'firestore.' + cls.__name__ + '.' + name,
                                    name in ('stream', 'get_all')))


class PerformanceMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http' or not enabled():
            return await self.app(scope, receive, send)
        supplied = dict(scope.get('headers', [])).get(b'x-request-id', b'').decode('ascii', errors='ignore')
        request_id = supplied if re.fullmatch(r'[a-f0-9]{32}', supplied) else uuid.uuid4().hex
        trace = {'lock': threading.Lock(), 'spans': {}, 'counts': {}}
        token = _trace.set(trace)
        start = time.perf_counter()
        status = 500
        async def measured_send(message):
            nonlocal status
            if message['type'] == 'http.response.start':
                status = message['status']
                message['headers'] = list(message.get('headers', [])) + [
                    (b'x-request-id', request_id.encode()),
                    (b'server-timing', f'app;dur={(time.perf_counter()-start)*1000:.2f}'.encode())]
            await send(message)
        try:
            await self.app(scope, receive, measured_send)
        finally:
            # Route template only; actual path/query can contain personal data.
            route = getattr(scope.get('route'), 'path', 'unmatched')
            # Only fixed, known workflow names may refine generic routes.
            allowed = {'employees','projects','modules','activities','attendance','work-logs','notifications',
                       'module-change-requests','project-deactivation-requests','billing-status-change-requests',
                       'delay-requests','activate','deactivate','delete','approve','reject','work-stage'}
            for key in ('collection', 'action'):
                value = scope.get('path_params', {}).get(key)
                if value in allowed:
                    route = route.replace('{' + key + '}', value)
            log.info(json.dumps({'request_id': request_id, 'route': route, 'method': scope['method'], 'status': status,
                                'total_ms': round((time.perf_counter()-start)*1000, 2), 'spans': trace['spans'], 'counts': trace['counts']}))
            _trace.reset(token)
