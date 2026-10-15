# Build 25: tenancy and saved-agreement renewal

Date: 10 October 2026. This records a tested implementation slice, not a claim
that the whole product or every approved artboard is complete.

## Implemented functionality

- Genuine current signed-original checks, verified participant access and
  all-tenant LIVE captured-deposit/first-rent gates. TEST payments never release
  real keys or create payouts.
- Confirmed physical room configuration, actual item/private-photo progress,
  optional-fixture absence explanations, editable electricity/water/gas readings
  and meter evidence. Official photos are bound to the home, item and revision.
- Broker key counts, designated receiving tenant, authenticated tenant count
  confirmation and a private server-generated app code. Expiry, single use,
  five-attempt lockout, resend bounds and immutable activation are implemented.
  This is not provider SMS delivery.
- Activation freezes baseline evidence and records the next inspection three
  calendar months later. Concurrent form changes require explicit reload rather
  than silently overwriting newer meter, key, notice or rent records.
- Active-tenancy move-out notice, who/date/reason, calendar-month notice and
  lock-in acknowledgment. A notice does not vacate the home or refund a deposit.
- Actual unpaid-share rent follow-up, broker conversation notes, tenant's own
  promised date and owner/broker/admin extensions with owner-informed attestation.
  These never mark rent paid, assess late fees or serve a legal notice.
- Search/review actual broker-owned signed agreements and create one private
  renewal draft per source. The start follows the original end; replay/another
  device resumes the same draft. Original legal record, participants, tenancy
  and money remain unchanged. Documents, replies, signing and payment evidence
  are not copied as verified. The source link, property and start are protected.
- Corresponding offline UI Test examples use conspicuously synthetic records
  and no Firebase/Internet. Normal routes never substitute those examples for
  real accounts, agreement originals or captured money.

## Validation and release evidence

- Flutter analyzer: no issues. Full Flutter regression: **214 passed**.
- Backend unit/service suite: **143 passed**. Firestore/Storage emulator rules
  and actual transaction/private-file integrations: **28 passed**.
- Local checks include key expiry/lockout, malformed/TEST money denial, private
  room/meter evidence, notice/late-rent role boundaries, stale form protection,
  private renewal creation/replay/date protection and removed-session responses.
  Renewal draft edits preserve the backend's frozen start timestamp across
  client timezones, while changed source/home/start values are rejected.
- Production `trustkeyper` tenancy/renewal callables are ACTIVE in `asia-south1`.
  Final Firestore rules are released. The new renewal callable uses the existing
  organization-policy-compatible transport without removing backend identity
  and approved-role checks. Anonymous, missing legal home, role escalation,
  client key-secret reads, fake activation and forged renewal are denied.
- All four configured phone identities pass normal Firebase SDK authentication.
  Deployed checks do not create application records, fabricate a legal original,
  activate a tenancy with fake money or charge a real payment.

- Signed normal AAB and offline UI Test APK: build 25, version 2.0.0. Bundletool
  validation and the expected Google Play upload certificate both pass. The
  normal package has Internet access; the UI Test package has none. Crashlytics
  build-time symbol upload is deferred; the release mapping is archived.
- Firebase Hosting now serves build 25. Its downloaded `main.dart.js` hash
  exactly matches the local release. Fresh anonymous browser checks pass login,
  admin login, invalid recipient-link handling and role authentication gates,
  with HTTP 200 and no JavaScript errors. These are not authenticated acceptance
  tests of every route.
- The actual OPPO CPH2707 runs the final separate UI Test APK. Its installed APK
  hash matches the archive. Device checks pass saved-source renewal/private-draft
  save, editable key counts, wrong-code rejection and synthetic key completion,
  missing-meter-evidence rejection, reviewed synthetic meter photos and editable
  readings retained on reopening, and tenant count consent before code issuance.
  No real login, money, SMS or legal signing is performed by this offline app.
- The original `com.trustkeyper.mobile` Play app remains build 18, last updated
  8 October at 23:45:12. It has not been replaced or cleared. Neither these
  selected phone checks nor the reference captures certify full-device,
  real-provider or pixel-perfect acceptance.

## Release files

| Artifact | SHA-256 |
|---|---|
| `C:\Users\ajayb\Downloads\TrustKeyper-v2.0.0-build25-tenancy-renewal.aab` | `659444443B86B014083D41D4B0023D31EC1E676CD96D2B3D9034C01180D32F3B` |
| `C:\Users\ajayb\Downloads\TrustKeyper-UI-Test-build25.apk` | `FA52D30C98653C11837563CA923DE20F0FE1B380BEA2868FE80845A93006CED3` |
| Local and hosted `main.dart.js` | `F0A1D44D888404DC0E6C543ABBBC789125DC4DE0B6895A6F5B04170C804324E9` |

Hosting: <https://trustkeyper.web.app>. Admin: <https://trustkeyper.web.app/#/admin/login>.
Supporting logs/captures are in `output/ui-audit/build25-*`; artifact, device,
hosting-byte and browser-runtime JSON records distinguish each validation scope.
Exact test steps are in `docs/build25-tenancy-testing.md`. No GitHub/Vercel
deployment, Git commit or push is performed for this release.

## Remaining work

Old-file renewal/import and sign-only upload, full renewal activation/deposit
carry-forward, owner self-onboarding, move-out comparison/settlement/disputes/
actual refunds, beneficiary verification/live payouts, provider notification
delivery, account lifecycle, complete translations and whole-artboard/native
acceptance remain open. Email OTP is explicitly deferred by Ajay.

The reference audit contains 438 boards: 394 active and 44 explicitly archived.
247 have partial implementation bindings, 139 are missing and eight are deferred.
Zero boards are certified as exact pixel matches; these counts are not a feature
completion percentage. Approved references remain unchanged.

Real-money release still needs the approved provider configuration, business/
compliance sign-off and reconciliation. Externally signed genuine legal originals
come from the admin upload workflow, not fabricated fixtures or demo PDFs.
