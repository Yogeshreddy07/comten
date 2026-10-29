# Performance changes — 29 October 2026

Implemented against `e11bd57`, retaining authorization, validation, approval
locks, transaction accounting and existing screen contracts. The earlier
performance release's startup regression is documented in
[its rollback report](PERFORMANCE_RELEASE_20261028.md). This change leaves
splash timing, identity restoration and app-lock routing untouched.

## Changes

- Billing queries only modules in the billing work stage. Distinct parent
  projects, leaders and approval locks load in one batch; the requests named
  by those locks load in a second batch. A lock alone never means pending:
  the referenced request must still have `approvalStatus=PENDING`. Mutations
  retain the existing transaction and row-enrichment path.
- Backend-only mobile operations (including billing, files, approvals and
  module edits) dispatch directly to the backend, which performs its live
  account, revoked-token and role checks. They no longer first perform a
  redundant client profile request. Native attendance/timesheet transactions,
  notification updates and supported direct reads retain their profile checks.
- Module lists with a project filter apply that filter in Firestore, using
  the existing projectId/memberIds index. Staff queries retain membership
  restrictions. No index deployment is necessary.
- Document enrichment shares repeated paths within a single operation, with
  at most eight document reads in flight. There is no cross-request identity
  or authorization cache. Module summaries across a project list share leader
  reads; team attendance deduplicates parent projects and loads staff records
  concurrently. Ordering and missing-employee behavior are preserved.
- Timesheet activity references are validated before reading, then distinct
  references load concurrently. The saved activity ordering, duplicate
  selections, idempotency key, attendance limit and daily ledger remain intact.
- Billing refresh keeps current-session content visible with a progress bar,
  combines simultaneous list requests, and clears content on refusal. Session
  and revision guards prevent stale completions overwriting a confirmed save
  or repopulating another session. Duplicate saves are refused while pending;
  errors release progress. Success still requires an acknowledged server write.
- Manager app entry starts one nonblocking health request per process on the
  shared HTTP client, overlapping connection setup with entry screens. It adds
  no Firestore reads and never gates navigation; failure is silently ignored.
  No repeated health polling or automatic mutation retry was introduced.
- Successful backend PUT requests now invalidate local data snapshots, matching
  POST/DELETE behavior and preventing stale post-edit reads.

