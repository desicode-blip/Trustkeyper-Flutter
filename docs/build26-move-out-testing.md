# Build 26 testing

Only **TrustKeyper UI Test** is safe for the following offline phone checks.
Its fixtures do not contact Firebase, send messages, transfer money or hand back
real keys. Reopening a gallery example creates a fresh synthetic scenario.
The original Play application and login remain untouched.

## Phone gallery

1. **Move-out · room comparisons (offline)**: open each room/item, review the
   before/after photos, choose a condition, edit cost/reason and save. Retake
   a TEST photo and confirm it before saving. Open final meters, edit readings
   and add reviewed TEST photos. Missing evidence must produce an error.
2. **Move-out · deductions and handover (offline)**: open Keys back, edit actual
   returned counts, choose the confirming tenant and prepare confirmation. A
   wrong code must fail. The fixture code `654321` works only in this isolated
   scenario. Check deductions, add a reasoned missing-key/utility proposal and
   publish. Completion records physical handover, not a bank transfer.
3. **Move-out · tenant key return code (offline)**: Get my confirmation code
   remains disabled until the tenant checks the exact returned-key counts.
   The displayed private fixture code expires; it is not an SMS OTP.
4. **Move-out · tenant deductions and bank (offline)**: agree or Question item,
   enter at least ten characters, optionally add a reviewed TEST photo and save.
   Choose refund destination; mismatching account confirmation or missing
   own-name attestation must not save. Saved bank details are masked and remain
   pending verification, never automatically VERIFIED.
5. **Move-out · owner report approval (offline)**: review before/after evidence,
   check the review confirmation and approve. Add a missed inspected item and
   explain its proposed amount. It stays pending rather than being silently charged.
6. **Move-out · team disputed item review (offline)**: open the questioned item,
   keep/reduce/remove with a reason. Review a missed-item proposal when present;
   acceptance requires a fresh report review. Request undisputed refund prepares
   only a provider queue entry and must not display money as transferred.

## Normal Firebase route

Use a current externally signed agreement with genuinely linked verified phone
accounts. TEST payment captures deliberately cannot activate a real tenancy or
release keys. Do not change Firestore manually to bypass those gates.

1. Broker/owner/tenant workspace → actual Agreement/Property → **Move-out and
   deposit** → give notice if none exists → **Continue move-out**.
2. Broker records official photos/comparisons, final meters and returned keys on
   or after the move-out day. Tenant opens the same home and confirms counts to
   get their private backend code; broker enters it.
3. Broker publishes; each tenant answers their own items; every owner reviews.
   Admin portal → **Move-outs** → **Open move-out** → review actual disputes or
   proposals. Changed reports require re-consent; stale forms require reload.
4. Tenant supplies their destination privately. Admin prepares an undisputed
   request only when actual captured rent/deposits and physical handover qualify.
   Actual refund processing and final occupancy reconciliation remain unfinished;
   do not interpret `awaiting_provider` or seven-day targets as payment success.

Normal release bundle: `C:/Users/ajayb/Downloads/TrustKeyper-v2.0.0-build26-move-out.aab`.
An AAB is uploaded to a Play testing track, not installed directly like an APK.
The offline APK has a different package and cannot test live authentication/payments.
