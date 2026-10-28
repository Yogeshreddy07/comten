# Crompton PMS performance audit — 28 October 2026

## 1. Executive summary

Audited local source at `0080174`, the two 25 October performance/bugfix notes,
the lifecycle benchmark, Git history, Flutter transport/repositories/ViewModels,
FastAPI handlers, authorization, roster reconciliation, reports and file flows.
The working tree was clean before this investigation.

Two measured local improvements were implemented:

* 100-employee report enrichment: median **205.1 → 32.0 ms** (84% lower),
  replacing 100 individual document requests with one batch request.
* Backend login: median **218.5 → 8.1 ms** (96% lower), reusing a lifespan-owned
  HTTP client rather than constructing a TLS/connection pool per request.

These are component/emulator measurements, **not measured improvements to
five-second physical-device submissions**. The reported end-to-end delay has
not been reproduced on an affected phone. Much of the mobile application uses
Firestore directly and never passes through Railway.

Added opt-in monotonic client/server tracing to locate the remaining delay.
No deployment, infrastructure purchase, production writes or real message
dispatch was performed. Read-only hosted checks were limited to health and
Firestore database metadata.

## 2. Confirmed causes and evidence limits

### Measured locally

`reports.employee_hours` fetched a current employee profile sequentially for
each distinct employee. Ten real local Firestore-emulator runs with 100
synthetic employees measured the improvement above. Profile selection remains
authoritative; totals, stable sorting, missing-employee errors and billable
filtering are preserved. Document volume remains 100; RPC count falls to one.

Backend password login allocated a new `httpx.AsyncClient` on every request.
Ten authenticated requests through TestClient with ASGI lifespan measured the
improvement above. A pool now belongs to the application's event loop and
closes at shutdown. Clients without lifespan retain the previous fallback.
This moves one-time client setup to backend startup; cold-start end-to-end
benefit has not been measured. Password verification, active-account checks
and Firebase token issuance are unchanged.

### Confirmed code paths; device contribution unmeasured

* `FirebaseTransport.profile()` forces a server profile read, binds encrypted
  storage and writes profile/cache lease metadata before most operations,
  including cache hits and unsupported operations that subsequently use HTTP.
  Thus a cached list is not a zero-network screen. Retain these authorization
  and permission-version checks until a safe invalidation design is measured.
* Dashboard routing waits up to three seconds for unread-count retrieval.
  That implementation reads all notification pages and counts locally; it
  can subsequently fetch the same list for the unread gate. Existing routing
  semantics require that gate, so they were preserved.
* Team attendance reads parent projects serially and then employee/attendance
  pairs serially. Duplicate parents are reread. This is a strong candidate for
  bounded concurrency and per-operation deduplication after device capture.
* Project-list decoration queries modules per project and leader data per
  module. List hydration is lighter than before but still has N+1 operations.
* Employee identity validation and its transaction scan the employee directory.
  This preserves uniqueness across legacy records but scales with directory
  size and creates contention around the identity lock. Replacing it requires
  an indexed uniqueness-record migration, not removal of validation.
* Reports still reread project/module/work-log graphs per project and employee
  profiles across separate modules. Attendance reports reread attendance for
  each trend month. Only the measured employee enrichment was changed.
* Several list ViewModels replace content with loading states on refresh.
  Timesheets already preserve content and guard against stale completions;
  other lists do not consistently have those protections.

No evidence establishes a single universal cause of the reported five seconds.
Do not attribute it to cold hosting, geography, UI rebuilds or Firestore alone.

## 3. Existing optimizations and rollout audit

Present in current source (introduced by the 25 October history, including
`2e24142` and `658dfab`):

* Grouped roster module queries (30 IDs), batched parent/employee reads,
  projected fields and retryable transactional permission writes.
* Batched project selection validation and creation-response enrichment;
  skip the extra pagination request after a partial final page.
* Persistent Flutter HTTP client; privileged lifecycle writes avoid a redundant
  client profile read and still use backend authorization/revocation checks.
* Confirmed mutation responses update project/module lists and creation screens
  without unnecessary full list reads; pending billing approval keeps active state.
