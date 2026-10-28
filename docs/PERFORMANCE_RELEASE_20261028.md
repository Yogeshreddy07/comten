# Controlled performance release — 28 October 2026

> This is the performance-release rollback record. A later, separately approved
> notification-only release installed 1.0.8/code 10 and deployed `b3051e2` while
> keeping the rejected performance changes reverted. See
> [the notification follow-up](NOTIFICATION_FIX_20261028.md) for current versions.

The combined 1.0.7 release was deployed, measured, and **rejected** after a
comparable authenticated cold-start test regressed. The authorized rollback
completed on Railway and the test phone. Do not distribute the candidate APK.
The one-second fresh billing target was not achieved.

## Deployed revisions and environment

| State | Source revision | Railway deployment |
|---|---|---|
| Saved pre-release | `15cf1167de16c90aca04b44fa1546b80ab6facfb` | `3ea719d7-5107-47a3-8cf5-b2582dea982f` |
| Tested candidate | `aea79cadfac9fd274d2f76cc4896264f7bb27bb0` | `02e7da7b-9fa6-4a47-9e2d-da3e7444e254` |
| Initial image rollback | Prior saved deployment | `07c4b1e9-6717-4b86-a285-7a4297a565cd` |
| Final restored source | `6c89fafedd007c45933226add766101b20b5467a` | `f2dc4eb5-2b7d-4534-97f4-94817751c08e` |

Final deployment details were rechecked in Railway: **Active**, **Deployment
successful**, and the GitHub source link names `6c89faf`. Its complete Git tree
matches `15cf116`. Reverting and pushing the rejected candidate prevents the
existing main-branch auto-deployment from reintroducing it on a later build.

Railway project `vivacious-dream`, service `comten`, environment **production**;
the application environment is **development**, Firebase project
`crompton-pms-dev-20261015`. The public service is
`https://comten-production.up.railway.app`. Region `ams`, one replica,
`/backend/Dockerfile`, health check `/health`; no variable, region, index,
security-rule or schema changes were made. A final health request returned
`status=ok`, `environment=development`, and the expected Firebase project.

The candidate arrived through the existing GitHub main auto-deploy during
preflight. Its 19-file diff was reviewed against the saved revision. Only
`backend/app/operations.py` changed backend runtime behavior; remaining changes
were the reviewed mobile performance changes, tests, tooling and documentation.
The Dockerfile copies requirements and `app`, excluding test/mobile tooling.
No unrelated runtime change was included. The workspace was clean after the
rollback, before writing these reports.

## Installed Android version and data preservation

The OPPO CPH2401, Android 14, was updated in place from 1.0.6/code 7 to the exact
tested **1.0.7/code 8** APK. Candidate SHA-256:
`647dec4b1a4e7ec1d282e6c5e71789f97a1bdc8118b3aeeddae8018a5dc46e2a`.

After the startup regression, prior source `15cf116` was built and installed in
place as **1.0.6-rollback/code 9**. This is the last verified installed version.
Rollback APK SHA-256:
`6dc1cd0a420de05acce069d1eef3489b24684f0bf14714bf79d479e41b29804b`.
Both packages use the original application ID `com.crompton.pms.frontend` and
the installed signing certificate SHA-256
`99207a2b2f5a3f589f7ec6f2109be80cb585d713e828161359f8621da5c71a80`.

Every normal-app installation used `adb install -r`. UID **11177** and first
install date **2026-10-26 17:42:45** were preserved. The normal app was never
uninstalled or cleared. No private app database or credential contents were
extracted. The candidate initially showed Welcome, also seen in the original
signed-out tests; the user logged in manually with the existing account.
Subsequent candidate/comparison/rollback startup runs reached the existing
account's app-lock screen. No PIN was entered or changed by automation.
These observations support preservation; they are not a record-by-record audit
of private app storage.

On final resumption, USB listed no connected device, so a further live package
recheck was unavailable. The successful rollback installation and completed
code-9 startup measurements below remain the last physical-device evidence.
Any future approved Android release must use a versionCode **greater than 9**.

## Before/after performance

All values below are milliseconds. P95 is nearest rank; with at most ten
samples it equals the maximum and is not a reliable population-tail estimate.
Candidate measurements describe the temporarily deployed candidate, not the
final restored release.

| Measurement | Before n | Before median / P95 / max | Candidate n | Candidate median / P95 / max |
|---|---:|---:|---:|---:|
| Authenticated hosted billing, fresh response | 5 | 9,632.6 / 9,975.9 / 9,975.9 | 10 | **2,096.0 / 2,432.7 / 2,432.7** |
| Projects navigation | 3 | 697.1 / 751.0 / 751.0 | 10 | 662.1 / 826.4 / 826.4 |
| Employee Management navigation | 3 | 754.8 / 1,242.3 / 1,242.3 | 10 | 682.4 / 1,003.4 / 1,003.4 |
| Billing Management navigation | 3 | 10,424.0 / 10,599.0 / 10,599.0 | 10 | **644.8 / 738.9 / 738.9** |
| Activities navigation | 3 | 710.1 / 770.3 / 770.3 | 10 | 656.2 / 817.2 / 817.2 |
| Authenticated cold start to app lock, same account | 3 | **5,467.6 / 6,531.2 / 6,531.2** | 3 | **7,911.3 / 9,219.0 / 9,219.0** |

