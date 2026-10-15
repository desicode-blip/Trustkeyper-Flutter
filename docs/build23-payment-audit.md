# Build 23 payment implementation and verification

Date: 10 October 2026. This is a completed TEST-payment implementation slice,
not a certificate that the whole product or every design is complete.

## Implemented

- Tenant phone/UID-bound, server-priced first deposit/current-month rent and
  maintenance, with calendar-day proration and exact tenant-paise allocation.
- Subsequent unpaid-month selection through the lease end; no repeat deposit,
  duplicate paid month, client-entered price or implicit past-rent write-off.
- Official Razorpay Android/web checkout in Test Mode only, signed callback and
  provider capture verification, immutable receipts and authenticated recovery.
- Idempotent order/retry handling, raw-body webhook HMAC checks, duplicate and
  out-of-order event handling, and reconciliation for changed/paused identities.
- A verified TEST PDF receipt; no fabricated email/WhatsApp delivery, real funds,
  legal signature, tenancy activation, payout or key-release result.
- Admin TEST labels/read-only receipt detail and exclusion from live rent totals.
- Existing externally signed-original/manual-admin-upload workflow is preserved.
  Demo copies remain explicitly non-signable and accepted solely for TEST checkout.

## Firebase deployment

Production project: `trustkeyper`. Billing is enabled; the deployment login was
refreshed. No staging/GitHub/Vercel deployment, branch creation, commit or push
was performed.

All five payment functions are active in `asia-south1`: `quoteRentPayment`,
`beginRentPayment`, `confirmRentPayment`, `reconcileRentPayment`, and
`razorpayTestWebhook`. Google organization policy prevents public-invoker IAM
bindings; the allowlisted callable-transport configuration is verified. Callables
still require Firebase identity; the webhook requires the dedicated raw-body HMAC.
All Razorpay credentials remain private in Secret Manager, not app/source files.

Firebase Hosting is updated at `https://trustkeyper.web.app`. Published
`main.dart.js` matches the completed release build, SHA-256:
`AAF2E832BAA445374F573AE29B901F33D6ABA93CE91ACB919BAD3AB37467B7A7`.

## Evidence

- Analyzer: no issues. Flutter suite: 177 passed; additional captured-receipt
  renderer check: one passed. Backend suite: 92 passed. Emulator rules: 19 passed.
- Live Firebase configured-phone SDK checks: private approvals/demo review/PDF
  access, server-priced TEST order, identical retry, unpaid/forged/outsider denial.
- Official secure SDK checkout/mock-bank TEST success returns a genuine signed
  callback. The backend fetches the captured payment, confirms the exact invoice,
  writes one immutable receipt and reconciles repeat calls to the same payment.
  A fresh quote shows zero deposit and the first month already paid.
- Every temporary Firebase agreement/event/review/invitation/round/payment/intent/
  account/order mapping/admin account/private PDF used by those checks is removed.
  Provider TEST history remains. Existing profiles and authentication settings
  are unchanged; no real-money charge occurred.
- The app's actual PDF generator renders the real captured TEST response. Its
  one-page PDF was visually inspected: warning, IDs, tenant, property, current
  month, deposit/rent/maintenance and total are legible without clipping.
- Fresh anonymous Chrome checks render hosted login, admin login and an invalid
  recipient-link route with HTTP 200 and no JavaScript errors. These are smoke
  checks, not a claim that all authenticated browser journeys are accepted.
- Connected CPH2707: isolated build 23 gallery, first-month/deposit layout,
  November/December/January selection totaling INR 33,000, end-of-lease scrolling
  and explicit no-payment refusal pass. APK has no INTERNET permission.
- Normal phone package remains build 18, last updated 8 October at 23:45:12.
  Only `com.trustkeyper.mobile.uitest` is updated; no original-app data is cleared.

Logs/screenshots are under `output/ui-audit/build23-*`. The sample rendered
receipt is `output/pdf/build23-verified-test-receipt.pdf`, SHA-256
`B2253639B2AEE6AAA01B2E9C62C0B6F88BA15F6E8B7167B9908E3472350187AB`.

## Android artifacts

Normal signed, optimized release AAB:
`C:\Users\ajayb\Downloads\TrustKeyper-v2.0.0-build23-test-payments.aab`

- Version: `2.0.0`, version code `23`; bundle validation passes.
- Certificate SHA-1 matches the Play upload key:
  `94:E2:48:81:D0:EC:4D:EF:34:52:1A:C0:62:82:1C:91:42:89:69:C7`.
- SHA-256: `32A82A523BBAC995CD5A1BD20E1C7B4C6A19872D0D4C56AA7670ECADA90FB2D8`.
- R8 mapping is archived locally. Crashlytics symbol upload remains deferred.
- Install via Play internal testing; an AAB is not directly installable.

Separate offline UI Test APK:
`C:\Users\ajayb\Downloads\TrustKeyper-UI-Test-build23.apk`

- Package: `com.trustkeyper.mobile.uitest`, version code 23.
- SHA-256: `624F52D0BD4FB2C5FFCA7C5DD2AD78CEC6C37F2E2AA0EF9C45C30D45BFB43C2E`.
- No Firebase initialization or network/gateway payment; not a release candidate.

## Still required

The provider-dashboard TEST webhook subscription is not registered; authenticated
Check payment status works without it. Background provider delivery, native
checkout on the normal updated app, real money/compliance approval, refunds,
disputes, brokerage/fees and bank-beneficiary payouts remain release gates.
Fixed-OTP Firebase test identities must be removed/reviewed before public rollout.

The 18 reference exports contain 394 active states: 206 partial, 180 missing and
eight deferred. None has full pixel/interaction acceptance. Full move-in/key
release, inspections, repair quotes/bills, late-rent actions, renewal, move-out,
owner self-onboarding, languages and account lifecycle remain incomplete.
Email OTP remains deferred at the user's request. See
`docs/product-requirements-coverage.md` and the generated design ledger in
`output/design-reference/implementation-audit.csv` for conservative story/state
coverage, and `docs/build23-test-payments.md` for step-by-step testing.