* Module details fetch references concurrently and deduplicate within a module;
  summaries omit full member/activity hydration.
* Work-stage-only changes avoid roster rebuilding. Completed-module restrictions
  and repeat Captain approval request checks remain present.
* Timesheet confirmation reuses the committed row; revision guards prevent
  older fetches erasing it; refresh retains content. Multi-module pending entries
  and cumulative attendance limits have regression coverage.
* Employee Management restricts staff lists without changing Captain PC management.
* Existing button loading flags disable actions; GET alone has one network retry.
  No new mutation retry was added. Timesheets use a deterministic request-derived
  document ID and transactional daily accounting; project codes and pending
  approval locks provide their existing duplicate protections.

**Railway:** health is reachable and reports the development Firebase project.
The response contains no commit/build identity. Historical local deployment
notes prove older revisions were deployed, not the current deployment revision.
No Railway CLI/account metrics access was available through the configured
tools/settings. Inclusion of the 25 October fixes in the current deployment is
**unverified**.

**Android:** `adb devices` returned no devices. A local 25 October APK manifest
exists for version 1.0.5, versionCode 6; it contains no source revision and marks
device testing/deployment separately. An APK on disk does not prove installation
on any affected phone. Installed binary/version and inclusion of fixes are
**unverified**. No APK was rebuilt or installed during this audit.

## 4. Instrumentation and latency breakdown

Backend: `PERFORMANCE_TRACE=1` enables tracing only in `local` or `development`.
Production ignores the flag. `perf_counter` measures elapsed time. An ASGI
middleware propagates a validated opaque 32-hex `X-Request-ID`, returns
`Server-Timing`/`X-Request-ID`, and logs route templates, status, total time,
stage aggregates and counters. Known collection/action names refine generic
routes; record IDs, query strings, headers and bodies are not logged.

Development-only wrappers measure consumed Firestore query/batch-read streams,
document gets/writes, batch commits and transaction commits. Additional spans
measure revoked-token verification, backend Firebase password authentication
and final JSON encoding. Context variables propagate into FastAPI worker
threads; concurrent requests have isolated accumulators. Wrapping is idempotent.

Counters distinguish returned documents, document gets and committed write
operations. They are **diagnostic operation counts, not Firestore billed reads**:
missing documents, rule evaluation, transaction retry reads and SDK internals
can differ. Nested spans overlap; do not sum them as independent latency.
`Server-Timing` ends at response headers; logged total ends after body send.
JSON encoding excludes FastAPI's earlier object normalization.

Flutter: run a debug/profile build with `--dart-define=PERFORMANCE_TRACE=true`.
Release builds disable the tracing flag. Stopwatch/Zone correlation connects
shared button taps, API dispatch, token retrieval, Firebase transport/profile/
pagination/attendance/timesheet operations, HTTP headers/body completion,
file upload/download, ViewModel listener dispatch/next frame, and navigation
first frame/transition completion. API and network errors retain end markers.
HTTP requests carry the interaction correlation ID; native Firebase requests
are correlated in client logs and cannot carry that header.

Frame markers do **not** prove that a spinner, success message or loaded list
was painted. Button coverage is the shared AppButton/AuthButton; other tap
controls need entry spans during device investigation. Widget build/raster
cost, DNS/TCP/TLS separation, every direct document read, all repository decoding,
all third-party provider calls and a single authoritative “user sees success”
end marker are **not fully instrumented**. Use Flutter DevTools/network profiling
and targeted stage spans for these gaps. No claim that Phase 2 is exhaustive.

### Workflow audit matrix

The following describes the real critical path. “Unmeasured” means no trustworthy
physical-device before/after timing, not zero latency. Backend fixture traces
are available separately for diagnosis and cannot substitute for mobile paths.

