# Android notification investigation — 28 October 2026

**Outcome: fixed, deployed and verified on the connected phone after explicit
approval.** Railway is running notification revision
`b3051e281c01e6d9a32d862b2a624ebf43ead97c`, deployment
`fe7cb8ab-17e4-40c4-9ead-dcac17bbf64a`. Android is running **1.0.8/code 10**.
Foreground, background and stopped-process alerts were physically observed
in Android's notification records. Tapping a cold-start alert preserved the
existing PIN gate and left the alert in the tray.

## Findings

Three reproducible gaps were found in the shared push path:

1. Device registration ran only when the dashboard was constructed. After
   authentication, unread notifications and walkthrough screens can precede
   that dashboard indefinitely. The connected phone was observed on the
   unread-notification gate after unlocking.
2. Registration had no lifecycle retry. A failed initial token lookup could
   also prevent the token-refresh listener from being installed. A failed
   repository registration response was silently ignored.
3. Backend `_send_push` returned success when the recipient had zero device
   tokens, or when all tokens were rejected as unregistered. `deliver_push`
   consequently cleared `pushPending` despite sending to no device. Two new
   regressions reproduced this against the prior implementation.

These are confirmed code defects. They do not establish which individual
historical alert failed at which stage: existing records lack per-device
delivery receipts, and FCM acceptance alone is not physical tray delivery.

## Live checks (read-only, no notification delivery)

- Railway push gates `ALLOW_REAL_MESSAGES`, `FCM_DISPATCH_ENABLED` and
  `FCM_REGISTERED_RECIPIENTS_ENABLED` are true; explicit FCM allowlist is empty.
  The service uses the expected dedicated development Firebase project.
- Bounded inspection found 150 notification records: 123 already skipped as
  stale, 27 without a skip marker, none pending. A missing skip marker is not
  a delivery receipt. Historical records were not requeued.
- Three registered tokens were inspected. FCM **dry-run** validation accepted
  two and returned `UnregisteredError` for one. No message was delivered by
  these validations. The expired token was not manually deleted, and it was
  not proven to belong to the connected phone.
- The OPPO test phone has Android notification permission granted. The
  `comten_notifications` channel has importance 4 (high), is not deleted,
  and enables vibration, badges, banner and icon. Permissions/channel blocking
  therefore do not explain the observed problem on this phone.
- Installed version during inspection remains `1.0.6-rollback`, code 9. The
  normal app was opened and its gate's Continue action used; no notification
  was marked read and no business workflow was submitted by automation.

Those bullets describe the initial diagnosis. The approved update and finite
delivery tests below were performed afterwards.

## Focused fix

- Start registration during authenticated navigation, before unread and
  walkthrough routing. Do not block navigation on push/network setup.
- Retry on app resume, coalesce overlapping sync calls, and install refresh
  listening before the initial token lookup. Failed repository registration
  remains retryable and produces a non-sensitive diagnostic.
- Logout invalidates pending sync generations, stops lifecycle retries and
  waits for pending registration before token removal. Account UID guards
  remain in place.
- Keep fresh notifications pending when no device accepts them. Existing
  recipient gates, transaction claims, retry age limit and expired-token
  cleanup remain intact.
- Use the full notification ID as the Android tag and a stable 32-bit local
  ID, preserving distinct alerts and reusing the same tray entry on repeated
  foreground delivery. Set backend `sticky=true` and foreground
  `autoCancel=false`; tapping does not automatically remove the alert. Users
  can still swipe or clear it. No timeout or forced ongoing notification was
  introduced.

All notification types share these paths. No billing, approval decision,
authentication policy, security-rule, startup route timing or infrastructure
configuration change is included. The rejected performance release remains
reverted.

## Validation

- Backend: **140 passed** on fresh isolated Firestore/Auth emulators. The two
  new missing/expired-device tests failed against the prior sender and pass
  with the fix. FCM sends in tests are mocked.
- Firebase rules: **17 passed**, zero failed; rules unchanged.
- Flutter analysis: **no issues**.
- Four targeted Flutter tests passed: native Android tray request, stable
  notification identity/retention, no empty alerts, overlapping sync/resume
  recovery, and logout cancelling a late permission result (the tray test
  covers several assertions).
- Full Flutter suite before the last two lifecycle tests were added: **59
  passed**, the same four pre-existing lock-screen visual comparisons failed.
  The final targeted run includes both additional lifecycle tests.
