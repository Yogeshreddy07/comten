# Tester report fixes — 28 October 2026

Reviewed all six pages of the supplied **App3.docx** in the Chrome window.
There are 14 actionable items. The initial local review below was followed by
the user-authorized release preparation described at the end. The rejected performance release remains
reverted; the existing notification registration/delivery fixes are retained.

| # | Tester issue | Result |
|---|---|---|
| 1 | Unable to connect on employee entry | Employee validation and writes go directly to the authenticated backend without a redundant Firestore profile read. Validation has a bounded 30-second wait; provisioning has a single 60-second request. Timeout and malformed-response errors are distinguished. Public activation/recovery requests no longer fetch an unrelated signed-in token. The historical device/network failure itself has not been reproduced. |
| 2 | Incorrect OTP becomes expired instead of showing remaining attempts | Local incorrect attempts retain accurate remaining counts. MSG91 attempt exhaustion is distinguished from actual expiry; the retired reason remains stable on another verification attempt. A provider-retired code cannot truthfully promise another usable attempt. |
| 3 | Resend OTP says to wait | Backend supplies Retry-After and structured seconds; activation UI disables sending until the deadline. Expired/exhausted codes enable replacement immediately, subject to the existing hourly cap. Countdown uses elapsed time, including time spent in the background. |
| 4 | Correct password rejected after repeated wrong passwords | Firebase throttling now has a distinct message with wait/recovery guidance, in both direct mobile auth and the backend alias-login path. Firebase's temporary restriction remains authoritative; a correct password cannot bypass it. |
| 5 | Completed module in Log Working Hours | Work-log project/module pickers use displayed completion status and exclude paid modules. Actionable pickers refresh instead of reusing the app's recent-data cache. Validation and submission reject a stale completed selection. |
| 6 | Missing module completion notification | Explicit completion and approved hours crossing the estimate atomically queue completion alerts for active managers and assigned staff/leader. Repeated saves or later approvals above the estimate do not repeat the alert. Uses the existing module notification deep link and push worker. |
| 7 | Employee review Save remains loading | Validation is bounded; create/update clear saving state in finally even on exceptions. Concurrent save calls are guarded. A failed save advises refreshing before retrying an uncertain write. Existing form/review/identity conflict checks pass. |
| 8 | Already activated account claims OTP sent | Already fixed in current source: activation returns 409 and an explicit already-activated/login message. Existing backend regression passes again. |
| 9 | Remove Attachment from Settings | Removed the My attachments entry from Settings. Existing attachments on business-record screens are retained. |
| 10 | Completed module in Reason for Delay | Picker excludes displayed-completed, paid and inactive modules. Backend rejects delay requests against completed/inactive modules or parents. |
| 11 | Billing Completed module in TL Status Update | Paid modules are filtered from the transport and ViewModel picker. Stale selections are rejected. Work completed but not yet paid can still be submitted for billing. |
| 12 | Cannot deactivate project; pending Captain approval error | Updated 30 October: Captains and Project Controllers deactivate projects directly, including Billing projects, without approval. Deactivation still cascades to modules. Activation remains direct; modules are reactivated individually. Legacy approval actions are retired and no longer shown in the decision queue. |
| 13 | Inactive billing project should move to Completed | Inactive module/parent rows group under Completed and display Inactive, with editing disabled. Stored payment status is preserved; deactivation does not assert full payment. |
| 14 | Change PIN keyboard cannot reopen | Tapping the PIN dots explicitly requests the system keyboard even when Android Back hid it while the field retained focus. PIN obscuring and semantics remain intact. |

## Validation and limits

- Fresh isolated Auth/Firestore emulators on ports 9299/8286: **148 backend
  tests passed**. A final retired-code reason change passed its focused
  verification/resend regression after that full run.
- Final whole Flutter suite: **67 passed, four pre-existing lock-screen pixel
  comparisons failed**. The final activation/employee-validation targeted run
  passed all nine tests, including retired-code resend and server cooldown.
- Flutter analysis: no issues. `git diff --check` passes.
- Hosted read-only `/health` returned OK, development environment and expected
  Firebase project. This does not verify the changed backend; it is still running
  the previously deployed source.
- All test messages/providers are mocked or emulator-only. No live OTP, email,
  push, hosted business write, deployment, phone installation, credential reset
  or database/security-rule migration was performed.