| Workflow | Critical path / excess work | Measurement and next capture |
|---|---|---|
| Login/dashboard | Native Firebase sign-in → profile/cache → token; email alias additionally calls backend; unread gate can wait 3 s | Backend login component measured below; native sign-in, gate and paint unmeasured |
| Project create/edit | Backend validation → authoritative write/roster → enrichment; simple edit may use direct Firebase and reread | Create lifecycle measured; edit/device unmeasured |
| Project activate/deactivate | Backend account/revocation → transactions/roster → confirmed state update | Lifecycle measured; preserve pending billing approval |
| Module create/edit | Backend validation/assignment reconciliation; full detail fetch on some edits | Backend regression spans; device unmeasured |
| Module status | Backend authorization/transaction; work stage avoids unnecessary roster work | Backend fixture spans; device unmeasured |
| Employee management | Profile → identity validation scan → provisioning/identity transaction/Firebase Auth → response | Backend fixture spans include contention; device unmeasured |
| Attendance in/out | Location acquisition → profile → transaction → server timestamp reread | Native/location spans still needed; rules and Flutter regressions pass |
| Team attendance | Profile → modules → serial parents → serial employee/day pairs | Static N+1 confirmed; physical timing unmeasured |
| Timesheet submit | Profile → module → sequential selected activities → transaction/ledger → confirmed local update | Rules/regression coverage; native transaction timing still needs device |
| Timesheet approve/reject | Profile/fallback HTTP → account check → transaction/ledger/notifications → UI | Backend approve/reject route traces; device unmeasured |
| Billing submit/approve | Profile/fallback HTTP → business validation/transaction → optional pending request | Backend fixture traces; duplicate pending locks preserved |
| Notifications | Profile → all pages → local sort/count; separate count/list calls | Native request totals traced; volume/device benchmark outstanding |
| Activity lists | Profile → server list pages → active filtering/cache | Regression checks; device/cached-display timing outstanding |
| Reports | Authorization → project/module/work-log queries → employee enrichment → encoding | Enrichment benchmark below; large mixed report workload outstanding |
| File loading/upload | Profile/fallback → capability authorization → signed object request → completion check | Mock-provider regression spans; real object transfer unmeasured |

All ViewModels retain their existing state/validation logic. The shared notifier
adds development trace markers only. No speculative success state, authorization
cache relaxation, background critical validation or broad data reload rewrite
was introduced.

## 5. Newly implemented optimizations

1. Batch distinct employee profile reads for report employee-hour enrichment;
   request only `id`, `employeeCode`, `name`, `role`. Preserve missing-profile 404.
2. Reuse the backend password-authentication HTTP connection pool over the
   service lifespan, retaining the existing timeout and no automatic POST retry.
3. Add the opt-in instrumentation, finite emulator-only benchmarks and trace
   summarizer described here. These are observability changes, not speed claims.

## 6. Benchmarks and hosting evidence

Ten samples per component; nearest-rank P95 equals maximum at this sample size.
Finite runs are sensitive to emulator/JIT warm-up and workstation load.

| Component | Before median / P95 / max (ms) | After median / P95 / max (ms) | Calls/errors |
|---|---:|---:|---|
| 100-employee report enrichment | 205.1 / 242.2 / 242.2 | 32.0 / 44.4 / 44.4 | 100 get RPCs → 1 batch RPC; 100 docs unchanged; no writes; 0 errors |
| Backend login with lifespan | 218.5 / 397.9 / 397.9 | 8.1 / 25.8 / 25.8 | 1 API call/sample; ordinary code login 1 Auth call + 1 employee get; 0 errors |

Project lifecycle is unchanged by the report optimization. Rerunning the
existing benchmark confirms function and volume behavior, but the variation
below **is not attributed to a new lifecycle optimization**:

| Action | 10 members before, median / P95 / max (ms) | 10 members after (ms) | 100 members after, 5 samples (ms) |
|---|---:|---:|---:|
| Create project/module | 79.2 / 166.0 / 166.0 | 67.6 / 86.1 / 86.1 | 335.1 / 394.1 / 394.1 |
| Deactivate project | 66.8 / 93.4 / 93.4 | 48.6 / 61.2 / 61.2 | 187.5 / 248.4 / 248.4 |
| Activate project | 35.3 / 45.8 / 45.8 | 26.5 / 35.7 / 35.7 | 31.2 / 49.2 / 49.2 |
| Activate module | 61.7 / 79.4 / 79.4 | 51.2 / 64.5 / 64.5 | 243.0 / 349.3 / 349.3 |

