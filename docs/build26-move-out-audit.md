# Build 26: move-out and working journey navigation

Date: 10 October 2026. Email OTP remains deferred at Ajay's request.
This is implementation evidence, not whole-product or pixel-perfect acceptance.

## Implemented

- Saved notice and actual signed-home/verified-role checks precede every action.
  Booking saves the requested date/window, not a fictional confirmed appointment.
- Frozen move-in room evidence is compared with new private move-out photos.
  Every item records same/repair/damaged/missing, a proposed integer-paise cost
  and explanation. Final meter readings require new meter photos and cannot
  move backwards. Missing-key/utility proposals require their actual evidence.
- Returned-key counts cannot exceed the original counts. The designated tenant
  confirms them and receives a private backend-generated app code; expiry,
  resend limits, single use and persistent five-attempt lockout are enforced.
  No SMS delivery is asserted. Wrong-code retries do not count as successful saves.
- Publishing freezes a versioned report and splits costs exactly by the actual
  captured deposit shares. Each departing tenant agrees or questions their own
  share, optionally attaching private evidence. Every linked owner reviews it.
- Owners can propose an actually inspected missed item. Admin accepts/reduces
  or rejects it with a reason. Accepted changes archive the old report and
  require fresh owner/tenant responses; pending proposals prevent premature
  refund preparation without silently becoming deductions.
- Admin can keep/reduce/remove questioned items with an evidence-based reason.
  Disputed/unanswered amounts remain held; undisputed amounts remain separate.
- Tenants select the original payment method or submit an own-name bank account
  for provider verification. Only the tenant sees the masked destination; full
  account data, key secrets and refund requests are inaccessible to direct clients.
  The destination locks once its refund request is queued.
- Physical handover is distinct from settlement. Rent continues until actual
  recorded handover, not merely the planned notice date; subsequent administrative
  settlement delays do not invent additional recurring-rent gates.
- Admin can queue one verified undisputed refund request only after physical
  handover, every owner's review and all departing tenants' captured rent.
  Its status is `awaiting_provider`, never paid/transferred. No property is
  marked vacant or legal tenancy terminated by a physical-handover click.
- Owner/tenant agreement, signing, setup and repair entry routes now open their
  real linked workspace rather than a disconnected sample journey. Agreement
  details expose move-out and rent follow-up. The journey directory opens
  implemented routes and preserves explicit boundaries for unfinished flows.

## Verified evidence

- Flutter analyzer: no issues. Flutter regression: 225 passed.
- Backend service/unit regression: 154 passed. Firestore/Storage emulator
  rule and actual transaction/file integrations: 29 passed. Total: 408.
- The integration test uses isolated `demo-trustkeyper-rules`, immutable actual
  emulator file generations and read-before-write transactions. Synthetic LIVE
  ledger fixtures exist only inside tests; production receives no fake money.
- Production `trustkeyper` move-out callables are ACTIVE in `asia-south1` and
  Firestore rules are released. Organization-compatible callable transport is
  enabled without removing application identity/role checks.
- All four configured test phone accounts pass ordinary Firebase authentication.
  Anonymous requests, other-role escalation, missing genuine homes, direct
  private destination/code/refund reads and forged client activation are denied.
  Production verification creates no application records or financial records.
- Widget evidence covers compact layouts, editable costs/readings/bank fields,
  key attestation, stale-version reload, revoked-session privacy, owner proposals,
  team decisions and identical-payload retry after a lost response.
- Approved export 16 supplies the move-out reference. Checklist progress, pills,
  next action, circular header controls and compact broker deductions follow its
  design tokens. Actual states and necessary safety disclosures differ from
  example data; all 394 active artboards are not certified visually accepted.

The signed build-26 AAB and separate offline APK are archived in Downloads.
The installed UI Test APK exactly matches the archived APK. Broker report
publication, tenant key attestation/code and owner report layouts were checked
on the CPH2707 phone. The original build-18 app and update time remain unchanged.
Firebase Hosting serves the exact verified build-26 bytes; four fresh anonymous
web routes render without JavaScript errors. Evidence is recorded separately in
`output/ui-audit/build26-artifacts.json`, `build26-hosted-bytes.json`,
`build26-web-runtime.json` and `build26-device-evidence.json`.

## Still required for whole-product acceptance

Actual provider refunds/beneficiary verification, financial reconciliation and
final tenancy/vacancy transitions are not implemented by a queued request.
Remaining broader work includes owner self-onboarding/listing/manager callbacks,
sign-only/old-document renewal, full renewal activation/deposit carry-forward,
broker collections/payouts, complete translations, account deletion/recovery,
provider notifications, and per-artboard/mobile/web acceptance. Native gateway,
business/compliance and genuine legal-original acceptance remain separate gates.
Email OTP is deliberately last. GitHub and Vercel were not changed.
