> Historical investigation: the candidate was subsequently deployed, tested, and rolled back after an authenticated startup regression. See [the final controlled-release report](PERFORMANCE_RELEASE_20261028.md) for current status.

# Connected Android performance follow-up â€” 28 October 2026

## Outcome

Tested an OPPO CPH2401 running Android 14. The normal installed application is
**1.0.6, versionCode 7**. Read-only tests reproduced a persistent **10.4-second
Billing Management load**. Other installed lists were observed ready within
roughly 0.7â€“1.2 seconds, including UI automation overhead.

Implemented and measured a billing backend fix, removed the artificial splash
delay, and improved billing refresh behavior. A separately installed performance
build exercised real Flutter screens, Firebase SDKs and confirmed project writes
against disposable local emulators. Both completed before/after runs passed.

The updated normal release APK **1.0.7, versionCode 8** is built and its signature
matches the installed app. **Railway deployment and installation over the normal
app have not been performed.** The original investigation instruction says:
â€œDo not deploy without explicit approval.â€ The temporary sandbox app was removed
after collecting results; the installed normal app and its stored data were kept.

## What the phone reproduced

Three read-only navigation runs on the original installed app:

| Screen | Median observed upper bound | Maximum |
|---|---:|---:|
| Projects | 697 ms | 751 ms |
| Employee Management | 755 ms | 1,242 ms |
| Billing Management | **10,424 ms** | **10,599 ms** |
| Activities | 710 ms | 770 ms |

These bounds include ADB/UI hierarchy polling, and are not precise enough to
certify a 100 ms target. The billing delay persisted on all three entries.

Five authenticated, read-only requests to the existing hosted `/api/billing`
endpoint independently measured **9,633 ms median**, **9,976 ms maximum**, with
seven rows and zero errors. This used the existing synthetic PC001 development
account, verified the dedicated development project through health, and made no
business mutations. The repeated slow response places the dominant delay in
the hosted request path rather than only widget rendering.

Three cold process starts of the original installed app reached its welcome
screen in **3,302 ms median**, **3,502 ms maximum**, including Android launch
and UI polling overhead. No PIN was entered or changed. This is a different
measurement from the controlled in-process startup comparison below.

## Confirmed billing work and fix

The original billing list scanned all modules and, for each billing row, read
its parent project, employee profile and pending-approval lock serially. Held
locks also triggered an individual request-document read. Seven rows therefore
incurred at least 21 individual enrichment reads, often repeating the same
parents/leaders, plus module pagination and any referenced approval reads.

`backend/app/operations.py` now:

1. Queries modules with `workStage == BILLING` before enrichment.
2. Batches distinct parent, leader and lock references, projecting only needed
   fields.
3. Batches the request documents named by the locks, preserving verification
   that a request is actually pending. Approved, missing and dangling requests
   still produce `reversionPending=false`.
4. Produces the same billing-row contract and keeps manager authorization,
   editable/inactive-parent rules, mutation transactions and approval locks.

The list uses one batch of metadata and, when needed, one batch of approval
requests, instead of per-row sequential round trips. Module pagination and
authentication remain. No Firebase rules or indexes were changed; the new
query was exercised successfully against the real development database.

| Controlled backend measurement | Before median / max | After median / max |
|---|---:|---:|
| Seven modules, ten authenticated local emulator requests | 89.5 / 172.0 ms | **27.4 / 60.5 ms** |
| Same seven real development billing rows, five read-only local-function calls | 1,127.5 / 2,114.9 ms | **197.6 / 834.6 ms** |

All five after-response hashes matched the before response exactly. The cloud
function comparison includes database access from this workstation and first
connection/credential warm-up; it excludes Railway, API authentication and the
phone. It establishes a measured improvement in the changed code, **not a
verified after-deployment latency for Railway**. The live endpoint remains on
its previous behavior until rollout is explicitly approved and verified.

## Phone before/after results

The performance APK used a separate package,
`com.crompton.pms.frontend.performance`, and refused cloud configuration.
Firebase Auth/Firestore and API calls used USB-reversed loopback emulators.
Synthetic records were seeded locally, and only this probe's `DEVICE-` project
records were removed between completed paired runs. No real GPS attendance,
approval, billing mutation, SMS, email or push dispatch was exercised on cloud.

The integration probe rendered the actual app, project list, review screen,
loading button and authoritative project-success screen. Form setup used the
actual ViewModel setters; the measured submission began at the real confirm
button. It required a confirmed module before accepting the success frame.

| Stage | Before median / max | After median / max | Samples per version |
|---|---:|---:|---:|
| In-process initialization â†’ welcome frame | **2,230 / 2,230 ms** | **252 / 252 ms** | 1 |
| Native Firebase login + local identity persistence | 643 / 643 ms | 562 / 562 ms | 1 |
| Project list to ready content frame | 662 / 854 ms | 598 / 787 ms | 5 |
| Activity API processing | 111 / 158 ms | 100 / 175 ms | 5 |
| Employee API processing | 150 / 210 ms | 137 / 233 ms | 5 |
| Notification count API processing | 125 / 169 ms | 121 / 128 ms | 5 |
| Module API processing | 213 / 277 ms | 190 / 214 ms | 5 |
| Confirm tap â†’ rebuilt loading-indicator frame | **19 / 52 ms** | **19 / 42 ms** | 5 |
| Confirm tap â†’ confirmed success frame | **536 / 639 ms** | **519 / 811 ms** | 5 |
| Hosted health from phone, reused connection | 250 / 477 ms | 247 / 513 ms | 5 |