Each lifecycle row represents one API request/sample. All benchmark requests
succeeded. Setup, cleanup and the extra teardown deactivation are excluded.
No paired 100-member baseline was collected in this audit. Earlier documentation
has historical numbers but those are not a controlled before/after comparison.

Read-only Railway `/health`: first workstation request **450.2 ms**; eleven
subsequent requests on a reused HTTP connection median **241.2 ms**, P95/max
**378.5 ms**, zero errors. Health does not access Firestore. First connection
latency is **not** proof of a backend cold start. Local emulator/TestClient
results exclude internet, phone rendering, cloud Firestore and cold startup.

Firestore metadata API confirms development database location **asia-south1**,
native Standard edition. The 1,116 ms metadata request includes workstation
authentication/HTTPS and is **not** database-read or Railway-to-Firestore RTT.
Historical Railway notes say Amsterdam; current region is unverified. That
possible regional separation merits measurement, not an infrastructure upgrade.

Current Railway startup duration, cold/warm application state, CPU, memory,
request concurrency and backend-to-Firestore RTT remain unmeasured without
runtime access. Physical device comparison is unavailable. No hosted mutation
benchmark or deliberate cold restart was performed.

## 7. Remaining bottlenecks and target acceptance

Highest priority: capture a reported slow form on the actual installed build
with one interaction trace, identify the transport, and compare stage timings
against a matching local seeded run. Then measure profile/cache overhead,
notification gating, team attendance and project graph hydration at realistic
volumes. Add bounded concurrency/deduplication only after capturing a baseline.

No end-to-end target (<100 ms feedback, <300 ms cached display, <800 ms list,
<1 s simple confirmation, <1.5 s complex confirmation) is certified. The
backend components measured locally meet their corresponding server-only
budgets, but the targets include unmeasured networking/rendering. Regression
contention cases exceed them; the workload and emulator lock waits differ
from normal single-user submissions. Do not silently remove transactional
consistency to meet a timing target.

Do not add automatic mutation retries until each endpoint has a documented
idempotency contract. Existing pending locks and timesheet hashes are not a
universal employee/module creation idempotency solution.

## 8. Regression tests

* Final clean seeded backend run with Firestore tracing enabled: **138 passed**,
  8 dependency/deprecation warnings, in 50.47 seconds.
* New backend coverage: report totals/order/filtering/missing employees;
  opt-in/redaction/401 status; production disablement; concurrent trace isolation;
  HTTP pool reuse and lifecycle closure. Four targeted tests passed.
* Flutter baseline: **54 passed, 4 failed**. Instrumented run: **57 passed,
  4 failed**, adding three tracing/HTTP/body/button tests. All four failures are
  the pre-existing lock-screen comparisons in `visual_preservation_test.dart`
  (400/800 widths, light/dark). No lock-screen source was edited.
* Flutter analysis after removing obsolete notifier imports: **no issues**.
* Firebase rules: **17 passed, 0 failed**, including pending multi-module
  timesheets, retry accounting, access rules and daily limits. Rules unchanged.
* Final `git diff --check`: passed.

An intermediate repeat backend run had three failures because prior tests left
fixed synthetic phone/email identities in the emulator. Resetting only the
owned loopback demo Auth/Firestore fixtures produced a clean 137-pass run.
The existing suite needs a clean seeded emulator; this was not worked around
by relaxing identity validation.

## 9. Credential audit and deployment requirements

A bounded pattern scan checked **645 reachable Git blobs** across all locally
available refs for private-key blocks, AWS access keys, GitHub tokens, Resend
keys and JWTs: **no matches**. `.env`, `.local`, service-account files, signing
keys and APKs are ignored; `.env` is not tracked. This is not a comprehensive
entropy/provider-secret audit and does not examine unavailable remote refs,
reflogs, hosting logs or distribution outside Git. Firebase public application
configuration is not a service-account credential.

No specific exposed live secret was confirmed, so no credential was rotated.
If a live private key/provider credential is found in history or a shared
artifact, revoke/rotate it immediately, inspect provider access logs, update
the consuming service and then remove the leaked copy. Deleting a tracked
file alone does not revoke a credential. Keep private `.local` evidence out
of shared handoff bundles.

