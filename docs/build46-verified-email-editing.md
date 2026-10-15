# Build 46 — verified account email editing

Razorpay is excluded. This batch fixes an actual account-form gap: build 45 let
customers type a new email, but its onboarding-only binding rejected changing
an existing address. Onboarding keeps that guard; the account editor uses two
separate authenticated account-edit callables.

## Behaviour

- A recently authenticated broker, owner or tenant with a verified Auth phone
  can add or replace their own email after a normal OTP to the new inbox.
- Codes are bound to the customer UID, purpose, target address and original
  Auth email/phone snapshot. A changed identity, wrong account, wrong code,
  expired/replayed code, admin, paused account or address collision is denied.
- Firebase changes the email on the existing UID. Phone, roles, approval,
  agreement membership and all existing records remain on that UID. Another
  identity is never automatically merged or overwritten.
- A server-issued same-UID session refresh handles Firebase's email-change
  refresh-token expiry. The client validates UID/address/proof before using it.
  This follows [Firebase's user-management API](https://firebase.google.com/docs/auth/admin/manage-users)
  and [session lifecycle](https://firebase.google.com/docs/auth/admin/manage-sessions).
- An out-of-order OTP callback cannot replace a newer challenge or refresh
  another session. Changing the form's account gateway clears busy/stale state;
  resend's 60-second UI cooldown now matches the server.
- Broker document-state golden checks now supply one deterministic clock to
  fixture timestamps and their rendered countdown. An initial full run exposed
  a one-second, 51-pixel countdown difference on a slow machine. The production
  clock still advances normally; an elapsed-time test checks 45 → 44 → resend.
- If Auth changes but the profile write/session response fails, no false saved
  result is displayed. Sign in normally through the verified phone/new inbox
  and request a fresh code if needed. The UID is not recreated.
- After verification and an interrupted profile save, the last actually verified
  address becomes the form's identity baseline. Reverting to the old address
  requires a new code; clearing the field cannot silently remove that identity.

## Recorded verification

All 420 Flutter tests, 257 backend tests and 51 complete emulator tests pass
(728 full-suite checks). The 75 focused checks are included in that count.
The emulator exercises actual Auth UID/email changes, profile persistence,
old-email unlinking and subsequent email/phone access to the same records.
The two production callables are active with bounded runtimes and verified
anonymous denial. No live customer email was changed by automated acceptance.
Analysis is clean. The signed AAB and isolated APK verify cryptographic
signatures/package identities against an unchanged source snapshot. All four
published hosting assets match local bytes; five anonymous browser routes and
five startup/storage/retry cases pass. The four configured phone accounts pass
production read-only profile/eligibility and admin-operation-denial checks.
No customer closure/restoration or email mutation is performed in production.

Downloads contains `TrustKeyper-v2.0.0-build46-testing.aab`,
`TrustKeyper-UI-Test-build46.apk` and the build-46 testing guide. The phone had
disconnected by the final installation check, so the new APK is not installed
or physically accepted. Build 45's bounded offline checks remain recorded;
the original normal app was not modified. See `output/ui-audit/build46-*`.

## Test this in the normal Firebase app

1. Sign in through the existing verified phone or current verified inbox. If
   asked for a recent login, sign out and log in again before editing.
2. Open **Profile → My details**. Enter a different non-admin inbox you control.
3. Tap **Save**, enter the new inbox's actual code, then **Verify and save**.
   Wrong/incomplete codes stay inline. Never paste the received code in chat.
4. Reopen details. The new email and original phone should be shown.
5. Sign out; use email OTP for the new address, then phone OTP for the original
   number. Saved name, roles and agreements must be identical in both sessions.
6. Trying an address belonging to another customer must fail without merging
   data. An old code must fail after a newer request or changed identity.

Do not sign in with the removed old email to test rejection: the ordinary email
sign-up flow may create a new, unrelated UID for an unregistered address. The
emulator test verifies that the old email no longer maps to the original UID.

The separate offline UI Test app cannot establish real email delivery, identity
binding or production mutations. Unit/emulator/device evidence and deployment
are recorded separately under `output/ui-audit/build46-*`.

Full Hindi/Telugu translations, server-enforced mandatory admin MFA, corrected
externally signed amendments and complete active-artboard/device acceptance
remain open. This batch is not a whole-product completion certificate.
