# Build 24 implementation and verification

Date: 10 October 2026. This is a verified repairs/roles/property-photo slice,
not a whole-product or pixel-perfect acceptance certificate.

## Implemented

- Server-owned vendor quotes, all-owner consent above ₹2,000, version-bound
  visits, reviewed before/after evidence and bill, immutable completion, and
  tenant working/not-working confirmation. Pending charge records do not deduct
  rent or move funds; live payout reconciliation remains separate.
- Private completion uploads with bounded file signatures, immutable storage
  generations/checksums, membership rechecks, replay protection and audit events.
  Admin orphan issue creation and direct client repair status changes are blocked.
- Authenticated customer role selection/addition without administrator escalation
  or invalidating another device through a global active-session write.
- Private property-photo timeline, approved room-grid icons/layout, new-camera
  capture, actor/start-time image stamp, server receipt time, immutable snapshot,
  authenticated image review and audited support review/repair creation.
- Inspection retry grants are bound to the same linked agreement. Profile and
  agreement access changes invalidate the UI; delayed camera grants/private-photo
  responses from a revoked session cannot reopen evidence after access recovers.
- Recipient collection, external signing/manual original upload and Razorpay
  TEST workflows from earlier builds are preserved. Email OTP remains deferred.

## Validation evidence

- Flutter analyzer: no issues. Full Flutter regression: **191 passed**.
- Backend unit/service suite: **119 passed**. Firestore/Storage emulator rules
  and real transaction/file integration: **25 passed**.
- Deployed normal Firebase phone authentication succeeds for the four configured
  test numbers. Role reading/routing, unauthorized escalation/mutation and
  anonymous denial checks pass without changing their application profiles.
- Deployed private-photo workflow passes normal SDK upload/snapshot/list/download,
  replay/idempotency, direct Storage denial, cross-broker denial, forged review
  denial and anonymous authentication checks. Its explicitly TEST-labelled
  temporary property, photo and upload grant are removed. No signed original,
  payment or real-camera capture is fabricated by that check.
- Repair quote/approval/visit/completion/file access and tenant-outcome behavior
  pass emulator integration. A genuine externally signed agreement is still
  required for full normal-app customer repair acceptance; it was not fabricated
  solely to claim a live signing/repair test.
- Final separate UI Test APK is installed on CPH2707 and its pulled installed
  `base.apk` hash matches the archived APK. Room selection, stamped synthetic
  photo review/save and pending status work. Repair owner approval, private TEST
  bill rendering, tenant confirmation and owner role routing were also exercised.
- The normal `com.trustkeyper.mobile` phone installation remains **build 18**,
  last updated **2026-10-08 23:45:12**. No original app data was cleared.
- Fresh anonymous Chrome contexts render hosted login, admin login, invalid
  recipient link and role-authentication gate with HTTP 200 and no JavaScript
  errors. These are smoke checks, not all authenticated browser acceptance.

Logs, captures and machine-readable evidence are under `output/ui-audit/build24-*`.
Exact manual test steps are in `docs/build24-repairs-and-photos-testing.md`.

## Firebase release

Project: **trustkeyper**. Repair/account-role/photo callables are deployed in
`asia-south1`; production Firestore and Storage rules are released. New callable
transport accommodates the existing Google organization invoker policy without
removing function-level Firebase identity and role checks. Runtime Storage
access is scoped to the corresponding upload/evidence prefixes.

Hosting: **https://trustkeyper.web.app**. The published `main.dart.js` matches
the final normal-app web build, SHA-256:
`B97A711DA47B2CE840AC02CEA720E6576DD7D257AEAAD4D046B3053D23BD5704`.

No GitHub/Vercel release, branch creation, commit or push was performed.
No real-money charge, transfer, legal signing or provider message delivery is
claimed by this release.

## Android artifacts

Normal signed bundle, verified by bundletool and the existing Play upload
certificate: package **com.trustkeyper.mobile**, version **2.0.0**, code **24**.

`C:/Users/ajayb/Downloads/TrustKeyper-v2.0.0-build24-repairs-photos.aab`

SHA-256: `FACA554A4F05634EC04A454D7488AA38B5CFDC99BE00CCD6AEA83BACFF272FA9`.

Separate debug UI Test APK, no INTERNET permission/Firebase initialization:

`C:/Users/ajayb/Downloads/TrustKeyper-UI-Test-build24.apk`

SHA-256: `249FD6E0BE3351C4D1806EECEAD5CACA63C016387FDD293A4D50EAEA28F4B9CA`.

Release mapping is archived at `output/ui-audit/build24-release-mapping.txt`;
build-time Crashlytics symbol upload was deferred. Machine-readable package,
size and checksum evidence is `output/ui-audit/build24-artifacts.json`.

## Still open

The 18 cached design exports contain 438 artboards, 394 active and 44 discarded.
The conservative source ledger marks **217 partial, 169 missing, 8 deferred**;
none has complete state/interaction/pixel acceptance. This is not a percentage
of completed features. Generated evidence is in
`output/design-reference/implementation-audit.csv`.

Whole move-in/payment/key gates, room/item completion and photo comparisons,
scheduled quarterly inspections, renewal/sign-only, owner self-onboarding,
late-rent requests/follow-ups, move-out/refunds/disputes, verified bank/payout
reconciliation, translations, account deletion/security lifecycle and complete
design acceptance remain required. Razorpay webhook dashboard subscription and
real-money business/compliance sign-off remain separate operational gates.
Do not release publicly as a completed product on the strength of this slice.
