# TrustKeyper Firebase admin panel

## Access

- Local route: `/#/admin/login`
- Production: `https://trustkeyper.web.app/#/admin/login`
- Auth: Firebase Email/Password. Administrators whose Firebase account already
  has a linked phone provider also complete a phone OTP challenge.
- Authorization: the matching `users/{uid}` document must contain
  `roles: ["admin"]` and must not contain `paused: true`.
- No default username or password is stored in source control. Create or reset
  an administrator only in Firebase Authentication, then add the role to that
  user's Firestore document through an already-authorized process.

## Customer authentication

- Phone sign-in sends a six-digit Firebase SMS OTP and supports the configured
  Firebase test phone numbers without consuming the production SMS quota.
- Once the code-entry screen opens, manual verification owns that request.
  Late automatic verification callbacks cannot consume its OTP, and callbacks
  from an older request cannot replace a resent verification session.
- Customer email OTP is deferred in build 17 at Ajay's request. Its code remains
  inactive; phone-only onboarding never claims email verification. See
  `docs/email-otp-setup.md` before enabling the sender and Functions.
- Administrator email sign-in retains Firebase Email/Password and its separate
  access checks.
- Firebase email-link authentication is intentionally not used because the
  Firebase console marks the legacy mobile Dynamic Links flow as discontinued.

## Build and hosting

```powershell
cd apps/flutter_app
C:\src\flutter\flutter_windows_3.38.6-stable\flutter\bin\flutter.bat build web --release --pwa-strategy=none --no-web-resources-cdn
```

The deployable output is `apps/flutter_app/build/web`. Firebase Hosting is
configured at the repository root. Deploying rules or hosting changes live
production state and must be reviewed and explicitly approved before running.
The production build self-hosts Flutter rendering resources and does not use an
offline-first service worker, preventing stale bundles and CDN failures from
leaving the admin page blank.

Launcher icons and browser icons are generated from
`assets/images/trustkeyper-app-icon.png` with `flutter_launcher_icons`.

Android release builds require the existing Google Play upload keystore. They
must never fall back to the debug certificate. Run `scripts/build-flutter-aab.ps1`
using the default private signing store at
`$HOME/.trustkeyper/signing/android-upload.json`, or pass
`-SigningCredentialsFile` explicitly. No legacy app or signing CLI is required.
Use `-FlutterExecutable` if Flutter is not on PATH. The script checks
the expected upload certificate before building and verifies the bundle's
certificate afterward. Credentials are read locally and are never printed.

## Operational behavior

- Broker approval/rejection and account pause/resume update `users`.
- Demo agreement review uses two trusted callables with revision checks, frozen
  non-signable snapshots and atomic audit/events. Administrators receive, review
  or return drafts with a correction reason; clients cannot mark them signed.
  Approved legal documents, participant consent and the manual signed-PDF
  fallback are still required before implementing production signing.
- Document decisions update `documentRequests` and enqueue notifications.
- Rent actions record follow-ups only; they cannot mark money paid.
- Payout actions create retry/hold requests only; they never move money.
- Repair, move-out and photo-review actions persist to their workflow records.
- Review transitions atomically append `adminAuditLogs` and agreement events.
  Other client-admin workflows retain separate audit writes and need further
  transaction/error-path acceptance; this is not a complete audit guarantee.

Email/WhatsApp delivery and Razorpay execution require trusted Cloud Functions
and approved provider credentials. Until those workers are deployed, queued
requests remain visible and auditable instead of being falsely reported sent.
