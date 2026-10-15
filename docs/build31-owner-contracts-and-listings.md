# Build 31: owner contracts, listings and tenant selection

Version 2.0.0+31 is an incremental testing release. It is not a certificate that
all 85 product stories or all 394 active artboards are complete or pixel-accepted.

## Implemented workflows

- Actual owner contract terms are reviewed in full, then accepted with two
  explicit confirmations and fresh Firebase phone reauthentication on the same
  account. Email login or an old phone session cannot stand in for that fresh
  proof. Acceptance records the immutable document hash and offered fee version.
- Admins privately upload the actual externally completed signed original after
  reviewing every page and recording its external reference. Identical unsigned
  source bytes cannot be published as a signed original. The customer sees the
  contract status/copy, not an admin-upload processing screen.
- The signed owner-service contract enables the owner's listing workflow; it
  does not sign a tenancy agreement, charge money or release keys.
- Owners review the public title, locality, actual photos and rent details, then
  explicitly publish a real Firebase-hosted listing. Private nicknames, owner
  contact details, full door addresses, contracts and other applicants are not
  included in the public response. Pause blocks subsequent public reads.
- An interested tenant opens the listing in a mobile browser, verifies their
  phone using Firebase and submits household/work/move-in details without
  installing the app. The sign-in/account-switch effect is explained first.
- Verified-phone views are deduplicated; these are not claimed to be a total
  count of every anonymous website visitor. Interests and confirmed visits are
  actual saved events, not example cards or generated statistics.
- Identity verification requires actual team review and an evidence reference.
  Changing the applicant's name, household or work invalidates that check.
  The owner can confirm a future visit, decline or select a checked applicant.
- Selection pauses the listing. Admins may link only an existing agreement
  matching this property, owner and chosen tenant, with both verified accounts
  already granted actual participant access. Unshared/cancelled records are
  rejected; normal private review links remain the path before account linkage.
  The owner's agreement entry
  filters to that linked record rather than opening an unrelated agreement.
- A tenant can use the original link and phone verification to read their own
  enquiry status, even after the public listing is paused. Selected/declined
  messages do not incorrectly say the enquiry is still awaiting selection.
- Actual reviewed team property photos can be privately uploaded from the admin
  portal. Live listings must be paused before the photo set changes; the owner
  must approve publication again.
- Open participant detail routes are bound to the account that opened them.
  Signing out or changing accounts hides the old record, including nested
  document/payment/inspection routes. Detail records follow the live authorized
  query; revoked access or query errors hide previously displayed data.
  Nested routes/dialogs are dismissed as well, so a child preview cannot remain
  above a hidden parent. Four regressions exercise both stacked routes and modals.

## Local verification

- 520 checks pass: 276 Flutter, 201 backend and 43 actual Auth/Firestore/Storage
  emulator checks. Flutter analysis reports no issues.
- Emulator checks exercise real private Storage grants, immutable PDF/image
  snapshots, token removal, wrong-user/role/type/size rejection, corrupted PDFs,
  fresh consent, publication, interest, actual review, selection and private
  paused-listing receipts. Test fixtures stay in the emulator, not production.
- Actual Flutter-rendered fee, listing, interested-tenant and selection screens
  are saved under `output/ui-audit/build31-ui-owner-*.png`. The visual harness now
  loads the app's actual bundled General Sans currency fallback, rather than a
  host-system font. These captures are not all-artboard acceptance.
- The design inventory is conservative: 298 partial, 96 missing active boards,
  44 archived boards and zero boards certified as fully accepted.

## Test this release

Use clearly labelled TEST addresses, photos and documents. Never upload real
Aadhaar/PAN/bank documents merely to test the interface. Do not attest to legal
signatures or identity checks which have not actually been completed.

1. Install the normal signed build through your Play testing track. An AAB is an
   upload bundle, not an APK that can be installed by tapping it. Do not replace
   the existing phone app with the separately labelled offline UI Test preview.
2. Owner: open Home/Properties → Add a property. Complete the five saved steps,
   choose a plan and request the free home check. Leave and reopen once to verify
   the property resumes with the saved details.
3. Admin portal: Properties → Owner setup. Confirm the actual assigned check.
   After that check has occurred, record its evidence and current fee offer.
4. Admin: open the same saved property and publish the actual owner contract
   terms using the PDF review action. Review every page and enter the reference.
   Do not use the signed-original action yet.
5. Owner: reopen the property, read every page, confirm both checkboxes and press
   Agree and sign. Enter the newly received phone OTP. Retry an incorrect code
   once: it must not accept the contract or silently change accounts.
