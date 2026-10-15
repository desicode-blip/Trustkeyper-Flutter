# Email OTP: build 28

Ajay resumed this feature on 10 October 2026. Firebase project: `trustkeyper`.
The normal app enables email OTP; the isolated offline UI Test APK disables it.

## Implementation

- Four callables: `requestEmailOtp`, `verifyEmailOtp`, `requestProfileEmailOtp`,
  `verifyProfileEmailOtp`, in `asia-south1`.
- Sender: `TrustKeyper <noreply@trustkeyper.com>`. Domain verification was
  confirmed by Ajay. Both secrets are enabled in Google Secret Manager:
  `RESEND_API_KEY` and `EMAIL_OTP_SECRET`. No secret ships inside Flutter.
- Six-digit random codes, five-minute validity after provider acceptance,
  sixty-second resend cooldown, five wrong attempts then fifteen-minute lockout.
  Verification is transactional and single-use; only keyed hashes are stored.
- Limits: five requests/email/hour, twenty/IP/hour, 200 globally/day. Review
  capacity and costs before public launch. Clients cannot read challenges/rates.
- Provider failure never displays successful send. Delayed client responses
  are rejected after sign-out, newer challenges or another login session.
- Existing Auth email accounts retain UID; new users complete profile/roles.
  Disabled, paused and admin accounts cannot use customer email login.
  Profile text is never grounds to merge another account.
- Phone profile email verification requires recent phone login, binds to the
  same UID and refreshes that identity without signing into a replacement user.
- Returning email sessions can use existing phone-bound workflows only with
  server-issued verified-phone claims matching the actual Auth phone. Membership
  and document invite checks remain mandatory. Generic custom tokens are denied.
- Keep me logged in is functional: web selects Firebase LOCAL/SESSION; native
  unchecked login signs out on the next cold start. Existing upgrades default
  to remembered sessions. Admin persistence is per-device, not a one-device cap.

## Runtime and deployment

The runtime has custom-token signing permission on its own service account,
not a project-wide Token Creator grant. Secrets are bound on the functions.
Production verification exposed a separate missing user-management grant: the
runtime could store challenges but could not look up/create Auth identities.
`scripts/configure-email-identity-access.cjs` assigns the reviewed custom role
with only `firebaseauth.users.get`, `firebaseauth.users.create` and
`firebaseauth.users.update` on TrustKeyper. It grants neither account deletion
nor authentication configuration access and preserves other IAM bindings.
The failed challenge was consumed; a replacement was sent for direct user
verification. Do not treat delivery alone as completed login acceptance.
Email resources: 256 MiB, fractional CPU, concurrency one, maximum three instances.
The regional CPU quota initially blocked a new requestEmailOtp revision. Recovery
created a distinct bounded revision; all four email functions and issueKeyReturnCode
now report ready, with startup boost disabled. Evidence is in
`build28-email-runtime.log`; Functions ACTIVE alone is not revision acceptance.

The first incremental web output used an outdated generated plugin registry,
which attempted a native MethodChannel on web before any email request. A clean
`flutter pub get` and release web build restored `cloud_functions_web`.
`scripts/build-testing-release.ps1` reproduces the clean build; archive checks
reject web output missing the `flutter-fire-fn` registration. The deployed
browser now opens an OTP challenge after real provider acceptance. Inbox receipt
and valid-code production login still require the user's direct code entry.

After a reviewed update, from the migration worktree:

```powershell
firebase deploy --only 'functions:authentication:requestEmailOtp,functions:authentication:verifyEmailOtp,functions:authentication:requestProfileEmailOtp,functions:authentication:verifyProfileEmailOtp' --project trustkeyper --non-interactive
node scripts/configure-email-runtime.cjs --project=trustkeyper --apply
node scripts/configure-email-identity-access.cjs --project=trustkeyper
firebase deploy --only 'hosting,firestore:rules,storage' --project trustkeyper --non-interactive
```

The runtime helper checks the bounded settings and disables startup CPU boost.
Callable transport does not require a Google IAM login. Authenticated operations
still require Firebase ID tokens and server authorization; no public data rules.

## Rotate the exposed key before public release

1. Create a replacement sending-only Resend key restricted to trustkeyper.com.
2. Save privately using `firebase functions:secrets:set RESEND_API_KEY --project trustkeyper`.
3. Redeploy all four email functions, verify runtime and real delivery/login.
4. Revoke the old key after replacement acceptance. Never paste keys in chat.

The previous key was exposed in chat. Do not broaden it to read messages.
Keep the hashing secret stable during provider-key rotation; changing that
secret invalidates outstanding challenges and rate-limit identifiers.

## Real testing

1. Open https://trustkeyper.web.app/#/login in a fresh browser session.
2. Select Email, enter the controlled non-admin inbox, and press Get OTP.
3. Check Inbox and Spam. Enter the newest code directly in the same app tab.
   Refresh loses the in-memory challenge: request a fresh code if necessary.
   Never send the code or mailbox password in chat.
4. Confirm profile setup for a new account, or the original existing account.
   Sign out and log in again; confirm the UID/profile remains the same.
5. Separately verify a phone customer's profile email and same-UID access.
   An email belonging to a different UID must fail instead of auto-merging.
6. Check wrong/expired/resent codes and stale sessions without exhausting
   the real inbox's hourly limit. Customer email must not authenticate an admin.

The official Resend simulator accepted delivery. A sending-only key cannot
read messages through GET APIs (401/403), so the production smoke test does not
pretend to verify a valid code. Actual SDK custom-token login and linked-phone
proof passed the Auth emulator; controlled-inbox production acceptance is separate.

Local: `flutter test`, `flutter analyze`, `npm --prefix functions test`, and
`firebase emulators:exec --only auth,firestore,storage --project demo-trustkeyper 'npm --prefix functions run test:rules'`.

See `docs/build28-testing-release.md` and `output/ui-audit/build28-*` evidence.
References: [Resend simulator](https://resend.com/docs/dashboard/emails/send-test-emails),
[Firebase persistence](https://firebase.google.com/docs/auth/web/auth-state-persistence),
[Cloud Run CPU](https://cloud.google.com/run/docs/configuring/services/cpu),
[Firebase Authentication permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/firebaseauth).
