# Crompton PMS

Email activation now uses **employee code → registered-email OTP → password setup
→ login**, with no temporary password or required SMS step for new email-verified
accounts. Forgot Password also uses email OTP. See [email setup and delivery
checks](docs/email-otp.md) for Resend testing switches and account migration behavior.

Railway backend setup: [step-by-step deployment guide](backend/RAILWAY.md).
Use repository `Yogeshreddy07/comten`, service root `/backend`, its detected
Dockerfile, and health check `/health`. Private settings can be exported locally with
`scripts/export-railway-variables.py`; its output stays in ignored `.local/`.

## Hosted tester build — 23 October 2026

The development backend is deployed on Railway at
**https://comten-production.up.railway.app**. Despite Railway's `production`
environment/domain label, the application uses `ENVIRONMENT=development` and
the dedicated `crompton-pms-dev-20261015` Firebase project. Project:
[Crompton Railway service](https://railway.com/project/4a9cfa7b-5a6a-41f5-b5ca-526d4f667cb9/service/f5a3e27b-9840-49e6-8a10-0001c8ca512b).

The new **1.0.1+2 universal Android debug APK** in ignored
`.local/tester-handoff-2026-10-23/` embeds the public HTTPS API URL. Android 7.0+
is supported. Its signature, package version, compiled Firebase/API settings,
and absence of saved backend secrets/test passwords were verified.

Current checks: **84 hosted API/report/permission/private-R2 checks passed**;
**9 hosted employee provisioning/lifecycle checks passed**; **35 Flutter tests
passed** and analysis reports no issues. The storage probe's object was deleted;
the one synthetic provisioning account was soft-deleted and disabled. Evidence
is in ignored `.local/railway-deployment/`. The previous 70-test backend rerun
remains recorded in `.local/railway-backend-tests.log`.

Use Log In with `CAP001`, `PC001`, `TL001`, or `EMP001` and the shared tester
password in `.local/development-logins.json`. `EMP001` now has the owner's
approved test phone (ending 9450), verified through actual hosted SMS OTP.
The other synthetic accounts retain their preverified placeholder contacts.

**SMS OTP is enabled for the exact approved test recipient.** Actual receipt,
MSG91 verification, the hosted verification endpoint, Firebase custom-token
exchange, app activation confirmation, verified profile and consumed-code
replay rejection passed on 23 October. Anonymous requests, an unenrolled phone,
resend/rate limits and malformed codes were also rejected. Evidence without
codes/tokens is in ignored `.local/railway-deployment/otp-live-results.json`.
The widget needed Web integration for backend requests and India + Netherlands
request-origin countries (Railway runs in Amsterdam). No APK change was needed.
Provider failures now log only a safe diagnostic category, not response bodies.

**Ready for tester evaluation; full device acceptance is not certified.** Email
and FCM dispatch remain off. A working email Agent and installation/launch of
this APK on tester devices remain unverified. No Android device is connected
for fresh physical testing. New accounts need an admin-assigned real phone;
each authorized tester number must be added to `APPROVED_SMS_RECIPIENTS`.
The backend still requires authentication, enrolled-phone matching and rate
limits before dispatch. The existing 1.0.1 APK uses these hosted SMS changes.

Re-run the finite hosted checks (one synthetic storage upload/download/delete;
no SMS/email):

```powershell
.\.venv\Scripts\python.exe scripts/verify-hosted-backend.py --url https://comten-production.up.railway.app
```

## Historical tester handoff — 22 October 2026 (API blocker resolved above)

The four existing synthetic development accounts (`CAP001`, `PC001`, `TL001`,
`EMP001`) now share the tester password saved in ignored
`.local/development-logins.json`. Actual Firebase password login and matching
role claims passed for all four. Placeholder phones are respectively
`9000000001`, `9000000002`, `9000000003`, `9000000004`; never dispatch to these
placeholders. Their pre-existing synthetic `phoneVerified` flags remain set for
login testing; these flags are not evidence of real OTP delivery.

**No full-testing green signal:** no public HTTPS FastAPI origin has been
provided, SMS/email dispatch remains disabled, and real OTP receipt is
unverified. Testers on their own networks need a publicly hosted API for OTP,
account provisioning and other privileged operations. The candidate debug APK
uses development Firebase directly for supported operations and an explicitly
unconfigured `.invalid` API placeholder; it is a limited preview, not a complete
internet-ready testing build. No physical device is currently connected.
An admin must assign the actual enrolled phone before the OTP step; activation
does not let the user replace it with an arbitrary number.

Current backend rerun: **63 passed** (`tests/tester-backend-results.xml`).
Flutter analysis is clean; **35 Flutter tests and 12 Firestore rule tests pass**.
The new universal debug APK (Android 7.0+, approximately 202 MiB) and tester
instructions are in ignored `.local/tester-handoff/`. APK signature and compiled
configuration were verified; its SHA-256 is in that folder's `build.json`.
Account results without passwords: `tests/tester-accounts.json`.
`scripts/prepare-tester-accounts.py` resets only the four known synthetic
development identities, takes `PMS_TESTER_PASSWORD` from the environment, and
verifies real Firebase login/role claims without sending messages.

The historical results and release blockers below retain their original dates.

Development application in `D:\Client\Comten\Crompton PMS`. Flutter uses Firebase Authentication/direct Firestore; privileged operations and the Next.js reporting website use FastAPI. Existing screens, website HTML/CSS, assets and navigation are retained. No original-project files, historical data, production deployment or billing settings were changed. No SMS/email was sent; finite FCM probes targeted only the connected synthetic development phone.

**Development workflows pass. Release acceptance remains blocked by native/device and external setup. Untested interactions are not certified complete.**

## Working feature checklist

| Feature | Actual verification |
|---|---|
| Four roles | 39 browser UI checks plus physical Android navigation/login/logout for all four roles. Captain/Controller checkpoints retained; Team Leader Settings/logout and Employee checks completed without replaying those roles. Exhaustive physical verification of every form/action is not certified. |
| Employees | Provisioning, unique contact login, edit, activation/deactivation, sensitive-role restrictions and clearing verification when a phone number changes. One-time temporary-password dialog; invitation/activation email queue respects recipient gates; live email disabled. |
| Projects/modules | Assignments/pickers, leader/member validation, response contracts, progress, cascading deactivation, approved budget changes, stale-request rejection and pending-timesheet reassignment. |
| Attendance/timesheets | Physical non-mocked location fix (reported accuracy 34.6 m), native SDK check-in/one-minute submission, actual OS permission denial/retry/grant, fresh-location checkout through the normal UI, and a 15-minute submission through the physical Employee form. Both entries approved; 16 minutes matched native totals and website exports. No elapsed attendance was manufactured. |
| Billing/approvals/notifications | Native SDK/API leader approval, billing and Captain budget approval pass. Actual foreground/background/terminated FCM delivery and My Timesheets deep links pass; cold notification tap respects PIN. Logout removes registration; subsequent login rotates the token. |
| Isolation/offline | Scoped queries, blocked unrelated staff/module access and privileged writes, encrypted Hive reopen/account/version isolation, bounded offline profile reads, reconnection and logout. Writes require connectivity. |
| Website | Six report families, charts/tables, navigation, Excel downloads; Captain/controller allowed, team leader/employee/anonymous rejected. |
| Visuals | 30 prior website comparisons preserved. Twelve Flutter welcome/login/portrait-PIN comparisons at 390/800 widths in light/dark match the preserved reference. Physical dashboard rotation and landscape PIN scrolling/unlock pass. Exhaustive dialog/device typography parity is not certified. |

## Executed results

| Check | Result | Evidence |
|---|---|---|
| FastAPI | **63 passed** | `backend/tests/` |
| Firestore Rules | **12 passed**, multiple assertions; development-only rules/index deployment | `firebase/rules.test.mjs` |
| Fresh cloud journey | **24 passed** | `tests/cloud-journey.json` |
| Real role/query/index checks | **22 passed** | `tests/cloud-query-results.json` |
| Flutter analysis/tests | **No issues; 35 passed**, including dashboard/PIN layout regressions and 12 original/copied pixel comparisons | `mobile/test/`, `.local/android-flutter-tests.log` |
| Flutter browser UI | **39 passed + 12 mocked attachment checks**, no recorded failures | `tests/visual/mobile/ui-results.json` |
| Next.js | **Typecheck, lint, production build passed** | `web/` |
| Website cloud navigation/exports | **13 passed; 6 workbooks / 338 cells verified**, including fresh workflow totals | `tests/visual/website/cloud-workflow-results.json`, `tests/exports/cloud/verification.json` |
| Website physical-workflow exports | **13 passed; 6 workbooks / 388 cells verified**, including the phone's 16 approved minutes | `tests/android/website-workflow-results.json`, `tests/exports/android/verification.json` |
| Website authentication | **8 passed; 12 mocked file UI checks** | `tests/visual/website/auth-results.json` |
| Android | **Updated normal development APK built, installed and restored**; SHA verified; installed OS backup flag disabled. No release AAB. | `mobile/build/app/outputs/flutter-apk/app-development-debug.apk`, `tests/android/build.json` |
| Physical Android | **Core workflow PASS:** OPPO CPH2471, Android 12; resumed native integration passes plus eight normal-app control cases. Positive biometric automation remains NOT TESTED; owner reports it working. | `tests/android/acceptance.json`, `tests/android/remaining-results.json`, `tests/android/device-results.json` |

The Android build emits upcoming Gradle/AGP/Kotlin support warnings; backend tests emit dependency deprecation warnings. Executed checks pass.

Physical testing on 16 October 2026 found/fixed narrow-dashboard overflow, premature open-shift rejection on a phone clock approximately four minutes behind the server, and a landscape PIN screen whose lower keypad rows were unreachable. Open shifts retain Firestore's server-time enforcement; closed shifts retain authoritative timestamp checks. The PIN screen scrolls only when needed; its portrait pixels match the reference. Physical reruns pass. The normal app is restored at Welcome, test instrumentation is stopped, and this phone's leftover synthetic token registration was removed.

| Physical scenario | Status / scope |
|---|---|
| Team Leader Settings/logout; Employee login/dashboard/navigation | PASS |
| GPS permissions, accuracy, check-in/check-out | PASS; 34.6 m reported fix, OS non-mocked; permission denial/allow and UI checkout observed |
| Employee work-log form | PASS; 15-minute minimum enforced, 15-minute entry committed through direct Firestore |
| FCM foreground/background/terminated delivery and deep links | PASS; actual receipt/tap, cold-start PIN gate and My Timesheets destination |
| Token lifecycle | PASS; logout deletion, replacement token after login, account ownership and cleanup |
| Background/force-stop/process restart | PASS; identity restored only after PIN unlock |
| Biometrics | Hardware/enrollment PASS; owner reports working. Automated positive authentication/restart NOT TESTED: no successful prompt completion observed by driver |
| Offline cache/reconnection/logout | PASS for SDK-offline encrypted profile read, reconnection and subsequent logout; airplane-mode/offline restart/logout NOT TESTED |
| Rotation/keyboard/layout | PASS for dashboard/landscape PIN and real keyboard form entry; exhaustive screen/text-size/device matrix NOT TESTED |
| Remaining role actions | Native SDK/API approval/billing/budget/report consistency PASS; exhaustive physical testing of every remaining role form/dialog NOT TESTED |

Terminated FCM was tested with a cached process killed and PID absence verified before sending. Force-stop was tested by explicitly reopening the app; delivery while force-stopped is not claimed.

Physical run commands (unlocked phone, USB debugging authorized, cloud API on 8007):

```powershell
Set-Location 'D:\Client\Comten\Crompton PMS'
.\.venv\Scripts\python.exe -m pip install -r scripts/requirements-device.txt
# Existing ignored synthetic credentials/workflow checkpoint are required.
# Resume the saved native protocol; do not recreate completed test data:
.\.venv\Scripts\python.exe scripts/test-android.py --device ZPQKY94PCMFMTSKN --resume --workflow-only
cd web
node tests/workflows.cjs --cloud --android
cd ..
.\.venv\Scripts\python.exe scripts/verify-exports.py --android
# Restore the normal APK after an integration-test entrypoint:
adb -s ZPQKY94PCMFMTSKN install -r -t mobile/build/app/outputs/flutter-apk/app-development-debug.apk
adb -s ZPQKY94PCMFMTSKN reverse tcp:8007 tcp:8007
adb -s ZPQKY94PCMFMTSKN shell am force-stop com.crompton.pms.frontend
adb -s ZPQKY94PCMFMTSKN shell am start -n com.crompton.pms.frontend/.MainActivity
```

The native runner stops on disconnection or a 20-minute deadline, checkpoints stages and retains prior attempts under `tests/android/runs/`. Public `workflow-checkpoint.json` contains IDs/stage; its private credential counterpart stays in ignored `.local/`. Normal-app cases save each result/event in `remaining-results.json` and `.local/android-controls.log`; initial harness timing/reminder/fixture errors are superseded only by successful affected-case reruns. Final native protocol exit code is zero. To attempt the remaining owner-assisted biometric case from the restored Welcome screen, run `scripts/test-android-remaining.py --device ZPQKY94PCMFMTSKN --case login`, then the same command with `--case biometric`, using `.venv/Scripts/python.exe`.

## Genuine release blockers

- **Device acceptance:** positive biometric automation, fully offline restart/logout, native file picker, actual backup/device transfer, Android 13+ notification permission behavior and exhaustive role-form acceptance remain unverified. The connected Android 12 phone does verify the core GPS/FCM/lifecycle/work-log flows above.
- **App Check:** physical debug enrollment and on-device debug token issuance pass. Release SHA enrollment, Play Integrity and enforcement with a signed release remain untested.
- **Release identity/hosting:** private upload keystore/signing properties and a working HTTPS FastAPI origin are missing. Release builds reject missing cloud/signing/HTTPS configuration and never use debug signing. No release AAB was produced.
- **Providers:** MSG91 SMS delivery remains untested. ZeptoMail's existing Agent is shut down; replacement Agent/key and account validation/credits remain pending. Private R2 passes real API/Flutter/website and physical native upload/download/cleanup checks; its native OS picker is untested. Routine message dispatch stays disabled; finite actual FCM development-phone delivery was verified.

## Run locally

Tools used: Python 3.12, Node 22, Java 21, Firebase CLI 15.33.0, Flutter 3.47.6 and Android SDK. Start from this project; use separate terminals for long-running commands.

```powershell
Set-Location 'D:\Client\Comten\Crompton PMS'
powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1 -Mobile
# Stop only processes recorded by this project:
powershell -ExecutionPolicy Bypass -File scripts/stop-local.ps1
```

Manual alternatives, from the root in separate terminals:

```powershell
cd firebase
firebase emulators:start --only auth,firestore --project demo-crompton-pms
```

```powershell
.\.venv\Scripts\python.exe scripts/seed.py
cd backend
..\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8006
```

```powershell
cd web
npm run dev
```

```powershell
cd mobile
flutter build web --debug --no-wasm-dry-run
python -m http.server 3008 --bind 127.0.0.1 --directory build/web
# Or run on an Android emulator:
flutter run --dart-define=USE_EMULATORS=true --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=BASE_URL=http://10.0.2.2:8006/api
```

Website: `http://127.0.0.1:3000`; API docs: `http://127.0.0.1:8006/docs`; Flutter preview: `http://127.0.0.1:3008`; emulator UI: `http://127.0.0.1:4006`. Emulator accounts: `CAP001`, `PC001`, `TL001`, `EMP001`; password `SyntheticPass123!`. Local-only phone code: `123456`; email recovery uses the fixed emulator-only code `123456`; only HMAC challenges are stored. No messages are sent. Both launchers explicitly reset dispatch flags; local startup also pins the demo project/emulator endpoints.

## Dedicated development Firebase

Project **crompton-pms-dev-20261015**, Firestore **asia-south1**, billing disabled. Public options: `firebase/development.web.json`, `firebase/development.mobile.json` and native `google-services.json`. Firebase Storage is unused; attachments use R2.

```powershell
# From root; launcher forces live messaging off:
powershell -ExecutionPolicy Bypass -File scripts/start-development.ps1
# Separate terminal:
cd mobile
flutter run --dart-define-from-file=../firebase/development.mobile.json
flutter build apk --debug --dart-define-from-file=../firebase/development.mobile.json
```

Cloud API docs: `http://127.0.0.1:8007/docs`. ADC, synthetic logins and generated recovery HMAC key stay in ignored/access-restricted `.local/` files. Backend provider secrets belong in ignored environment files; see `.env.example`.

Once the actual HTTPS origin and private signing properties (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) are supplied through ignored `mobile/android/key.properties` or `PMS_ANDROID_KEY_PROPERTIES`:

```powershell
cd mobile
flutter build appbundle --release --dart-define-from-file=../firebase/development.mobile.json --dart-define=BASE_URL=$env:PMS_RELEASE_API_URL
```

This targets development Firebase and does not authorize production publication.

## Re-run validation

With services running, from root:

```powershell
.\.venv\Scripts\python.exe -m pytest backend/tests -q
cd firebase
npm test
node cloud-read-probe.mjs
cd ../mobile
flutter analyze --no-pub
flutter test --no-pub
cd ../web
npm run typecheck
npm run lint
npm run build
node tests/auth.cjs
node tests/workflows.cjs
node tests/mobile-ui.cjs
```

Fresh cloud workflow (creates bounded synthetic data; never messages), with cloud API 8007 and website 3000 running:

```powershell
cd mobile
flutter build web --debug --target integration/journey_probe.dart --output build/journey --no-wasm-dry-run --dart-define-from-file=../firebase/development.web.json
python -m http.server 3009 --bind 127.0.0.1 --directory build/journey
# Separate terminal from project root:
cd web
node tests/journey.cjs --cloud
node tests/workflows.cjs --cloud
cd ..
.\.venv\Scripts\python.exe scripts/verify-exports.py
```

Visual comparison: run `.\.venv\Scripts\python.exe scripts/reference-site.py` from root, then `node tests/visual.cjs` from `web/`, followed by `.\.venv\Scripts\python.exe scripts/compare-visuals.py` from root (Pillow is installed in the existing virtual environment). The baseline is the preserved copy inside this project; the original project is never accessed. Screenshots/results are under `tests/visual/`.

## Provider integration status â€” 16 October 2026

| Service | Credentials loaded | Configuration complete | Live verification | Remaining blocker |
|---|---|---|---|---|
| MSG91 | Yes, from ignored root `.env`; dedicated Widget ID matches | Protected Widget flow implemented | Read-only balance authentication passed; saved key matches Yotechsys/comten on the dedicated widget; live verification rejects a synthetic invalid token. SMS delivery NOT TESTED | Exact test recipient/charge approval; actual OTP receipt and successful verification |
| ZeptoMail | Existing token loaded; legacy key name and dashboard prefix supported | `tech@virtualfinpros.com`, verified `virtualfinpros.com`, India origin configured | Domain/DKIM/bounce verification confirmed in Chrome; no email sent | Existing `Comtem-PMS` Agent is shut down (irreversible per Zoho). Replacement `CromptonPMSDevelopment` prepared, creation/key approval pending. Account review pending; zero emails available. No credits purchased. |
| Cloudflare R2 | Yes, private development file | Private `crompton-pms-dev`, Asia Pacific, exact development CORS, bucket-only Object Read & Write user token; **no expiry** requested and confirmed | Real uploads/downloads/delete across all five categories; cross-user/project denial, leader read-only scope, membership revocation, expired URLs, browser CORS, abandoned cleanup, Flutter and website controls passed | Native Android picker/device acceptance remains NOT TESTED |

The first R2 key was rotated and invalidated; only its replacement is retained in ignored configuration. No billing settings or real SMS/email dispatch were changed. Runtime keys cannot administer buckets. Public development URL and custom domains remain disabled.

Provider loading is now root `.env` â†’ root `.env.local` â†’ backend `.env` â†’ backend `.env.local` â†’ `.local/providers.<process ENVIRONMENT>.env`. Later nonempty provider values override earlier ones; blank placeholders cannot erase saved credentials. Process environment wins, so the normal launchers still force all message channels off. The private files have restricted Windows ACLs. Secrets are absent from scanned source/client bundles.

Actual checks this run: **63 FastAPI tests**, **12 Rules tests**, **20 Flutter tests / clean analysis**, **39 Flutter UI + 12 mocked attachment checks**, **8 website auth + 12 mocked file checks**, **22 real Firebase query checks**, **13 cloud report/export checks / 338 Excel cells**, and Next.js typecheck/lint/build. All 30 website visual comparisons pass with the existing eight intentional-button exclusions; Flutter tests retain eight welcome/login pixel comparisons. The Android debug APK is from the prior completed build; no device is connected and no release build is certified.

Real R2 evidence: `tests/r2-live-workflows.json` (13 checks), `tests/visual/providers/website-live-results.json` (7 checks), `tests/visual/providers/mobile-live-results.json` (3 checks), plus the finite smoke probe (10 checks). All probe-owned objects were removed; metadata tombstones remain until capability expiry/cleanup grace. The expiry probe waits 20 seconds for a one-second signature because this development host's clock was several seconds ahead of R2.

To run the actual cloud application, use separate terminals from the project root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start-development.ps1
```

```powershell
$env:API_URL='http://127.0.0.1:8007'
cd web
npm run dev
```

```powershell
cd mobile
flutter build web --debug --output build/cloud-files --no-wasm-dry-run --dart-define-from-file=../firebase/development.web.json
python -m http.server 3008 --bind 127.0.0.1 --directory build/cloud-files
```

Website `http://127.0.0.1:3000`, Flutter `http://127.0.0.1:3008`, API `http://127.0.0.1:8007/docs`. The API and website must both target development for real attachment workflows; local emulators remain a separate mode.

Re-run finite storage checks (creates/deletes only synthetic development fixtures):

```powershell
$env:ENVIRONMENT='development'
$env:PROJECT_ID='crompton-pms-dev-20261015'
$env:GOOGLE_APPLICATION_CREDENTIALS=(Resolve-Path '.local/development-service-account.json').Path
.\.venv\Scripts\python.exe scripts/configure-r2.py
.\.venv\Scripts\python.exe scripts/provider-smoke.py --r2-live
.\.venv\Scripts\python.exe scripts/r2-workflows.py
cd web
node tests/files-live.cjs --website-only --direct
node tests/files-live.cjs --mobile-only
```

Key settings: MSG91 `MSG91_AUTH_KEY` and configured `MSG91_WIDGET_ID`; ZeptoMail `ZEPTOMAIL_TOKEN` (or legacy `ZEPTOMAIL_API_KEY`), authorized `ZEPTOMAIL_FROM`, matching `ZEPTOMAIL_VERIFIED_DOMAIN`, regional `ZEPTOMAIL_API_ORIGIN`; R2 `R2_ENDPOINT`, `R2_BUCKET`, `R2_ACCESS_KEY`, `R2_SECRET_KEY`. All are backend-only. Existing CORS files remain `firebase/r2.cors.dashboard.development.json` (dashboard array) and `firebase/r2.cors.development.json` (SDK wrapper).

MSG91 challenges expire after 10 minutes in the application, even though its provider expiry is 15 minutes. Resend limits, five verification attempts, atomic consumption, enrolled-phone binding and Firebase UID linkage are covered by mocked/emulator tests. Default provider SMS branding remains CInfoS / InfoT Portal; no custom template was registered. Email invitations contain no temporary passwords; recovery stores HMAC challenges; durable delivery claims prevent automatic retries after ambiguous acceptance. `scripts/jobs.py` processes approved email events and retention cleanup under the same backend environment.

Live SMS/email probes require separate exact-recipient approval, global/channel enablement and exact recipient allowlists. Provider acceptance is not delivery evidence. See [MSG91 Widget API](https://docs.msg91.com/otp-widget), [Zoho authentication](https://www.zoho.com/cpaas/help/api/api-authentication.html), [regional endpoints](https://www.zoho.com/cpaas/help/api/multiple-data-centers.html), and [R2 signatures](https://developers.cloudflare.com/r2/api/s3/presigned-urls/).