6. Verify the owner sees Agreement confirmed, not an already signed original or
   active tenancy. Finish actual external signing separately. Only then may the
   admin publish the checked genuine signed owner contract with its reference.
7. Owner: refresh and read the signed copy. Choose Find a tenant. Review/add the
   actual property photos, enter a public home title and locality, and explicitly
   approve the public details/photos before Put it live.
8. Copy the listing link and open it in a separate browser/profile. Confirm that
   no owner phone, private document, full door address or applicant list appears.
9. Tenant: choose I am interested, verify the tenant phone, then enter name,
   household, work and intended move-in date. Submit once. Reopen/verify the same
   phone: the existing private enquiry should appear, not a duplicate applicant.
10. Admin: review the actual applicant's identity evidence and record the check
    reference. Before this check, owner selection must remain blocked.
11. Owner: refresh → See interested tenants → the actual applicant. Confirm an
    actual future visit, or choose the checked applicant. Verify the listing
    pauses and no tenancy/payment/key handover is recorded by selection alone.
12. Tenant: reopen the original link and choose Check my existing enquiry. Verify
    the same phone. The selected status remains readable while public listing
    content is unavailable; a different phone must not see this receipt.
13. Prepare/review the normal actual agreement through the existing broker
    workflow and finish its verified participant-account linkage. Before that,
    use the broker's private review links. Admin may link the agreement ID only
    when property/owner/tenant match and both participants actually have access.
    A cancelled or merely unshared draft must be rejected. Owner → See the
    agreement must show that specific linked record.
14. Test refresh/retry, expired OTP, paused account, changed terms, changed
    applicant details, wrong account and signing out with private screens open.
    A stale revision must request refresh, never overwrite another person's work.
    Leave a property/payment detail open in another tab when switching accounts:
    the old account's detail must disappear. Removing its participant access must
    also hide a detail which was already open.

## Remaining release gates

- All active artboard comparisons and physical Android acceptance remain open;
  ADB currently detects no phone. Widget/emulator checks are not device tests.
- Actual beneficiary verification, refunds/payouts/reconciliation and business
  approval are required before real-money release. Razorpay TEST receipts are
  not live rent, deposit, payout or key-release evidence.
- Old-file renewal, complete Hindi/Telugu, pre-existing account collision/contact
  recovery, reviewed deletion/retention, remaining admin security/fee operations,
  signing-party delivery/receipts and notification-provider delivery remain open.
- Team-created property/owner review and other unimplemented approved states are
  tracked in the design inventory; existence of a generic route is not coverage.
- Rotate the Resend credential exposed earlier in chat, remove the configured
  fixed-code Firebase test identities before public release and complete release
  monitoring/symbol-upload checks. No secret belongs in source or this report.
- Firebase Hosting's standard domain is used. Custom-domain DNS, Vercel, GitHub
  and Play publication are not changed by this local build.

## Delivered testing artifacts and deployment

- Signed normal bundle: `C:/Users/ajayb/Downloads/TrustKeyper-v2.0.0-build31-testing.aab`.
  Package `com.trustkeyper.mobile`, version 2.0.0+31; bundle validation, freshness,
  Google Play upload-certificate match and cryptographic signature checks pass.
  SHA-256: `2CAE3B58F54ACF8A17792C1F0D0CA1650B0F7ED021CC0C1BE9FDFA4606AA03FA`.
- Offline preview: `C:/Users/ajayb/Downloads/TrustKeyper-UI-Test-build31.apk`.
  Separate package `com.trustkeyper.mobile.uitest`, version 2.0.0+31, no Internet
  permission and no live Firebase data. This is not the functional testing app.
- Shareable guide: `C:/Users/ajayb/Downloads/TrustKeyper-build31-testing-guide.md`.
- Owner functions and Firestore/Storage rules are deployed on `trustkeyper`.
  All six new callable transports are ready; 20 anonymous checks pass (19 private
  calls denied, nonexistent public listing rejected). No authenticated production
  fixture writes were performed by these checks.
- Firebase Hosting at `https://trustkeyper.web.app` serves the final exact index,
  bootstrap and main JS bytes. Deployment and checksum evidence is saved under
  `output/ui-audit/build31-*`; this is not authenticated device acceptance.
- No phone installation, original-app replacement/data clearing, Play upload,
  GitHub push, Vercel release or DNS change was performed. Crashlytics mapping
  is archived; symbol upload remains deferred. Whole-product acceptance is open.
