# Project submission and lifecycle performance — 25 October 2026

## Findings and fixes

The activity list included records with `active=false`, including previously
deactivated activities. The create-project picker offered these records, but
the backend correctly rejected their IDs with “Selection is unavailable”.
The transport, picker view model and backend activity listing now exclude
inactive activities. Authoritative submission validation still rejects stale
selections and identifies whether the unavailable selection is an employee or
an activity.

The synchronous roster reconciliation queried modules once per employee,
repeated parent-project reads, and wrote employee permissions individually.
It now shares module queries in groups of 30 employee IDs, batches parent and
employee reads, and commits roster updates together in a retryable transaction.
Reading only required validation/summary fields also avoids transferring every
employee's full peer roster. Permission-version increments, assignment removal,
access through other projects, parent activation requirements and billing
approval rules remain enforced.

Other changes in the audited paths:

- Batch selection validation and creation-response enrichment; avoid the extra
  empty pagination request for a partial final page.
- Forward privileged project/module writes directly to backend authorization,
  avoiding a redundant client profile request. Existing Firebase token and
  backend account/revocation checks remain in place.
- Reuse HTTP connections for backend requests.
- Update project/module state from confirmed mutation responses. Project
  deactivation no longer waits for a full list fetch; a billing approval request
  keeps the project active. Module activation immediately restores its returned
  status.
- Skip full member/activity hydration for mobile list summaries; fetch full
  module-detail references concurrently and deduplicate the leader/member read.
- Reuse full module details already returned by project creation for the
  success screen, with compatibility fallback for older servers.
- Avoid rebuilding permissions when only a module's work stage changes.

## Measured scope

These are finite local TestClient measurements with actual Firebase Auth and
Firestore emulators, including authenticated endpoint processing. They exclude
phone rendering, internet transit, hosted Firebase latency and backend cold
starts. They are **not a hosted one-second guarantee**.

| Action | 10 employees, 10 runs: median / max | 100 employees, 5 runs: median / max |
|---|---:|---:|
| Create project and initial module | 86 / 96 ms | 837 / 916 ms |
| Deactivate project and modules | 72 / 121 ms | 426 / 524 ms |
| Activate project | 36 / 63 ms | 68 / 72 ms |
| Activate module | 66 / 109 ms | 638 / 765 ms |

Use an isolated, seeded `demo-crompton-pms` emulator. The benchmark refuses
nonlocal environments and nonloopback emulator addresses, cleans up its
synthetic records, and sends no email/SMS:

```powershell
$env:ENVIRONMENT='local'
$env:PROJECT_ID='demo-crompton-pms'
$env:FIREBASE_API_KEY='demo-key'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8186'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9198'
$env:ALLOW_REAL_MESSAGES='false'
.\.venv\Scripts\python.exe scripts/seed.py
.\.venv\Scripts\python.exe scripts/benchmark-project-lifecycle.py --members 100 --runs 5
```

Raw local results are in `.local/project-performance-benchmark.json` and
`.local/project-performance-benchmark-100.json`.

## Verification and rollout

The final clean, seeded backend run passed all **114 tests**. All **five new
Flutter regressions passed**, and `git diff --check` passed. Backend test output
is saved in `.local/project-performance-backend-tests.log`.

New backend regressions cover retired/stale activity selections, cascading
deactivation, preserved permissions through another project, activation order
and billing approval requests. New Flutter regressions cover confirmed-state
updates without list refetches, pending approval, restored module status,
inactive activity filtering and creation-response reuse.

The full Flutter run has 45 passing tests and four lock-screen pixel comparison
failures. The lock-screen source had pre-existing local edits and was not
changed by this fix. Flutter analysis is clean.

Both the backend changes and a rebuilt mobile application must be rolled out
before installed-app timings change. This work does not deploy the hosted
service or replace installed APKs. Verify warm/cold hosted timings and device
rendering before accepting an end-to-end one-second target. Shared transport
and project/module paths were audited; other application features have not
been certified to complete within one second.
