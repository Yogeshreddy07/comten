# Email OTP activation and recovery

Creating or inviting an employee does not send an activation OTP. The employee
opens Activate Account, enters their employee code, and taps Send OTP to receive
it at their registered email. The screen verifies that OTP, then opens password
setup and returns to Login. No temporary
password is returned, displayed, emailed or placed in the outbox. Firebase has
an undisclosed random credential while pending, and the account is disabled.
Existing activated accounts and passwords are preserved. Legacy accounts that
have not completed verification can also activate by email OTP.

Activation OTPs expire in 10 minutes, permit five attempts, and have a 60-second
resend cooldown and five sends per hour. Only HMAC hashes are stored; OTPs and
password-setup proofs are single-use, purpose-separated, and bound to the
employee's current email. Pending accounts cannot access the API or Firestore.
Forgot Password retains its email OTP / new password flow, now with visible
dispatch errors and email binding. It cannot bypass pending account activation.

For hosted development testing, configure Railway with the existing private
`.env` Resend key and these values:

```dotenv
EMAIL_PROVIDER=resend
RESEND_FROM=no-reply@virtualfinpros.com
RESEND_VERIFIED_DOMAIN=virtualfinpros.com
RESEND_DISPATCH_ENABLED=true
ALLOW_REAL_MESSAGES=true
EMAIL_REGISTERED_RECIPIENTS_ENABLED=true
```

The enrolled-recipient switch permits only unique, active, non-deleted employee
emails, excluding placeholder domains. Other addresses still require the exact
approved-recipient list. SMS and FCM retain their independent controls. Local
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
