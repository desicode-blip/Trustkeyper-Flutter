# Build 29: one account for email and phone

Ajay confirms that production email OTP login works on 10 October 2026.
That is user-reported acceptance, not an agent-recorded physical-device test.

## Implemented behavior

- Phone first: complete profile email verification. The backend attaches the
  verified email to the current Firebase UID; it does not create a second user.
- Email first: profile setup requests a real Firebase phone OTP. The app links
  the verified phone credential to the current email UID instead of signing in
  as a different phone account. Automatic SMS verification uses the same path.
- Existing email-only customer profiles return to profile setup until a phone
  is verified. Administrators keep their separate login flow.
- After both contacts are verified on the same UID, later phone or email logins
  resolve to that same UID, roles, agreements and stored account data.
- Typing an email/phone without OTP verification never establishes ownership.
- If a contact already belongs to another UID, the operation is blocked with a
  support/recovery message. Neither account nor its records are deleted or
  silently merged. Existing duplicate accounts require a separately reviewed
  recovery/migration after proving ownership of both identities.
- Expired/missing challenges and session changes cannot turn a linking code into
  an ordinary sign-in. Signing out clears the pending phone-link state.

## Acceptance sequence

1. Start with a new controlled email and a phone not already assigned to another
   account. Use test identities, not someone else's real contacts.
2. Sign in by email OTP. Enter name and phone on profile setup.
3. Verify the phone OTP. Continue profile setup and choose the customer role.
4. Note the Firebase Authentication UID privately in the console. Do not share
   ID tokens, OTPs or real identity documents in chat.
5. Log out and sign in by phone. Verify the same UID, role and saved records.
6. Log out and sign in by email. Check that same UID and records again.
7. Repeat with phone-first signup, followed by profile email OTP verification.
8. Try a contact already assigned to a different test account. Expect a collision
   error; both original accounts and data must remain intact.
9. Check SMS auto-verification, wrong code, resend and sign-out during a pending
   challenge. There must be no unexpected switch to another account.

Firebase Auth emulator integration exercises actual SDK credential linking,
subsequent phone/email sign-in, preserved UID and trusted linked-phone claims in
both directions. Flutter tests cover manual/automatic linking, changed sessions,
collision protection, routing and failed-delivery draft retention.

## Release boundary

Final validation passes 464 checks: 253 Flutter, 175 backend, and 36 actual
Auth/Firestore/Storage emulator checks. Flutter analysis is clean. Evidence:
`output/ui-audit/build29-flutter-tests.log`, `build29-backend-tests.log`,
`build29-rules-tests.log`, and `build29-analyzer.log`.

The signed `C:/Users/ajayb/Downloads/TrustKeyper-v2.0.0-build29-testing.aab`
passes bundle validation, normal package/version and Google Play upload-certificate
checks. SHA-256:
`BC4B07D6539006CDA16C18D264AA9B0989215E7324D60E31ECCC6044ACD11643`.
The separate offline `TrustKeyper-UI-Test-build29.apk` is also archived, has a
different package and no Internet permission. Neither artifact was installed.

Firebase Hosting `https://trustkeyper.web.app` is updated; HTTP 200, exact local/
hosted main-JavaScript bytes and Cloud Functions plugin registration are verified.
See `output/ui-audit/build29-hosted-integrity.json` and `build29-artifacts.json`.
No functions/rules deployment, DNS change, Git push/commit or Vercel release was
made for this change. ADB detected no device; native bidirectional OTP acceptance
and full physical-device design acceptance remain separate gates.

To install the normal AAB, use Google Play Console → Testing → Internal testing,
upload build 29, add the intended testers and follow the Play opt-in/install link.
An AAB cannot be installed directly in a file manager. A normal Play update
replaces the normal app build; this task did not publish or install that update.

Build 28 does not contain the new email-first phone-link UI. Use the validated
build 29, or the updated Firebase-hosted web app.
The offline UI Test APK cannot validate real authentication. No existing normal
phone installation is automatically replaced.

This closes the bidirectional onboarding link gap, not every remaining product
story or approved design. Owner listing/self-onboarding, sign-only/older-file
renewal, financial reconciliation, account recovery/deletion, translations and
complete device/design acceptance remain tracked in the product coverage ledger.