**Stop before deployment:** backend report/pool changes require an explicitly
approved backend rollout. Client tracing requires a debug/profile build;
production APKs do not emit it. This change does not require a Firebase rules
deployment. Earlier activity/rule fixes may still require their own rollout.
Add a nonsecret build revision to future health/build metadata so inclusion
can be checked without guessing from behavior or artifact timestamps.

## 10. Reproduction and next steps

Use only an isolated `demo-crompton-pms` emulator. This investigation used Auth
`127.0.0.1:9198`, Firestore `127.0.0.1:8186`, and a separate rules emulator on
8086 because existing rules tests hardcode that port. All dispatch flags were
disabled and local mode starts no background delivery workers.

```powershell
$env:ENVIRONMENT='local'
$env:PROJECT_ID='demo-crompton-pms'
$env:FIREBASE_API_KEY='demo-key'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8186'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9198'
$env:ALLOW_REAL_MESSAGES='false'
$env:MSG91_DISPATCH_ENABLED='false'
$env:ZEPTOMAIL_DISPATCH_ENABLED='false'
$env:RESEND_DISPATCH_ENABLED='false'
$env:FCM_DISPATCH_ENABLED='false'
.\.venv\Scripts\python.exe scripts/seed.py
.\.venv\Scripts\python.exe scripts/benchmark-report-enrichment.py --output .local/reports.json
.\.venv\Scripts\python.exe scripts/benchmark-auth-login.py --output .local/login.json
.\.venv\Scripts\python.exe scripts/benchmark-project-lifecycle.py --members 100 --runs 5
$env:PERFORMANCE_TRACE='1'
.\.venv\Scripts\python.exe -m pytest backend/tests -q
# In mobile/: flutter test --dart-define=PERFORMANCE_TRACE=true
# In mobile/: flutter analyze --no-pub
# In firebase/, with isolated emulator on 8086: npm test
```

Raw evidence remains in ignored `.local/audit-*`: paired report/login/lifecycle
JSON; backend/Flutter/analyzer/rules logs; hosted health samples; database
location; sanitized credential scan; and per-request workflow spans. Summarize
captured backend JSONL with:

```powershell
.\.venv\Scripts\python.exe scripts/summarize-performance.py .local/audit-workflow-spans.jsonl --output .local/audit-workflow-summary.json
```

That summary includes every observed route's sample count, errors, median,
P95, maximum, stage medians and operation counters. **Regression fixture
timings include deliberate races, overrides and mocked providers, and are not
representative user workflow latency benchmarks.** Expected authorization and
validation failures are not production error-rate estimates.

Before acceptance: verify installed APK identity and deployed revision; obtain
warm/cold device traces for each row of the workflow matrix; capture hosted
resource/concurrency metrics and actual backend-Firestore RTT; benchmark
realistic list sizes and upload sizes in a notification-disabled environment;
then prioritize the next change using the longest measured stage. No paid
infrastructure change is justified by the current health-only cloud evidence.

## Appendix: observed backend regression trace breakdown

These are all **55 route groups** observed in the final clean test run. They
include successful and intentionally rejected calls, mocked providers,
dependency overrides and concurrent contention. They are diagnostic fixture
measurements, not normal user latency or a before/after benchmark. Stage
columns are medians across requests, with absent stages counted as zero;
independently computed medians do not add up to the total. Read/write counts
are cumulative SDK diagnostics over each group, not per-request billing.

