# Build 30: owner setup and signing-only workflows

This is an incremental testing release, not a claim that all product stories or
all 394 active artboards are finished or pixel-accepted. Version 2.0.0, build 30,
is now signed and archived as a testing release.

## Release evidence

- Normal signed bundle: `C:/Users/ajayb/Downloads/TrustKeyper-v2.0.0-build30-testing.aab`.
- Separate offline preview: `C:/Users/ajayb/Downloads/TrustKeyper-UI-Test-build30.apk`.
- Package/version, Google Play upload certificate, bundle validity, source
  freshness and the preview's absence of Internet permission all pass verification.
- Production Firebase project `trustkeyper`: 14 new owner/signing endpoints,
  private Firestore/Storage rules and indexes are deployed. All 14 endpoints
  reject unauthenticated requests with Firebase SDK errors, not exposed records.
  Storage runtime access is limited to the four new private object prefixes.
- Firebase Hosting at `https://trustkeyper.web.app` serves byte-identical index,
  bootstrap and main-JavaScript files from the verified build. Custom-domain DNS,
  Vercel and GitHub are unchanged; no Play upload or phone installation was made.
- 494 automated checks pass: 263 Flutter, 191 backend and 40 actual
  Auth/Firestore/Storage emulator checks. The analyzer reports no issues.
  These are separate from the 14 production unauthenticated-access checks.
- Two actual Flutter-rendered entry layouts are saved as
  `build30-ui-owner-step1.png` and `build30-ui-signing-entry.png`. The offline
  browser verifies navigation/editing, but browser screenshots were unavailable.
  ADB detects no phone; neither this nor the widget tests certify all-device or
  exact-artboard acceptance.

## Implemented

- Broker: New agreement → Sign only now opens editable page capture/PDF upload,
  page review, owner/tenant/witness details, review and a server-confirmed receipt.
  Every page must be reviewed; duplicate signer numbers and incomplete parties
  are rejected. A connection retry keeps the same operation, without duplicate
  requests or silently changing the reviewed content.
- Camera-JPEG conversion respects all eight EXIF rotations/mirrors and safely
  copies pooled byte buffers before PDF embedding. Parser bounds, transforms
  and actual JPEG-to-PDF conversion have regression checks; this is not yet a
  physical-camera acceptance test.
- Broker: Agreements → Signing-only progress shows actual saved requests and
  stages. Source pages and completed originals use private authenticated reads.
- Admin: Agreements → Signing-only requests records real stamp/signing stages.
  Only an externally completed PDF, checked by the admin for all parties, can
  complete the request. Re-uploading identical unsigned source bytes is blocked.
  No test receipt or demo PDF activates a tenancy or records a real payment.
- Owner: Home or Properties → Add a property saves five editable steps: address,
  rooms, features, rent/deposit and photos. Completed steps resume on another
  device. Up to five reviewed private photos, or a team-photo request, are saved.
  A saved property does not claim an existing tenancy or public listing.
- Owner: choose DIY/full service and request a free visit/video check. This is
  explicitly a request until the admin records an actual assigned appointment.
- Admin: Properties → Owner setup records the actual manager, date, time and
  booking reference. After the confirmed check has occurred, an admin can record
  an evidenced 5–20% fee offer with version and effective date. The owner sees
  that actual offer. It is not a signed contract or an applied payment charge.
- Private screens discard old form state on account changes and hide records
  when the session ends. Cross-account access, version conflicts, immutable
  upload snapshots, exact file metadata and private reads are enforced by the
  backend and Firestore/Storage rules, not just hidden buttons.

## Testing steps

Use synthetic documents and addresses only. The separate **UI Test** APK uses
offline fixtures, not live accounts, emails, payments or Firebase uploads.
The normal AAB needs installation through a Play testing track or bundletool;
an AAB cannot be installed directly by tapping it. This release does not replace
or clear the existing app on Ajay's phone.

### Normal Firebase app

1. Sign in as the approved test broker. Choose **New agreement → Sign only**.
2. Upload a synthetic unlocked PDF or clear page photos. Cancel a review once:
   Next must remain blocked until every page is reviewed.
3. Enter synthetic owner/tenant names and the configured test phone numbers.
   Try a duplicate number; correct it before sending.
4. Send once, then open progress. Check one real received request and readable
   source pages. Test offline failure/retry without generating duplicates.
5. In the admin portal, open **Agreements → Signing-only requests**. Record each
   actual external stage in order with its evidence reference. Do not record
   legal signing that has not happened.
6. For test acceptance only, use a clearly marked TEST PDF actually signed by
   consenting test participants after reviewing it. Verify the broker sees the
   exact private copy. Do not tick real signing attestations for an unsigned
   file; use the offline preview/emulator fixtures for that demonstration.
7. Sign in as the owner. Open **Add a property**, enter a TEST address, save two
   steps, leave and reopen. Check saved values remain editable.
8. Complete rooms/features and enter rent/deposit in rupees, not paise. Invalid
   floors, counts and money must not be accepted by the server.
9. Add clear TEST photos or request team photos. Save the property. It must not
   appear as rented or as a public listing just because it was saved.
10. Select a plan and future check slot. The screen must say **Check requested**.
11. Admin → **Properties → Owner setup**: confirm an actual assigned check.
    Refresh the owner screen; check the saved manager/time, not example names.
12. After the real check, record the fee offer and evidence. A 4%/21% fee,
    past effective date, stale revision or owner impersonation must fail.
13. Confirm the offer displays without claiming contract signature, active
    listing, rent capture, deposit release or payout.
14. Sign out/change accounts with a private screen open. The previous account's
    form/document must disappear. Retest phone/email login to the same linked UID.

## Acceptance still required

- Final owner contract consent and listing/tenant-selection lifecycle, including
  verified documents and real listing/visit statistics.
- Broker/owner verified beneficiary accounts, actual refund/payout processing,
  financial reconciliation and business approval before real-money release.
- Old-file renewal completion without unauthorized full-agreement OCR.
- Signing-only party delivery/receipt acceptance and remaining associated states.
- Complete localization, contact/account recovery, reviewed deletion/retention,
  remaining admin security/fee workflows and actual notification delivery.
- Physical-device journeys and visual comparison of every active artboard, not
  merely successful compilation or widget tests. The coverage inventory marks
  implemented subsets **partial** until their acceptance is actually completed.
- Rotate the Resend key previously exposed in chat before public release.
- Remove/disable fixed-code Firebase test identities before public launch, and
  review production domain routing and the deferred Crashlytics mapping upload.

Release logs, checksums and deployment evidence are saved under
`output/ui-audit/build30-*`. Successful automated checks are release evidence,
not substitutes for whole-product acceptance or actual legal/financial actions.
