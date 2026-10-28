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
| 12 | Cannot deactivate project; pending Captain approval error | Billing projects still require Captain approval. Repeated Deactivate returns an informational pending result and creates no duplicate request. A new request atomically queues a Captain alert; its in-app tap opens Approvals, and the queue refreshes on entry. Approval still cascades deactivation to child modules. |
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
