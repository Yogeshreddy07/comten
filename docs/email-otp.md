# Email OTP activation and recovery

Creating or inviting an employee queues a welcome email with their employee
code and activation instructions, without an OTP or password. The employee
opens Activate Account, enters their employee code, and taps Send OTP to receive
it at their registered email, shown partially masked in the app. The screen verifies
that OTP, then opens password setup followed by enrolled-phone SMS verification.
Only after both checks succeed does it return to Login. No temporary
password is returned, displayed, emailed or placed in the outbox. Firebase has
an undisclosed random credential while pending, and the account is disabled.
Existing activated accounts and passwords are preserved. Legacy accounts that
have not completed verification can also activate by email OTP.

Email activation, password recovery, and phone OTPs permit three attempts:
the first incorrect code leaves two attempts, the second leaves one, and the
third blocks verification and resending for 15 minutes. The server persists
the lockout across app restarts. After it ends, request a fresh code. OTPs
expire in 10 minutes, with a 60-second resend cooldown and five sends per hour.
Only HMAC hashes are stored for email OTPs; OTPs and
password-setup proofs are single-use, purpose-separated, and bound to the
employee's current email. Pending accounts cannot access the API or Firestore.
After password setup the account remains disabled in `PHONE_PENDING`. A separate
30-minute phone session is bound to the verified email and enrolled phone, can
only send/verify that phone's OTP, and grants no application access. The final
SMS verification activates the account and consumes the session. Contact changes
invalidate it. Existing activated accounts are not forced through this flow again.
Forgot Password retains its email OTP / new password flow, now with visible
dispatch errors and email binding. It cannot bypass pending account activation.

For hosted development testing, configure Railway with the existing private
`.env` Resend key and these values:

```dotenv
EMAIL_PROVIDER=resend
RESEND_FROM=no-reply@virtualfinpros.com
RESEND_VERIFIED_DOMAIN=virtualfinpros.com
RESEND_DISPATCH_ENABLED=true
RESEND_API_KEY=<private Resend key>
ALLOW_REAL_MESSAGES=true
EMAIL_REGISTERED_RECIPIENTS_ENABLED=true
MSG91_DISPATCH_ENABLED=true
SMS_REGISTERED_RECIPIENTS_ENABLED=true
```

The key must be saved in the hosted Railway service variables and deployed;
a key in the local `.env` is not available to the hosted API. A missing key
logs `MISSING_RESEND_API_KEY` without exposing credentials or email content.

The enrolled-recipient switches permit only unique, active, non-deleted employee
contacts, excluding placeholder email domains. Other addresses require the exact
approved-recipient list. SMS uses the existing MSG91 widget with its own channel
switch and enrolled-phone check; FCM retains its independent controls. Local
emulators use synthetic OTP `123456` and send no real activation/recovery mail.

OTP emails are sent directly by the API so no worker is needed for activation
or recovery. Other queued transactional notifications are drained by the API's
background email worker; durable provider claims and Resend idempotency keys
prevent duplicate dispatch. An uncertain provider response requires review.
See [Resend idempotency](https://resend.com/docs/dashboard/emails/idempotency-keys).

Account creation retains `activationEmailSent: false` for client compatibility.
Delivery failures are reported when Send OTP is tapped in Activate Account.
Retry there after correcting the provider configuration; do not create the
employee again.
