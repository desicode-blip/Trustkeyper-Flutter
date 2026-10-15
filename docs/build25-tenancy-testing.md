# Build 25 tenancy checks

The normal signed AAB uses Firebase project `trustkeyper`. The separate **UI Test**
app uses offline synthetic data, no Firebase and no INTERNET permission. Never
confuse its paid/active examples with real payments, legal signing or key release.

## Files and entry points

- `C:\Users\ajayb\Downloads\TrustKeyper-UI-Test-build25.apk`: already installed
  as **TrustKeyper UI Test** on the connected OPPO. The original Play app remains
  unchanged. This separate app resets synthetic tenancy examples when a gallery
  example is reopened; it is not a durable Firebase account.
- `C:\Users\ajayb\Downloads\TrustKeyper-v2.0.0-build25-tenancy-renewal.aab`:
  signed normal Firebase app for Google Play internal testing. An AAB cannot be
  installed by tapping it like an APK. No Play upload or replacement of the
  existing app is performed automatically.
- Web: <https://trustkeyper.web.app>. Admin:
  <https://trustkeyper.web.app/#/admin/login>. These use production `trustkeyper`,
  not the offline fixture data.

## Separate UI Test app on the phone

1. Open **TrustKeyper UI Test**, not the existing Play app.
2. Open **Move-in · room photos and meters (offline)**. Check the five steps and
   unpaid tenant count. Hand over keys must remain unavailable.
3. Open Move-in photos, a room and an item. Capture/review the clearly synthetic
   stamped image and save. The item/room count must update, not invent all photos.
4. Open Meter readings. Enter electricity/water readings, use Photo on each and
   review/save. Select No gas if appropriate. Missing evidence must not save.
5. Open **Move-in · broker key confirmation (offline)** from the gallery. Change
   counts and prepare confirmation. Enter `000000`: no completion. Enter the
   offline fixture code `654321`: only the synthetic fixture becomes active.
6. Open **Move-in · tenant key count and code (offline)**. Confirming the displayed
   count is required before requesting a code. This is not an SMS delivery test.
7. Open the move-out notice example. Choose people/date/reason, acknowledge an
   applicable lock-in warning and save. Notice must not report a deposit refund.
8. Open the three Rent follow-up examples. Broker notes need a spoken-to attestation;
   broker extensions also require Owner informed. Owner extension has no red late
   warning. Tenant promises target only their own share and never mark it paid.
9. Open **Renew · saved signed agreement (offline)**. Search by tenant/home, pick
   the synthetic signed source and check the next-day start. Create the separate
   draft and edit the actual wizard. Original documents, legal status and payments
   must not appear verified or paid in that draft.

## Normal app: renewal from a saved agreement

Broker → New agreement → Renew agreement. Choose a genuinely externally signed
home managed by this same approved broker. Review its actual people/rent/deposit
and next-day start, then create the renewal. Repeated attempts or a second device
resume the same private draft, not two renewals. A draft already sent to review
must be opened from Records. Review names/phones, upload fresh required documents
and use the existing versioned reply/review/external-original pipeline.

The old signed record, its legal original, linked customers, tenancy and money
remain unchanged. The renewal has a new private ID and no copied verification,
signatures, replies or paid ledger. Its start cannot overlap the original. This
does not implement full-agreement OCR, old-file/page import, deposit carry-forward
or automatic transition between active tenancies.

## Normal Firebase app: genuine linked home

1. Use a current broker-approved property and a genuinely externally signed original
   published by the admin. Demo agreements cannot open tenancy operations.
2. Broker: Records → signed agreement → Move-in checklist. Owner/tenant: linked
   agreement → Move-in and key record. Missing membership must deny access.
3. Confirm actual physical bedroom/washroom/balcony layout before official photos.
   Layout freezes after the first official item; do not use arbitrary generic photo
   checks to satisfy this checklist. Required items need photos; optional absent
   fixtures need a specific explanation.
4. Capture/review every actual room/item and meter. Readings and received private
   photos must survive reopening/another authorized device. Removed members must
   lose access; stale/retried edits must not overwrite newer values.
5. TEST Razorpay payments **must not** release real keys. The live handover gate is
   unit/emulator-tested with isolated ledger fixtures, not production fake money.
   Real capture requires the separately approved live-provider configuration.
6. With all real gates met on move-in day, broker prepares actual key counts and
   receiving tenant. That same verified tenant opens their account, confirms counts
   and requests the private app code. No provider SMS is sent by this operation.
7. Wrong/expired/other-tenant codes fail. A valid code is single-use; completion
   freezes the baseline, marks the actual home rented and dates the next inspection.
   Five wrong attempts lock the agreement challenge, even if a new one is requested.
8. After real activation, use Rent follow-up/More time or Start move-out. Saving
   these changes produces versioned in-app records, not SMS, legal notice delivery,
   payment, payout, deposit deduction, refund or finished move-out.

## Remaining acceptance boundaries

Old-file renewal/sign-only uploads, owner self-onboarding, full photo comparison and move-out
settlement/dispute/refund, beneficiary verification/payouts, provider reminders,
translations, account lifecycle and all-artboard pixel acceptance remain separate
work. Email OTP is deferred by Ajay. Do not claim the product is 100% accepted.
