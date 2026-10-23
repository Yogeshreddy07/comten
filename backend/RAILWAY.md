# Deploy the development backend to Railway

Repository: https://github.com/Yogeshreddy07/comten, branch `main`.
Current API: https://comten-production.up.railway.app, deployed 23 October 2026.
The Railway project is `4a9cfa7b-5a6a-41f5-b5ca-526d4f667cb9`; service is
`f5a3e27b-9840-49e6-8a10-0001c8ca512b`. Root `/backend` and `/health` were
configured in the dashboard; the Dockerfile was detected automatically.
This deploys only FastAPI. Flutter, the Next.js website and Firebase rules are
separate components. Existing development Firebase accounts/data remain in place;
do not run either seed script on Railway. No SQL database or volume is required.

1. In Railway, create an **Empty Project**, then add an **Empty Service** named
   `backend`. Configure it before its first deployment.
2. Under the service's **Settings**, connect GitHub repo
   `Yogeshreddy07/comten`, branch `main`. Set **Root Directory** to `/backend`
   and **Healthcheck Path** to `/health`. Railway detects the included Python
   3.12 Dockerfile, which starts Uvicorn on `0.0.0.0:$PORT` (default `8080`).
   Leave Build Command and Start Command overrides empty. Let Railway supply
   `PORT`. New services cannot opt into the deprecated Config as Code feature;
   `railway.json` is retained for legacy services only.
3. On this development PC, generate the private variable map if needed:

   ```powershell
   .\.venv\Scripts\python.exe scripts/export-railway-variables.py
   ```

   Open `.local/railway-variables.json` locally. In Railway **Variables → Raw
   Editor**, select JSON mode if offered and paste the whole JSON object. Save.
   This file contains real private keys: paste it only into Railway variables.
   It is ignored by Git and must not be added to GitHub or chat.
4. Confirm these initial variables:

   | Variable | Value/source |
   |---|---|
   | `ENVIRONMENT` | `development` |
   | `PROJECT_ID` | `crompton-pms-dev-20261015` |
   | `FIREBASE_API_KEY` | Development web API key from the generated map |
   | `FIREBASE_SERVICE_ACCOUNT_JSON` | Entire service-account JSON as one variable |
   | `RECOVERY_HMAC_KEY` | Existing private recovery key from the map |
   | `WEB_ORIGIN` | Initially `http://127.0.0.1:3000`; later the website's exact HTTPS origin |
   | `ALLOW_REAL_MESSAGES` | `false` |
   | `MSG91_DISPATCH_ENABLED` | `false` |
   | `ZEPTOMAIL_DISPATCH_ENABLED` | `false` |
   | `FCM_DISPATCH_ENABLED` | `false` |

   The map also includes configured R2/MSG91/ZeptoMail secrets and empty recipient
   allowlists. Do not set `GOOGLE_APPLICATION_CREDENTIALS` to a Windows file path.
   Remove `FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST` if present.
   Do not import the root `.env.example` defaults; those target local emulators.
5. Deploy the staged changes. Check deployment logs for successful startup.
   Docker builds have not been run locally; Railway performs the actual image
   build. Firebase JSON startup/authenticated cloud access passed locally.
6. Open **Settings → Networking → Public Networking → Generate Domain**.
   Use the service's `$PORT` target if prompted. Railway provides HTTPS.
7. Open `https://YOUR-DOMAIN/health`. Expected:

   ```json
   {"status":"ok","environment":"development","project":"crompton-pms-dev-20261015"}
   ```

   Open `https://YOUR-DOMAIN/docs` and test `/api/auth/login` with an existing
   tester employee code and its password. A health response alone does not prove
   Firebase permissions, R2 or OTP delivery.
8. Mobile's `BASE_URL` must be `https://YOUR-DOMAIN/api`. Both development Firebase
   define files now use `https://comten-production.up.railway.app/api`. Build
   from `mobile/` with `flutter build apk --debug
   --dart-define-from-file=../firebase/development.mobile.json`. Version 1.0.1+2
   uses this hosted address; discard the older 22 October `.invalid` preview.

## OTP and provider activation

SMS is now enabled on the deployed service for the owner's exact approved test
recipient. `EMP001` was enrolled and verified through a received SMS and the
hosted verification API on 23 October. `ALLOW_REAL_MESSAGES=true` and
`MSG91_DISPATCH_ENABLED=true`; email and FCM remain disabled. The private
`.local/railway-variables.json` reflects these live settings. The export helper
deliberately generates a fresh dispatch-disabled baseline; do not overwrite
the live settings from that baseline unintentionally.

For this backend-mediated integration, the dedicated MSG91 widget must use
**Web** integration. Its **Allow Specific** origin countries include India and
Netherlands because the Railway service runs in Amsterdam. These are request
origin countries, not destination phone countries. Recipient permissions are
still enforced by the backend's exact phone allowlist and enrollment checks.
See [MSG91 country restrictions](https://msg91.com/help/sendotp/country-wise).

To verify an already-sent SMS without sending another one, set `PMS_TEST_OTP`
locally and run `scripts/verify-phone-otp.py`. The helper checks hosted OTP
verification, Firebase session linkage, activation confirmation and replay;
it persists no OTPs or tokens. Real OTP values must never be committed.

Deploying the API does not enable SMS/email automatically. Use real, enrolled
test recipients, not placeholder phones or `example.invalid` email addresses.
An admin must assign the phone number before activation verifies it.

After the MSG91 account/widget and a working ZeptoMail Agent/key are ready, set
`ALLOW_REAL_MESSAGES=true` and enable only the channel being tested. Set
`APPROVED_SMS_RECIPIENTS` to exact normalized digits such as `91` plus the real
10-digit phone, and `APPROVED_EMAIL_RECIPIENTS` to exact email addresses
(comma-separated). SMS needs `MSG91_DISPATCH_ENABLED=true`, `MSG91_AUTH_KEY`
and `MSG91_WIDGET_ID`. Email needs `ZEPTOMAIL_DISPATCH_ENABLED=true`,
`ZEPTOMAIL_TOKEN`, `ZEPTOMAIL_FROM`, `ZEPTOMAIL_VERIFIED_DOMAIN` and the correct
regional `ZEPTOMAIL_API_ORIGIN`. Redeploy and verify actual receipt and code
consumption before approving OTP testing. Existing ZeptoMail setup was reported
inactive and requires repair. Keep placeholder recipients out of allowlists.

FCM remains independently gated by `FCM_DISPATCH_ENABLED` and
`APPROVED_FCM_USER_IDS`. This API service does not run `scripts/jobs.py`;
queued invitation/security emails and scheduled cleanup require a separately
configured worker/job. Password-recovery OTP mail is sent by the API itself.

## References

- [Railway monorepo/root directory configuration](https://docs.railway.com/deployments/monorepo)
- [Railway Dockerfiles](https://docs.railway.com/builds/dockerfiles)
- [Railway Variables and Raw Editor](https://docs.railway.com/variables)
- [Railway public HTTPS domains](https://docs.railway.com/networking/public-networking)