| Route | Requests / expected error responses | Median / P95 / max ms | Auth ms | Document get ms | Query ms | Batch read ms | Transaction commit ms | JSON ms | Get calls / returned docs / committed writes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `DELETE /api/activities/{key}` | 2 / 1 | 10.62 / 12.93 / 12.93 | 0.00 | 2.33 | 3.70 | 0.00 | 0.60 | 0.01 | 2 / 1 / 1 |
| `DELETE /api/files/{key}` | 3 / 1 | 13.64 / 19.95 / 19.95 | 3.20 | 4.63 | 0.00 | 0.00 | 0.00 | 0.02 | 11 / 0 / 2 |
| `DELETE /api/projects/{key}` | 3 / 0 | 22.38 / 31.22 / 31.22 | 0.00 | 3.87 | 5.99 | 4.25 | 2.61 | 0.02 | 7 / 20 / 13 |
| `GET /api/activities` | 3 / 0 | 5.68 / 7.57 / 7.57 | 0.00 | 0.00 | 2.55 | 0.00 | 0.00 | 0.02 | 0 / 9 / 0 |
| `GET /api/billing` | 2 / 0 | 14.37 / 15.72 / 15.72 | 2.55 | 6.82 | 2.81 | 0.00 | 0.00 | 0.03 | 10 / 4 / 0 |
| `GET /api/employees` | 2 / 0 | 7.62 / 8.57 / 8.57 | 0.00 | 0.00 | 5.41 | 0.00 | 0.00 | 0.04 | 0 / 7 / 0 |
| `GET /api/files` | 4 / 1 | 11.97 / 16.36 / 16.36 | 3.44 | 4.01 | 2.62 | 0.00 | 0.00 | 0.03 | 8 / 1 / 0 |
| `GET /api/files/{key}/download` | 9 / 6 | 9.67 / 22.51 / 22.51 | 2.63 | 4.72 | 0.00 | 0.00 | 0.00 | 0.00 | 24 / 0 / 0 |
| `GET /api/reports/attendance/employees` | 1 / 0 | 12.12 / 12.12 / 12.12 | 3.35 | 1.99 | 3.20 | 0.00 | 0.00 | 0.05 | 1 / 2 / 0 |
| `GET /api/reports/attendance/employees/{uid}` | 2 / 1 | 16.13 / 25.12 / 25.12 | 3.36 | 2.35 | 6.76 | 0.00 | 0.00 | 0.04 | 3 / 0 / 0 |
| `GET /api/reports/billing-status` | 1 / 0 | 11.14 / 11.14 / 11.14 | 2.23 | 1.16 | 4.95 | 0.00 | 0.00 | 0.03 | 1 / 4 / 0 |
| `GET /api/reports/billing/modules/{mid}` | 1 / 0 | 12.28 / 12.28 / 12.28 | 3.52 | 4.72 | 1.67 | 0.00 | 0.00 | 0.03 | 2 / 0 / 0 |
| `GET /api/reports/billing/projects/{pid}` | 1 / 0 | 18.11 / 18.11 / 18.11 | 2.89 | 4.49 | 5.83 | 0.00 | 0.00 | 0.08 | 3 / 2 / 0 |
| `GET /api/reports/clients` | 1 / 0 | 28.45 / 28.45 / 28.45 | 2.54 | 8.29 | 14.29 | 0.00 | 0.00 | 0.03 | 5 / 4 / 0 |
| `GET /api/reports/clients/{cid}` | 1 / 0 | 17.76 / 17.76 / 17.76 | 2.87 | 4.95 | 6.42 | 0.00 | 0.00 | 0.03 | 3 / 3 / 0 |
| `GET /api/reports/projects` | 5 / 2 | 17.17 / 29.53 / 29.53 | 3.01 | 4.26 | 6.90 | 0.00 | 0.00 | 0.03 | 13 / 8 / 0 |
| `GET /api/reports/projects/{pid}` | 1 / 0 | 14.46 / 14.46 / 14.46 | 3.81 | 3.32 | 5.07 | 0.00 | 0.00 | 0.04 | 3 / 1 / 0 |
| `GET /api/reports/projects/{pid}/modules/{mid}` | 1 / 0 | 13.72 / 13.72 / 13.72 | 2.86 | 4.11 | 4.26 | 0.00 | 0.00 | 0.03 | 3 / 1 / 0 |
| `GET /api/reports/working-hours/employees` | 1 / 0 | 9.42 / 9.42 / 9.42 | 3.77 | 1.20 | 2.48 | 0.00 | 0.00 | 0.03 | 1 / 2 / 0 |
| `GET /api/reports/working-hours/employees/{uid}` | 2 / 1 | 10.27 / 14.59 / 14.59 | 2.63 | 2.75 | 2.63 | 0.00 | 0.00 | 0.02 | 3 / 0 / 0 |
| `GET /api/users/me` | 7 / 3 | 6.52 / 30.39 / 30.39 | 2.15 | 1.22 | 0.00 | 0.00 | 0.00 | 0.02 | 4 / 0 / 0 |
| `GET /health` | 5 / 0 | 2.13 / 3.94 / 3.94 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.02 | 0 / 0 / 0 |
| `POST /api/auth/forgot-password/reset` | 2 / 1 | 20.99 / 25.48 / 25.48 | 0.00 | 1.84 | 4.95 | 0.00 | 1.67 | 0.03 | 2 / 2 / 2 |
| `POST /api/auth/forgot-password/send-otp` | 5 / 2 | 9.30 / 11.34 / 11.34 | 0.00 | 0.95 | 3.28 | 0.00 | 1.20 | 0.02 | 4 / 5 / 6 |
| `POST /api/auth/forgot-password/verify-otp` | 4 / 3 | 8.76 / 9.86 / 9.86 | 0.00 | 1.13 | 2.98 | 0.00 | 1.70 | 0.00 | 4 / 4 / 2 |
| `POST /api/auth/login` | 21 / 3 | 244.37 / 316.30 / 408.71 | 0.00 | 1.55 | 0.00 | 0.00 | 0.00 | 0.03 | 16 / 1 / 0 |
| `POST /api/auth/phone/send` | 3 / 2 | 11.17 / 13.28 / 13.28 | 2.45 | 3.03 | 0.00 | 0.00 | 1.01 | 0.00 | 7 / 0 / 3 |
| `POST /api/auth/phone/verify` | 13 / 11 | 17.07 / 2281.92 / 2281.92 | 2.74 | 5.67 | 0.00 | 0.00 | 3.09 | 0.00 | 38 / 0 / 18 |
| `POST /api/auth/signup/phone/send-otp` | 19 / 6 | 15.32 / 78.35 / 78.35 | 0.00 | 4.20 | 3.72 | 0.00 | 1.86 | 0.02 | 47 / 19 / 39 |
| `POST /api/auth/signup/phone/verify-otp` | 19 / 6 | 37.43 / 2096.50 / 2096.50 | 0.00 | 13.81 | 3.66 | 0.00 | 6.75 | 0.02 | 138 / 19 / 86 |
| `POST /api/auth/signup/send-otp` | 30 / 3 | 11.28 / 26.15 / 63.24 | 0.00 | 1.51 | 3.53 | 0.00 | 1.70 | 0.02 | 28 / 29 / 51 |
| `POST /api/auth/signup/set-password` | 19 / 2 | 28.45 / 57.71 / 57.71 | 0.00 | 5.13 | 3.61 | 0.00 | 4.61 | 0.03 | 53 / 19 / 51 |
| `POST /api/auth/signup/verify-otp` | 38 / 19 | 11.21 / 34.13 / 36.96 | 0.00 | 2.01 | 3.89 | 0.00 | 1.84 | 0.01 | 37 / 38 / 32 |
| `POST /api/employees` | 65 / 12 | 25.42 / 2138.90 / 2307.51 | 0.00 | 2.04 | 4.93 | 0.00 | 2.06 | 0.03 | 75 / 327 / 162 |
| `POST /api/employees/validate-identity` | 7 / 4 | 2.63 / 10.34 / 10.34 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1 / 16 / 0 |
| `POST /api/files/authorize-upload` | 26 / 12 | 12.46 / 2106.82 / 2124.91 | 2.95 | 4.38 | 0.00 | 0.00 | 1.10 | 0.02 | 66 / 0 / 28 |
| `POST /api/files/{key}/complete` | 13 / 7 | 14.62 / 35.60 / 35.60 | 3.18 | 6.65 | 0.00 | 0.00 | 0.00 | 0.00 | 51 / 0 / 9 |
| `POST /api/module-change-requests` | 8 / 4 | 1042.47 / 2155.99 / 2155.99 | 3.62 | 11.03 | 0.99 | 2.45 | 1006.51 | 0.01 | 32 / 12 / 12 |
| `POST /api/modules` | 2 / 1 | 22.62 / 35.90 / 35.90 | 3.78 | 4.56 | 2.97 | 4.69 | 1.97 | 0.01 | 5 / 14 / 4 |
| `POST /api/notifications/delay-requests` | 4 / 1 | 22.64 / 24.78 / 24.78 | 2.56 | 5.79 | 4.25 | 0.00 | 1.40 | 0.03 | 15 / 21 / 12 |
| `POST /api/projects` | 20 / 6 | 29.26 / 4152.24 / 4373.59 | 0.00 | 1.77 | 8.11 | 9.07 | 1.54 | 0.04 | 26 / 228 / 70 |
| `PUT /api/billing-status-change-requests/{key}/reject` | 1 / 0 | 14.70 / 14.70 / 14.70 | 2.90 | 4.40 | 0.00 | 0.00 | 1.84 | 0.03 | 2 / 0 / 2 |
| `PUT /api/billing/{mid}` | 7 / 4 | 14.91 / 25.23 / 25.23 | 2.80 | 7.40 | 0.00 | 0.00 | 0.00 | 0.00 | 36 / 2 / 7 |
| `PUT /api/delay-requests/{key}/approve` | 2 / 1 | 9.89 / 12.88 / 12.88 | 2.87 | 2.53 | 0.00 | 0.00 | 0.86 | 0.13 | 3 / 0 / 2 |
| `PUT /api/delay-requests/{key}/reject` | 2 / 1 | 13.05 / 16.52 / 16.52 | 2.86 | 4.61 | 0.00 | 0.00 | 0.77 | 0.02 | 4 / 0 / 2 |
| `PUT /api/employees/{uid}` | 9 / 5 | 20.09 / 2108.51 / 2108.51 | 0.00 | 6.33 | 4.66 | 0.00 | 1.22 | 0.00 | 25 / 46 / 8 |
| `PUT /api/employees/{uid}/activate` | 1 / 0 | 27.62 / 27.62 / 27.62 | 2.78 | 8.25 | 0.00 | 0.00 | 0.00 | 0.03 | 3 / 0 / 1 |
| `PUT /api/employees/{uid}/deactivate` | 1 / 0 | 23.52 / 23.52 / 23.52 | 2.46 | 5.94 | 0.00 | 0.00 | 0.00 | 0.02 | 3 / 0 / 1 |
| `PUT /api/module-change-requests/{key}/approve` | 4 / 2 | 12.78 / 16.81 / 16.81 | 2.70 | 3.86 | 0.00 | 0.00 | 0.65 | 0.02 | 11 / 0 / 6 |
| `PUT /api/modules/{key}/activate` | 2 / 1 | 16.78 / 25.13 / 25.13 | 0.00 | 2.79 | 3.55 | 2.46 | 1.75 | 0.01 | 5 / 6 / 4 |
| `PUT /api/modules/{key}/work-stage` | 10 / 6 | 13.02 / 24.26 / 24.26 | 0.00 | 4.25 | 0.00 | 0.00 | 0.00 | 0.00 | 22 / 18 / 10 |
| `PUT /api/modules/{mid}` | 6 / 5 | 12.41 / 38.30 / 38.30 | 2.62 | 4.86 | 0.00 | 0.00 | 0.00 | 0.00 | 19 / 19 / 6 |
| `PUT /api/projects/{key}/activate` | 1 / 0 | 19.14 / 19.14 / 19.14 | 0.00 | 3.67 | 4.31 | 0.00 | 4.40 | 0.06 | 2 / 1 / 2 |
| `PUT /api/projects/{key}/work-stage` | 1 / 1 | 6.06 / 6.06 / 6.06 | 2.61 | 1.19 | 0.00 | 0.00 | 0.00 | 0.00 | 1 / 0 / 0 |
| `PUT /api/work-logs/{key}/approve` | 5 / 3 | 17.28 / 2157.22 / 2157.22 | 3.74 | 7.35 | 0.00 | 0.00 | 2.32 | 0.00 | 26 / 0 / 6 |
