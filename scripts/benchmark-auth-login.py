"""Ten synthetic local login requests, including ASGI lifespan."""
import argparse
import json
import os
from pathlib import Path
import statistics
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    from app.config import settings
    if (settings.environment != 'local' or settings.project_id != 'demo-crompton-pms'
            or not all(os.getenv(k, '').startswith(('127.0.0.1:', 'localhost:'))
                       for k in ('FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST'))):
        parser.error('Requires owned local demo Auth and Firestore emulators')
    from fastapi.testclient import TestClient
    from app.main import app
    samples = []
    with TestClient(app) as client:
        for _ in range(10):
            start = time.perf_counter()
            response = client.post('/api/auth/login', json={'employeeCode':'CAP001', 'password':'SyntheticPass123!'})
            response.raise_for_status()
            samples.append(round((time.perf_counter() - start) * 1000, 2))
    result = {'scope':'10 local authenticated backend login requests with lifespan; no device/cloud',
              'median_ms':statistics.median(samples), 'p95_ms':max(samples), 'max_ms':max(samples), 'samples':samples, 'errors':0}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
