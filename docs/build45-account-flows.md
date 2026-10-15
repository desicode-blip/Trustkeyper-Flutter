# Build 45 — real account flows, 13 October 2026

Razorpay changes and provider calls are explicitly excluded from this batch.
This is an implementation/testing record, not a whole-product completion claim.

## Implemented

- Broker, owner and tenant profile entries now open saved details, actual masked
  bank information, help, confirmed logout and guarded account closure. Broker
  role switching, participant manager support and existing updates remain wired.
- Name, city and optional broker RERA save through Firebase. Name errors appear
  once next to their input. Existing property-label/address rules are unchanged.
- Phone/email verification comes from Firebase Auth, not editable profile text.
  Changing email requires the existing normal server email-OTP flow on the same
  account. A successful OTP is not consumed twice if the subsequent profile
  write fails. Identity changes clear stale private reads and challenges.
- Approved 09/19, 20, 22, 23, 28, 29, 30 and 31 layouts are implemented with
  field-level validation, real actions and recovery states. The details fields
  use the approved inside-label 60-pixel layout rather than floating outlines.
- Closure checks actual signed obligations, unsettled real payouts/checkouts
  and refund history. Test money never becomes fictional money due. Final
  consent and a recent login are required. Firebase Auth is disabled, sessions
  are revoked and stale-token Firestore/Storage access is denied.
- A private admin queue can finish an uncertain already-consented closure or
  restore a confirmed account within seven days. Durable mutation leases keep
  concurrent closure and restoration from racing identity disable/enable.
  Roles, broker approval and shared legal history are not rewritten.

## Important design/behaviour boundaries

The original “Delete forever” copy would falsely claim permanent erasure.
These screens therefore say **Close account**, disclose retained shared legal
and audit records, and provide the approved seven-day team restoration window.
There is no scheduled personal-data purge or approved retention policy in this
batch. Closure is not a promise that every record has been physically erased.

No rating, broker-since date, bank verification or paid-out amount is invented
to make a screenshot look populated. Bank changes/beneficiary verification
remain deferred with Razorpay. The language screen truthfully supports English
only; full Hindi/Telugu translations and layout acceptance remain unfinished.

The six new account golden images are regression baselines, not six pixel-perfect
certificates against Aman’s exports. Whole-product visual acceptance is still
open, including corrected signed-amendment/reconciliation and remaining
owner/tenant lifecycle variants. The build-31 coverage inventory is stale and
must not be presented as the current number of unfinished features.

## Verification

- 414 Flutter tests pass for the final frozen build, including 20
  account-flow/visual tests. The standalone offline closure returns to its
  gallery after logout; optional callbacks never leave a permanent busy state.
- Analysis is clean; the exact frozen sources are checked again after signing.
- 250 backend tests pass, including consent, proof, obligations, retry,
  concurrent closure/restoration, uncertain provider recovery and admin expiry.
  The seven-day window begins at confirmed closure; a prolonged outage cannot
  consume it before the customer receives confirmed closure.
- 49 complete real-emulator rules/integration tests pass. A separate actual
  Auth/Firestore lifecycle test also passes: normal phone OTP, persisted details,
  blocked active legal obligation, identity disable, denied login, authorised
  restore and login returning to the same UID. Its fixtures are emulator-only.
- Production read-only checks pass for all four configured test-phone accounts.
  Seven anonymous callable guards and customer-to-admin-operation denials pass.
  No production profile, closure, restoration or financial mutation is exercised.
- Seven account callables and updated access rules are published to `trustkeyper`.
  Google’s invoker IAM restriction required the same existing callable transport
  configuration used by the app’s other functions. Normal Firebase Auth and
  server role checks remain enforced; this is not an authentication bypass.

Evidence is in `output/ui-audit/build45-*`. Signed artifacts, hosting-byte
verification and physical-device results have their own checks; do not infer
them merely from passing widget tests or an APK installation.

The phone was subsequently reconnected. Build 45's separate UI Test package
installed successfully. Saved synthetic RERA details survived reopening; help
expanded, logout cancellation retained the profile, and the three-step offline
closure returned to the gallery. Original normal build 43's base APK hash and
last-update timestamp remained unchanged. These are bounded offline device
checks, not proof of real email delivery or complete active-board acceptance.

During these checks, the existing-email edit was found to still hit the stricter
onboarding binding. Build 46 tracks the separate authenticated account-edit fix
and stale-request recovery; do not treat build 45 as accepting that operation.
