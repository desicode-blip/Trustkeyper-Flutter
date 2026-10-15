# Product completion work — 13 October 2026

The approved baseline has 438 artboards, including 44 explicitly discarded
boards on pages 13 and 14. The 394 active boards span 18 design exports and
85 product/user stories. The build-31 source audit is stale; a "missing" row
there is not proof that later builds still lack the function. Conversely,
passing tests is not proof of exact acceptance for every artboard.

## Current non-payment work: build 46

The verified existing-email edit discovered during build-45 acceptance is fixed.
The old onboarding binding intentionally rejects changing an existing email;
the editable account form must use a separate account-edit challenge, not weaken
onboarding or create another customer UID. Bind codes to the original verified
identity, require recent customer login, reject collisions/admin/paused users,
and refresh the same Firebase session after changing the Auth primary email.
Out-of-order OTP callbacks, gateway replacement and interrupted-save recovery
have regression coverage. All 420 Flutter, 257 backend and 51 emulator tests
pass. Analysis is clean, the two new callables and Firebase Hosting are
published, hosted byte/runtime checks pass, and the signed unchanged-source
AAB/isolated APK are archived in Downloads. Physical build-46 acceptance is
pending because the phone disconnected before installation.

Razorpay remains deferred. Server-enforced mandatory admin MFA, full Hindi/Telugu,
corrected signed-amendment/reconciliation and complete active-board acceptance
remain open. A role check alone is not proof of admin second-factor enforcement.

## Completed non-payment batch: build 45

Profile/details/help/logout, verified email editing, guarded closure and the
private restoration queue are implemented and tested. The signed build and
device/hosting checks are tracked separately in `output/ui-audit/build45-*`.
Full Hindi/Telugu support, corrected signed-amendment/reconciliation and full
remaining lifecycle/design acceptance are still open; do not declare 100%.

Razorpay implementation is explicitly deferred at Ajay's request. Do not change
gateway/transfer credentials or initiate provider tests in this batch.

1. Replace inert broker profile controls with approved profile/details/help,
   verified-contact editing and confirmation dialogs backed by real storage.
2. Implement guarded account closure, obligations checks and authorised
   seven-day restoration without claiming that retained legal records vanished.
3. Reconcile language support and remaining lifecycle/correction/renewal states
   against actual implemented routes; record partial states honestly.
4. Run focused/full tests, visual comparisons and normal Firebase checks, then
   freeze sources and produce the next signed testing bundle.

Build 45's local/server checks, signed AAB, isolated APK and hosted byte checks
pass. After reconnection, bounded offline account flows passed on the phone;
details save/reopen, help, logout cancellation and three-step closure are
recorded separately. Original normal build 43's base APK checksum and update
timestamp stayed unchanged. Full authenticated/native acceptance remains open.

## Previous implementation batch: build 44

- Tenant references 12/04–12/10: actual linked home, flatmates and exact
  personal rent/deposit shares; home/flatmate correction and share requests;
  pending and completed acknowledgements. Save/reopen, stale revision, timeout,
  wrong-account, cancellation and queue guards need recorded acceptance.
- Tenant home entry opens the confirmation flow for an unconfirmed linked
  signed/current home. Pending corrections do not silently change money.
  Requests reach the admin queue. Resolving requires a corrected newer
  externally signed, digest-matching revision, not an admin checkbox alone.
  The existing externally signed original workflow is retained.
- Broker records references 09/05–09/10: property/owner/tenant tabs, actual
  saved records, search, contact/property detail, bound document views and
  photo-check entry. Equal free-text property labels must not merge IDs.
  Private details must disappear when membership/access changes.
- Web broker handoff references 01/22–01/23: mobile download/app-open entry,
  desktop real Play-store QR and user-initiated link composer. Owner/tenant
  recipient web and admin portal remain web flows. Test-app deep links must
  never claim the normal app's scheme.
- Visual tests load the actual Roboto, General Sans fallback and icon fonts,
  and await the logo image decode. The bundled General Sans already includes
  the rupee glyph; missing rupee/icons in incomplete test-font setup are not
  a reason to change working production fonts.

## Remaining verification and implementation tracks

1. Reconcile every active board with current routes and state-generating
   data, not just an export number or generic journey stub. Compare actual
   rendered layouts, assets, copy, controls, keyboard and narrow/large text.
2. Complete uncovered broker profile/my-details, help, language, bank-change,
   account-deletion and payments states. Account deletion must respect actual
   unsettled obligations and preserve necessary audit records; never display
   "deleted" after merely saving a request.
3. Complete uncovered owner/tenant dashboard, identity-change, confirmation,
   inspection comparison, manager-added property and lifecycle edge states.
   Existing working persisted services must be reused rather than replaced
   with hard-coded examples.
4. Complete remaining renewal import/page validation and reviewed extraction
   states. Inventory extraction remains inventory-only with review and
   explicit save; full agreement OCR is restricted by repository instructions.
5. Bank/UPI beneficiary confirmation, owner/broker disbursements, financial
   reconciliation and deposit refunds need the enabled Razorpay transfer/
   product. Aman confirmed Razorpay Route on 13 October 2026. Its enabled
   Test Mode capability and actual owner/broker Linked Account mappings still
   need provider evidence. Razorpay TEST
   checkout capture is not a real owner/broker payout or a verified bank.
6. Finish authenticated native device journeys, push receipt, deployment
   parity and signed artifact checks. Keep the original phone app untouched
   while using the isolated offline UI Test package for visual work.

## Provider decision

Aman confirmed Razorpay Route. Route linked accounts, transfer/settlement
tracking, reversal/refund reconciliation and exact contractual allocations
are the remaining integration work. Do not substitute RazorpayX or treat
captured checkout money as a settled beneficiary transfer. Test account IDs
are needed to verify readiness; no keys belong in chat.

Razorpay's separate products are documented in its official
[Route overview](https://razorpay.com/route/) and
[RazorpayX payout documentation](https://razorpay.com/x/payouts/).
The QR uses the maintained
[QR.Flutter API](https://pub.dev/documentation/qr_flutter/latest/).
App opening follows the user-gesture and fallback behaviour described in
[Chrome's Android intent documentation](https://developer.chrome.com/docs/android/intents).

Build 44 is an implementation/testing batch, not a declaration that all
394 active boards or the production money flows have been accepted.