- Four existing original-versus-current app-lock pixel comparisons fail at
  widths 390/800 in light/dark, as already documented in the performance and
  notification release reports. App-lock screen source was not changed here.
- New completion-trigger outbox records and approval transitions are verified
  locally. Actual new-trigger FCM receipt, SMS provider behavior and PIN keyboard
  reopening on a physical phone remain acceptance checks after deployment.

Provider references: [Firebase Flutter error handling](https://firebase.google.com/docs/auth/flutter/errors)
and [MSG91 widget flow](https://docs.msg91.com/otp-widget). These providers own
their throttling/verification limits; their protections have not been relaxed.

Private local logs, emulator configuration and candidate APK are under
`.local/tester-bugs/`. Existing application accounts/data and the current
installed release have not been modified.

## Review APK

Candidate **1.0.9 / versionCode 11**, universal Android release APK:
`.local/tester-bugs/Crompton-PMS-1.0.9-tester-fixes.apk`, 64,018,223 bytes.
Build succeeded; Gradle/AGP/Kotlin upcoming-support warnings remain.

Initial candidate SHA-256: `2f9ff7f7fa51844c0ef113122656fe78e4ca36ff05516641c696cee836ddbaaf`.
The package is `com.crompton.pms.frontend`, Android 7.0+ (minimum SDK 24).
`apksigner verify` passes; signing certificate SHA-256 is
`99207a2b2f5a3f589f7ec6f2109be80cb585d713e828161359f8621da5c71a80`,
matching the previously installed release recorded in the notification report.

The compiled app contains the configured hosted API origin and no unconfigured
API placeholder. A bounded package scan found no environment/signing/private-key
files, private-key marker, or matches against five configured private values.
This is not an exhaustive secret-format audit.

Reproduce from `mobile/`:

```powershell
flutter build apk --release --no-pub --dart-define-from-file=../firebase/development.mobile.json --build-name=1.0.9 --build-number=11
```

This is a review candidate. Backend fixes require deployment together with the
mobile update for the new completion alerts, retry metadata and pending-approval
response. No APK installation, source push or backend deployment was performed.

## Authorized release preparation

The user requested another test run, connected-phone testing, backend push and
an APK handoff. The fresh full backend rerun passed **148 tests**. Flutter
analysis is clean; **67 Flutter tests passed**, with the same four pre-existing
lock-screen visual comparisons failing.

The source version is now **1.0.9+11**. The rebuilt signed universal release APK
is 64,018,223 bytes, SHA-256
`5b274757681b3e44900bd4072c6173d7921bff355c0765372afc2fefa6426d75`.
Package/version/signature and bounded private-value checks passed again.
This rebuilt APK supersedes the initial review artifact at the same local path.

The OPPO CPH2401, Android 14, is detected. `adb install -r` successfully updated
the normal app from 1.0.8/code 10 to 1.0.9/code 11. UID 11177 and original
first-install date are checked before/after; the app was not uninstalled or
cleared. Device acceptance and hosted rollout results are recorded separately
under `.local/tester-bugs/` as they complete.


## Employee review loading follow-up ? 30 October 2026

Next validates contact details once before opening review. Review no longer
repeats that request on entry, on Confirm, or before saving. Confirm is ready
when review opens and opens the existing confirmation dialog immediately; it
never displays a loading spinner. Saving starts directly after dialog Save,
with separate progress feedback and duplicate-tap protection. Backend atomic
identity checks remain authoritative if another account claims the contacts
between Next and Save. Failed saves still refresh field errors and support
validation retry; returning to Edit preserves the form and Next validates again.

The read-only identity-validation response no longer clears and rewrites the
account data cache before Next can navigate. This removes local cache work and
three redundant validation round trips from the successful flow; actual save
completion still depends on backend provisioning and network response time.

Validation: all 10 focused Flutter tests passed across employee validation flow,
employee identity, and request reads. No backend changes, deployment, APK build,
or phone installation were performed for this follow-up.


## Direct project activation/deactivation - 30 October 2026

Per the updated requirement, project deactivation never creates a Captain
approval request, including when a Project Controller deactivates a project
with Billing modules. Activation already required no approval and retains that
behavior. Existing manager-only permissions remain in force. Deactivation still
marks the project and all modules inactive and reconciles assignment access;
billing/payment values are preserved. Project activation does not automatically
activate its modules, matching the existing lifecycle.

Old pending requests cannot block direct deactivation. The retired request
creation and decision endpoints return 410 with guidance to use Projects, so an
old approval cannot deactivate a project again after reactivation. The mobile
approval queue no longer fetches deactivation requests, and the project dialog
no longer states that Captain approval is required. Other approval flows retain
their existing behavior.

Validation: 23 backend lifecycle tests passed against local Auth/Firestore
emulators; nine focused Flutter lifecycle/approval tests passed. Changed Dart
files pass analysis, and git diff --check passes. No hosted deployment, APK
build, phone installation, or live project changes were performed.


## Phone OTP attempt-count follow-up - 30 October 2026

Found and fixed an overbroad provider error classification: any message
containing `expire` was treated as definite expiry. An ambiguous rejection such
as `Invalid or expired OTP` therefore retired the challenge, set its expiry to
zero, and replaced the remaining-attempt count with an expiry message.
Ambiguous invalid/expired responses now follow the incorrect-code counter;
explicit expiry still retires the code. Attempt-limit responses take precedence
when they also mention expiry, preserving the correct lockout reason.

Regression coverage exercises the real provider adapter together with the
Firestore challenge counter: incorrect entries report 4, 3, 2, then 1 attempt
left without changing the original deadline. A correct code then succeeds;
a fifth incorrect entry locks the challenge and cannot be bypassed by submitting
a correct code. A mobile regression checks the visible 2-to-1 sequence and
successful verification afterwards. No attempt limits, expiry durations,
recipient binding, proof validation, or resend protections were relaxed.

Validation: 74 provider/activation tests and three focused phone workflow tests
passed against local emulators with mocked external provider responses; all
four Flutter activation-flow tests passed and changed-test Dart analysis is
clean. The exact live provider response behind the supplied screenshots was
not captured, so this verifies the reproduced classification bug, not a live
SMS reproduction. No live OTP was sent, and no deployment or phone update was
performed. Provider integration reference: https://docs.msg91.com/otp-widget.


## First project load and login code casing - 30 October 2026

The supplied project-load screenshot shows the direct transport's `Firebase is
unavailable` message. The existing HTTP GET retry never handled these direct
Firebase reads, so a temporary connection failure immediately produced the
Retry screen, particularly noticeable with no project snapshot on a fresh
installation. Direct GET operations now retry transient unavailable,
deadline-exceeded, and timeout failures up to three times with short backoff.
Each attempt creates a fresh document-read scope so a previously failed Future
cannot be reused. Persistent failures still surface after the bounded retries;
permission/authentication errors are not retried and writes are never replayed.
The exact phone/network condition on the original installation has not been
reproduced; the missing recovery path is verified with simulated failures.

The login Employee Code field now converts typed/pasted lowercase and mixed-case
codes to uppercase and submits a trimmed uppercase code. Cursor position is
preserved for employee codes. Existing Firebase/backend case-insensitive login
is retained; password characters are unchanged.

Validation: 20 focused Flutter tests passed, covering recovery after three
transient failures, retry exhaustion, immediate permission/auth errors, code
formatting/login submission, and existing project lifecycle/read behavior.
No APK build, phone installation, or deployment was performed.


### Login casing requirement correction - 30 October 2026

The updated requirement supersedes the earlier case-insensitive login note:
employee-code login now requires uppercase codes in both the mobile transport
and backend endpoint. The form automatically uppercases typed/pasted codes,
so normal input submits the canonical uppercase code. Lowercase/mixed-case
codes passed directly to authentication are rejected before password
verification. Passwords remain case-sensitive and are never uppercased.
Firebase's internal account email alias remains lowercase as required by the
existing account scheme; this does not change the accepted employee-code case.

Five focused backend tests pass with mocked authentication; no live account
writes, deployment, or phone update was performed.


## Project milestone and Android tray follow-up - 30 October 2026

The user clarified that the missing alerts are app notifications, not SMS OTPs,
and that progress must use the combined estimate of the whole project. The
new thresholds are 25%, 50%, 75%, and 100% of approved billable seconds divided
by the combined estimated hours of active, non-deleted modules. For example,
one approved hour against a three-hour project crosses 25% only. Pending or
rejected hours do not advance approved progress.

Crossings queue project milestone notifications for active Captains, Project
Controllers, and assigned staff/team leaders across the project's modules.
Project-level markers and the approval transaction prevent duplicate crossings
from repeated saves, simultaneous approvals, or later increases in estimates.
A large approval queues every threshold it crosses. Existing module completion
alerts remain intact. Project milestone cards/pushes carry their percentage and
open Project Details.

The connected OPPO has notification permission granted, its Comten channel at
high importance with banners enabled, and Do Not Disturb off. Current FCM token
validation succeeds. Three labelled phone-only alerts were actually observed
in Android's notification records: foreground (859 ms), background (422 ms),
and stopped app process (937 ms). No hosted notification or business records
were written by those probes. These are individual observations, not latency
guarantees. The 08:34 record is no longer pending but has no device-delivery
receipt, so its historical absence cannot be attributed with certainty.

Two delivery improvements are implemented: failed registration retries while
the app stays open (5/15/30/60-second backoff, cancelled on logout), and outbox
attempt records capture FCM acceptance/device fingerprints and sanitized
failure categories. Acceptance remains distinct from actual phone receipt.
A partial device failure no longer resends to devices that already accepted
the same alert. Existing notification permission/recipient controls and stale
backlog handling are preserved.

Validation: 84 related backend tests passed, followed by the final seven
milestone tests including two additional edge cases. All 33 focused Flutter
regressions passed and changed-file analysis is clean. New backend behavior
has not been deployed. The physical verification and candidate build details
below complete this follow-up.


### Installed candidate and physical milestone verification

Signed candidate **1.0.11 / versionCode 14** is installed on the connected
OPPO CPH2401 using `adb install -r`. UID 11177 and the original installation
date (26 October 2026, 17:42:45) are preserved. No uninstall, app-data clear,
password change, or PIN reset was performed. This APK contains the current
local source fixes from this thread; backend changes remain undeployed.

Four project milestone payloads were generated by approving synthetic work
through the actual local-emulator endpoints against a three-hour project
spread across two modules. They were forwarded through the current push
composition to only the fingerprint-matched connected phone. All four native
tray entries were observed: 25% (813 ms), 50% (781 ms), 75% (422 ms), and 100%
(375 ms). Synthetic project IDs were omitted from the phone-only payloads so
that tapping a test alert safely falls back to Notifications; no synthetic
project exists in the hosted database. No hosted notification/business records
were created or historical notifications requeued. Labelled test alerts are
left for the user to dismiss.

APK: `.local/notification-debug/Crompton-PMS-1.0.11-progress-fixes.apk`,
64,018,147 bytes, SHA-256
`d81a9ba6d26c2f2b202a17b4877f5273e7ea5df44419b35d85462dd4cec40783`.
Signature verification passes and matches the installed signing certificate.
The bounded configured-private-value/package scan passed. Build with:

```powershell
flutter build apk --release --dart-define-from-file=../firebase/development.mobile.json --build-name=1.0.11 --build-number=14
```

The current Flutter SDK requires generated release plugin registration to be
refreshed after test tooling; the successful build includes the dependency/tooling
refresh instead of `--no-pub`. Existing Gradle/AGP/Kotlin future-support warnings
remain. Private build/probe reports are under `.local/notification-debug/`.
Live project milestone generation still requires deploying the backend source;
phone-only FCM tests do not establish that hosted trigger is deployed.


On the updated code-14 APK, background and stopped-process probes also produced
native tray entries (1,031 ms and 875 ms respectively). Future in-place updates
must retain code 14 or use a higher version code; build flags above override
the checked-in pubspec version for this candidate.


### User-requested live phone retest - 30 October 2026

The connected phone was already past its lock screen at the New Notifications
gate. Continue was used without marking notifications read; no password or
PIN was entered or changed by automation. Fresh phone-only FCM probes again
produced native notification records in foreground (359 ms), background
(1,016 ms), and with the app process stopped (875 ms). A screenshot also shows
the native Comten test banner above the app. All four labelled project
milestone payloads were rechecked on the same physical phone: 25% (844 ms),
50% (828 ms), 75% (359 ms), and 100% (797 ms). The first milestone probe stopped
because the app was no longer foreground; rerunning after reopening the app
passed. No hosted business or notification records were modified. This repeats
physical FCM delivery verification; it does not deploy or prove hosted project
milestone generation, whose backend source still awaits deployment.