Navigation values are automation-inclusive observed upper bounds. Billing can
show retained content while refreshing; the 645 ms screen result does **not**
mean a fresh server response arrived within one second. Each billing screen
was left open three more seconds and checked for delayed errors. Forty valid
navigation measurements completed. A foreground guard interrupted one run
after six complete cycles; the remaining four cycles were resumed. No app
crash/ANR was found for that interruption.

Hosted billing improved by approximately 78% in these samples, but its median
was still 2.10 seconds. These authenticated hosted requests were from the
workstation; the separate navigation measurements were on the physical phone.

The startup comparison used prior source with the same package, certificate,
account and app-lock destination, temporarily versioned `1.0.6-compare/code 8`.
Candidate samples were 7,505.1, 9,219.0 and 7,911.3 ms; prior-source samples
were 6,531.2, 5,396.7 and 5,467.6 ms. The observed ranges did not overlap.
Sample counts are small, but the result was sufficient to trigger the user's
conservative rollback gate. The cause is not yet established.

After installing the final rollback code 9, three further app-lock launches
were 5,336.1, 4,930.0 and 5,284.6 ms: median **5,284.6**, P95/max **5,336.1**.
The older 3.3-second signed-out Welcome baseline and the 252 ms in-process
emulator-probe initialization are different scopes and cannot be used to
claim improved authenticated native cold startup.

One post-rollback authenticated hosted billing smoke request took **11,045.1
ms**, with seven correct rows. This confirms restoration of the legacy path;
one sample does not establish its latency distribution. The billing speedup
is no longer deployed.

## Project submission and immediate feedback

The user declined hosted synthetic project creation. No hosted project was
submitted or removed for this test, so real-world hosted submission latency
remains **unverified**.

A separate phone sandbox package, using only local Firebase/API emulators,
tested the actual confirm button, loading frame and authoritative created
module before success. The candidate passed all five submissions:

| Local-emulator phone measurement | n | Median | P95 | Maximum |
|---|---:|---:|---:|---:|
| Confirm tap to loading frame | 5 | 19.06 | 56.99 | 56.99 |
| Confirm tap to confirmed success frame | 5 | 571.55 | 978.57 | 978.57 |

Immediate feedback met 100 ms in this sandbox. It does not certify all hosted
buttons or workflows. The sandbox package was removed after testing; the
normal package and its data were kept. No deliberate hosted business-data
mutation or test SMS/email/push dispatch was performed. Normal account/login
housekeeping is separate from business writes.

## Correctness, authorization and regression checks

- Backend: **141 passed**, eight dependency/deprecation warnings.
- Firebase security rules: **17 passed**, zero failed; rules unchanged.
- Flutter analysis: **no issues**.
- Flutter suite: **63 passed**, the same four pre-existing lock-screen visual
  comparisons failed. No lock-screen source change was included.
- Ten candidate hosted billing calls: all HTTP 200, seven rows each, zero
  errors; every response exactly matched the independent legacy reference.
  Four rows covered inactive/noneditable conditions.
- Unauthenticated billing returned 401. Employee login succeeded and employee
  billing returned 403. The controller account/profile was accepted.
- No live pending-approval row was present. Pending, approved, missing and
  dangling request cases, inactive parents and empty billing were verified by
  isolated regression tests. Live mutations/approval transitions were not
  exercised; this report does not certify every live approval journey.
- Candidate source filtered modules to BILLING before enrichment, batched
  distinct project/leader/lock references, and batched referenced requests.
  Regression assertions verified two batches for pending-request fixtures and
  no enrichment documents for empty results. Source and hosted equality checks
  confirm removal of per-row sequential enrichment in the candidate; no
  hosted database-read tracing was enabled. Rollback restores the old reads.
- Final rollback smoke: health OK with expected project; unauthenticated 401;
  controller login/profile valid; authenticated billing 200 and exact legacy
  response match. No business writes were needed.
- Credential scans covered 648 source files plus the candidate APK, using
  patterns and known private values; no findings. APK contents were checked
  for environment/service-account/signing-key files, and signature/hash
  checks passed. This bounded scan is not a claim that all possible secret
  formats can be detected.
- `git diff --check` passed before rollout. The final source revert was a
  normal commit/push, without force pushing or changing infrastructure.

The additional empty-list test was preserved in a named Git stash and private
artifact before reverting; it was not reapplied to the restored runtime tree.

## Rollback and recommendation

Rollback succeeded through the saved Railway deployment, followed by a source
revert to keep subsequent main-branch builds on the restored behavior. The
normal Android app was restored through a signed, higher-version-code build
of the saved source. No database migration, security-rule change or business
record rollback was required.

**Do not ship the combined 1.0.7 release.** Investigate and resolve the
authenticated cold-start regression, then repeat comparable device startup
and billing measurements on a new reviewed candidate. A separately reviewed
backend-only optimization could be considered later; no further rollout was
performed. Fresh billing still needs additional work to approach one second.
Hosted project submission, live approval mutations and other role-specific
write journeys remain outside the completed acceptance evidence.

## Evidence

Private artifacts remain under ignored `.local/controlled-release/`:
predeployment/release hashes, candidate hosted samples, forty navigation
samples, paired startup JSON, code-9 startup confirmation, local sandbox
probe, regression logs, credential-scan summary, rollback APK metadata,
rollback result and hosted smoke. The original investigation artifacts remain
under `.local/device-performance/`. Neither secrets nor private row payloads
are included in this report.

Rollback proof: `.local/controlled-release/rollback-railway-proof.jpg`.
The earlier investigation is retained in `PERFORMANCE_DEVICE_20261028.md` as
historical pre-release context; this report supersedes its rollout status.