At five samples, nearest-rank P95 equals the listed maximum. One startup/login
sample per version is an observation, not a distribution or P95 claim.

Only the startup change is attributed to removing the deliberate two-second
delay. The project write/read logic was unchanged; its modest timing variation
is not claimed as a new optimization. The controlled startup stopwatch starts
inside the integration process before `app.main()`; Android/Flutter engine
boot before the test callback is excluded. It cannot be compared directly with
the original application's 3.3-second native cold-launch measurement.

Frame measurements identify completed Flutter frame work, not the physical
display's photon time. List iterations reset provider state and leave transport
caching enabled, so they are not a measurement of normal unchanged-provider
screen re-entry. The local emulator results cannot establish hosted submission
latency. Hosted health does not access Firestore or perform an authoritative
write; it is a network/service observation, not a lower bound for every route.

## Other implemented responsiveness changes

* Removed the fixed splash timer; required session and identity checks remain.
* Billing API calls now delegate directly to FastAPI before a redundant client
  Firestore profile read. The backend still checks the live account, revocation
  and manager role. Mutation cache invalidation remains in place.
* Billing refresh retains the current session's loaded content while fetching
  fresh data and shares simultaneous list requests. A server refusal clears
  retained content and displays the error.
* Session/revision guards prevent a former session or older list response from
  revealing old data or erasing a confirmed mutation. Duplicate billing saves
  are rejected locally while one is running. Existing state remains unchanged
  until the authoritative mutation succeeds.
* Added an awaitable `Future<void> main()` for deterministic initialization in
  the device probe, and sandbox-only Android package/network configuration.
  Emulator loopback host mapping is disabled only for the physical sandbox;
  normal Android emulator mapping is preserved. Cloud release configuration
  and production tracing disablement remain intact.

The billing refresh changes were validated by regression tests and included in
the normal release build. The completed paired sandbox runs preceded those
additional ViewModel changes; they do not provide a phone timing for the new
billing refresh behavior. That needs verification on the updated normal app.

## Regression results and artifacts

* Backend: **140 passed**, 8 existing dependency/deprecation warnings.
* Firebase security rules: **17 passed, 0 failed**; rules unchanged.
* Flutter analysis: **no issues**.
* Flutter suite with tracing: **63 passed**, the same **four pre-existing
  lock-screen visual comparisons failed**. Lock-screen source unchanged.
* New targeted Flutter responsiveness tests: **6 passed**. The startup regression
  measured 2,016 ms of logical frame time before removal and 32 ms afterward.
  That fake-clock measure isolates the route delay, not native device startup.
* Both completed physical sandbox before/after probes passed. Two earlier probe
  configurations were corrected before the completed comparison: Android
  loopback mapping/profile HTTP permission and a loading-button finder whose
  text child disappears while loading. Partial failed runs are not used as the
  completed benchmark results.
* APK signature verification succeeded; installed and prepared release signing
  certificates match. New package is the normal application ID, version 1.0.7,
  code 8, arm64. The normal installed APK was backed up without reading app data.
* `git diff --check` passed.

Prepared APK:
`.local/device-performance/Crompton-PMS-1.0.7-performance.apk` (24,119,365 bytes).
SHA-256:
`647dec4b1a4e7ec1d282e6c5e71789f97a1bdc8118b3aeeddae8018a5dc46e2a`.
The release was built from working-tree changes over `15cf116`; build and
signature metadata are in `.local/device-performance/release-metadata.json`.

Evidence is under ignored `.local/device-performance/`: `before.json`,
`after.json`, installed navigation/cold-start results, hosted billing samples,
paired local/cloud billing measurements, test/build logs and APKs. These private
artifacts are intentionally not added to Git. No live secret was copied into
the source or APK; fixtures were delivered over a transient loopback broker.

Reproducible tooling:

* `scripts/benchmark-installed-navigation.py`: read-only known dashboard routes;
  refuses to control another foreground application.
* `scripts/benchmark-installed-startup.py`: cold-process launch to an interactive
  screen; never enters an app PIN.
* `mobile/integration_test/performance_device_test.dart` and
  `scripts/run-device-performance.py`: isolated package verification, finite
  on-phone probe, scoped correlation traces and automatic USB reverse removal.
* `scripts/benchmark-billing-list.py`: emulator-only seven-module benchmark.
* `scripts/benchmark-cloud-billing.py`: bounded, read-only dedicated development
  Firestore comparison; emits aggregate timings/hashes, never row contents.

## Rollout and remaining acceptance work

The slow live billing path will not inherit the batch optimization until the
backend is deployed. The original phone application remains version 1.0.6;
the prepared APK must also be installed to apply startup, direct billing
delegation and refresh changes. Deploy/install only after explicit approval,
then repeat the same authenticated hosted and device billing tests, confirm
the deployed revision, and check empty/inactive/pending-approval cases.

Immediate button feedback met the 100 ms goal in the completed local phone
probe; confirmed local project creation met one second in all five after
samples. That does not certify every hosted workflow as instantaneous.
Physical attendance/GPS, timesheet/billing mutations, uploads and all-role
approval journeys still require dedicated notification-safe device timing.
No paid infrastructure change is justified by these measurements.