These changes reduce repeated reads without introducing listeners, background
polling, a paid cache, database duplication or additional infrastructure.
Parallel reads reduce serial waits but do not inherently lower document charges;
deduplication and query filtering reduce redundant document retrieval. Rule
evaluation can add billed reads. See [Firebase best practices](https://firebase.google.com/docs/firestore/best-practices)
and [Firestore pricing](https://firebase.google.com/docs/firestore/pricing).

## Measurements

Five paired read-only calls against the dedicated development Firestore
database, using the seven existing billing records:

| Local function using real cloud Firestore | Median | Maximum |
|---|---:|---:|
| Legacy sequential enrichment | 1,273.6 ms | 2,182.0 ms |
| New batched enrichment | 176.6 ms | 194.2 ms |

Median reduction: **86.1%**. Each pair returned identical rows. The comparison
made no writes and excludes HTTP authentication, Railway and mobile rendering.
Reproduce with `scripts/benchmark-billing-reads.py --cloud --output <path>`.
Cloud mode is pinned to the existing development project and uses the ignored
local service-account file. It never prints row contents or credentials.

Before rollout, three authenticated read-only hosted `/api/billing` calls had
median **10,020.4 ms**, maximum **10,124.1 ms**, seven rows and no errors.
The saved synthetic controller credentials were used without resetting them.

## Verification

- Backend: **153 passed**, ten existing dependency/deprecation warnings.
- Flutter: **74 passed**, four lock-screen image comparisons fail, matching
  the previously documented failures at widths 390/800 in both themes.
  Lock-screen code was not changed. Seven new Flutter tests cover read sharing,
  bounded concurrency/error recovery, routing, refresh and session/save races.
- Flutter analysis: **no issues**.
- Firebase rules: **17 passed**. Added a query assertion for project-scoped
  module access while retaining the required membership filter. Rules unchanged.
- Five new backend cases cover exact billing equivalence, deduplicated batch
  volume, pending/approved/dangling locks, empty lists and denied roles.
- Signed universal release APK built successfully. Gradle/AGP/Kotlin support
  warnings remain. No Firebase schema, security rules, billing configuration,
  provider settings or hosting region was changed.

## Android artifact and device

Candidate **1.0.10 / versionCode 13**, package `com.crompton.pms.frontend`.
APK: `.local/performance-20261029/Crompton-PMS-1.0.10-performance.apk`.
SHA-256: `e5cb6243d9a77c560e6b3d1de4150e66e3adbf688d7b7f52d34b4908e5ca2f66`.
Signing certificate SHA-256:
`99207a2b2f5a3f589f7ec6f2109be80cb585d713e828161359f8621da5c71a80`.

Installed with `adb install -r` on OPPO CPH2471 (`ZPQKY94PCMFMTSKN`), upgrading
1.0.4/code 5 (initial update code 12, final connection-preparation build code 13). Package UID **10343** and first-install date
**2026-10-24 17:35:16** were unchanged. App data was not cleared or uninstalled.
The original installed APK was retained privately. The updated app launches to
Welcome. Login with the existing synthetic controller account succeeded,
including the unread-notification gate and its Continue action. Notifications
were not marked read for the probe.

Three read-only navigation runs per screen on the updated phone:

| Screen | Median observed ready | Maximum |
|---|---:|---:|
| Projects | 1,000 ms | 2,156 ms |
| Employee Management | 1,157 ms | 1,937 ms |
| Billing Management | 1,078 ms | **9,219 ms** |
| Activities | 953 ms | 1,047 ms |

These are automation-inclusive upper bounds. Repeated billing entries can
show retained content before the new server response arrives; they are not
fresh-server timings. The first billing entry was still slow and remains an
open issue. All twelve screen entries passed, and billing was additionally
checked for delayed refresh errors. There was no comparable phone baseline
run, so this table does not establish a phone before/after improvement.
A temporary, private diagnostic build enabled the existing safe stage traces
on the same signed app. Before connection preparation, a first native Billing
GET took **4,067.7 ms**, of which **4,048.0 ms** was HTTP and **6.6 ms** was token
retrieval. Three warm native GETs took **2,219.8 / 2,322.2 / 2,540.2 ms** (sorted).
This isolates most remaining wait to the request/response path, not Firebase
transport dispatch or token retrieval. It does not measure every UI/JSON stage. It does not separate DNS, TLS and server
processing or explain every part of the earlier 9.2-second observation.

After adding the nonblocking health preparation, one first native Billing GET
completed in **3,234.8 ms**, with **3,228.3 ms** in HTTP and **5.5 ms** in token
retrieval. This is a single observation, not a controlled distribution or proof
that all first loads improved. Fresh network responses still take seconds.
Final build code 13 restores release tracing disablement; diagnostic builds
are not handoff artifacts.

A shell-level network probe was inconclusive (one resolver failure and one
stdin/process timeout); it is not evidence of an application DNS fault. Its
remote diagnostic file was removed. No network/device settings were changed.

The reusable `scripts/benchmark-mobile-navigation.py` refuses to operate unless
the app is foreground and its unlocked dashboard is visible. It never enters
credentials, handles a PIN or changes business records.

## Rollout and remaining limits

The mobile update is installed. Commit `9697ade` was pushed to the existing main
branch, triggering the configured Railway deployment. GitHub's
`vivacious-dream - comten` status reports success for deployment
`3711849f-13bd-4d1a-8ca7-96f32ef42a35`. Its application health reports the
expected development project. No hosting settings were changed.

Five authenticated read-only hosted billing requests after deployment measured
**2,098.7 ms median**, **2,466.0 ms maximum**, seven rows and zero errors.
Compared with the three before samples, the median fell **79.1%**. This is
workstation-to-hosted-API timing, not a phone rendering measurement. The fresh
response is still about two seconds; no subsecond fresh-server claim is made.
The response exactly matched an independent legacy calculation against the
same live database. Anonymous access returned 401; an authenticated employee
returned 403. All probes used existing synthetic accounts without resets or
business writes. Private logs and timing JSON are under
`.local/performance-20261029/`.

There is no claim of zero network latency or certification of every workflow.
Remaining full-app work includes notification count/list duplication, the live
profile read before cached direct reads, large project graph queries, employee
identity-directory validation, location acquisition and attachment transfer.
Changing those requires additional focused measurements and correctness checks.
Native GPS/attendance writes, live approval/billing mutations, OTP/provider
delivery and exhaustive all-role acceptance were not exercised by this audit.