- An initial backend run reused an occupied emulator and encountered three
  duplicate-fixture failures. It was superseded by the clean 140-pass run on
  new ports. An early display test lacked native plugin registration in its
  test harness; the harness was corrected before the completed passing run.
- `git diff --check` passed.

## Approved release and physical verification

The signed **1.0.8/code 10** release was built at
`.local/notification-debug/Crompton-PMS-1.0.8-notifications.apk` (24,119,365 bytes).
Final SHA-256: `a045260b5e09a44e19faee299e1ba0abf72d901479885ab151f0816b26b7dd97`.
Its certificate matches the installed application, and the private-value scan
of 639 tracked source files plus APK entries found no exposed private values
or private-key/environment/signing files in the APK. The bounded scan does
not establish that every possible secret format is detectable.

The user explicitly approved notification-only deployment, in-place update,
and a labelled phone-only test after reviewing the local results. Only five
notification runtime/test files were committed and pushed; the unrelated
historical performance reports were excluded. Railway's final deployment
details show Active, Deployment successful, and the exact `b3051e2` GitHub
source link. Health returns 200 with the expected development Firebase
project; unauthenticated billing still returns 401. No variables changed.

The APK was installed with `adb install -r`. Version 1.0.8/code 10, UID
**11177** and first install date **2026-10-26 17:42:45** were verified. Pulling
the installed APK confirmed an exact SHA-256 match to the reviewed artifact.
The normal app was never uninstalled or cleared. The existing account and
app lock continued to work; no password or PIN was reset. Any future update
must use versionCode greater than 10.

To address only this phone, the release logs a SHA-256 fingerprint on successful
registration, never the token. The on-phone fingerprint was matched to exactly
one server registration. Registration succeeded **while still on the unread
gate, before the dashboard was constructed**, exercising the fixed path.

Three clearly labelled synthetic alerts were sent to only that verified token:

| Phone state at send | Actual Android tray entry | AUTO_CANCEL flag | Observed send-to-record time |
|---|---|---|---:|
| Foreground, unread-notification gate | Present | Off | 437 ms |
| Background, home screen | Present | Off | 828 ms |
| App process absent before send (`am kill`, not force-stop) | Present | Off | 922 ms |

These are one observation per state, including send/ADB polling; they are not
latency distributions or an every-notification delivery guarantee. The finite
sender used the deployed revision's `_send_push` composition with its device
enumeration narrowed to exactly this phone. It sent directly through FCM;
it did **not** create a hosted notification/business record or exercise a new
live business trigger through the Railway outbox. Backend outbox retry and
recipient/authorization behavior were verified by the emulator regression
suite and the deployed source revision, rather than a cloud business mutation.

The first cold-tap attempt selected Android's grouped-notification presentation
without opening the activity. Selecting the explicit synthetic child row
then opened the app-lock screen. After the existing PIN gate, the pending
notification opened the Notifications screen without an error banner. All
three alerts, including the tapped alert, remained in Android's tray. No app
crash was recorded. The clearly labelled test alerts are left for the user
to dismiss; no historical backlog was replayed or business workflow invoked.

Regression results remain 140 backend passes, 17 rules passes, four targeted
Flutter passes, and clean final Flutter analysis. The existing four lock-screen
visual failures remain documented above. Source/runtime changes are confined
to notifications; the rejected performance optimizations remain reverted.

The saved pre-notification Railway deployment is
`f2dc4eb5-2b7d-4534-97f4-94817751c08e`, source `6c89faf`; the previous signed
code-9 APK/source remain backed up. No notification rollback was needed. An
Android source rollback after code 10 would require a signed higher-code build
of that saved source rather than uninstalling or clearing the normal app.

Release proof: `.local/notification-debug/railway-notification-release.jpg`.
Detailed private results include `candidate-metadata.json`,
`phone-registration.json`, `phone-foreground.json`, `phone-background.json`,
`phone-terminated.json` and `cold-tap-verification.json`.

The unchanged one-hour pending-push age limit deliberately skips old backlog.
This fix does not promise every historical alert will be replayed, or that
Android will display notifications after force-stop/permission denial.
Firebase also documents that notification payloads are collapsible while
undelivered: offline delivery of every event is not guaranteed. Durable
notification records remain available inside the application.

Provider behavior reference: [Firebase Flutter receive documentation](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages),
[FCM collapsible messages](https://firebase.google.com/docs/cloud-messaging/customize-messages/collapsible-message-types).
Private evidence is under ignored `.local/notification-debug/`; no credentials,
device tokens, PINs or user message contents are included in this report.
