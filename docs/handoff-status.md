# Handoff Reconciliation

## Mac/iOS repository preparation (15 October 2026)

Ajay requested publication to `desicode-blip/Trustkeyper-Flutter` so the same
Flutter/Firebase app can be built on the Mac. Version 2.0.0+47 keeps one set of
screens/assets/workflows and the existing project/bundle identity. Flutter
3.38.6 is pinned; the Dart lockfile is enforced. CocoaPods, all three native
configurations, camera/photo declarations, phone-auth callback, app-open scheme,
push/background capabilities and App Attest entitlements are prepared.
Broker FCM lookup waits for APNs and discards late tokens after account changes.

The repository is public. A clean source export excludes previous Git history,
private credentials, build/customer data and local operational instructions
containing configured live test accounts. Unit/emulator fixtures remain
synthetic. No Firebase deployment, DNS, billing, phone installation, Apple key
upload or store publication is authorised as a side effect of this code push.

Mac setup and shared-flow acceptance: `docs/ios-macos-setup.md`. An actual Xcode
build, Apple team/provisioning, APNs console configuration and physical iPhone
acceptance are still required; Windows checks do not certify these. Existing
full-suite document-state clock failures and other product limitations remain
open, and historical build-46 binaries are not version-47 builds.

## Flutter/Firebase-only checkout (15 October 2026)

At Ajay's request, the legacy application and its dependencies/build setup are
removed from the active primary checkout and migration worktree. Continue in
`D:\Trustkeyper\Project`: `apps/flutter_app`, `functions` and root Firebase
rules/configuration are authoritative. No Git branch/history, remote service,
production data, DNS or installed phone app was changed by this cleanup.

The 362 non-generated code/asset/test files in the build-46 snapshot are unchanged;
its other 40 entries are disposable historical test-difference images, not app
inputs. Future release snapshots exclude those generated failure images;
the build-46 AAB/APK and four retained web assets retain their checksums.
Downloads files were no longer present at the final audit, so the matching
native build outputs are retained in the primary project's
`output/releases/build46` with the testing guide. Their original hashes verify.
The upload key is preserved in the private user signing store, independently of
the old Expo tree. Root npm/editor commands now target Flutter/Firebase only.
See `docs/legacy-stack-retirement.md` for the recovery backup and boundaries;
`output/maintenance/legacy-retirement-verification.json` records fresh checks.
Analysis, 257 backend tests, 51 emulator tests and five cleanup checks pass.
The full Flutter suite has 406 passes and 14 failures, all in the document-state
test file. Its countdown failure also reproduces in the unchanged migration
source: fixed October-13 test clocks still reach a real-clock expiry getter.
No application source or golden baseline was changed to hide those failures;
fixing that existing test-clock issue is outside this stack-removal change.
This cleanup does not certify remaining product/design acceptance or payments.

## Build 46 verified account email edit (13 October 2026)

Existing-email replacement was still blocked by build 45's intentionally strict
onboarding binding. A separate account-edit challenge now verifies the new
inbox, original Auth identity, recent customer login and address uniqueness,
updates that same UID, and refreshes its session. Onboarding/admin protections
stay in place. Roles, verified phone and agreement membership are retained.

420 full Flutter tests, 257 backend tests and 51 complete Auth/Firestore/Storage
emulator tests pass (728 total); the 75 focused checks are a subset, not extras.
Two new bounded account
email callables are published; anonymous guards deny requests without sending
mail or changing accounts. Analysis is clean; final signed AAB/isolated APK,
unchanged-source verification, four matched hosted assets, five browser routes
and five startup/storage/retry cases pass. Four configured phone accounts pass
production read-only guards. Evidence is in `output/ui-audit/build46-*`.
Guide: `docs/build46-testing-guide.md`; binaries and guide are in Downloads.

The initial full Flutter run exposed a one-second cooldown golden difference.
An injected test clock now keeps fixture timestamps and countdown rendering
deterministic, while real-app clocks still advance normally. No baseline image
was regenerated to conceal a layout mismatch. See the elapsed-time regression.

Build 45's isolated APK passed bounded physical profile/details/save-reopen,
help, logout cancellation and closure checks. Original normal build 43's APK
hash and update time remained unchanged. Real-inbox email replacement through
the new release still needs internal-test acceptance; emulator acceptance is
not a claim that a real recipient opened their inbox. The phone disconnected
before the final build-46 installation check; its new APK is not installed.

Razorpay remains deferred. Full Hindi/Telugu, mandatory server-enforced admin
MFA/lockout, corrected signed amendments/reconciliation, identity-recovery
variants and complete active-board acceptance remain open. No 100% claim.

## Build 45 account batch (13 October 2026)

Real saved details, normal same-account verified-email addition, help/logout and
guarded customer closure/restoration replace inert profile controls. Seven new
Firebase account callables and closed-access rules are published; normal Auth,
role and recent-login checks remain. Four configured test-phone identities pass
read-only production checks. No production customer closure/restoration or
financial mutation is exercised. An emulator-only real Auth/Firestore lifecycle
passes through disable, denied login, restoration and the same customer UID.

The final bundle is rebuilt after the offline closure return-path regression.
Use `output/ui-audit/build45-artifacts.json`, its source snapshot and final logs,
not an earlier artifact's checksum. Guide: `docs/build45-testing-guide.md`.
The phone subsequently reconnected and the isolated APK passed bounded offline
account checks. Original normal build 43 remained unchanged. Existing-email
replacement is the build-46 fix, not an accepted build-45 operation.

Razorpay stays deferred. Full Hindi/Telugu, signed-amendment/reconciliation,
remaining lifecycle variants, retention-policy/personal-erasure acceptance and
whole-product design/device acceptance are still open. Do not claim 100%.

## Build 44 implementation batch (13 October 2026)

Aman confirmed Razorpay Route. The selected-provider decision is recorded in
`docs/razorpay-route-integration.md`; test Linked Account/product readiness,
actual beneficiary mappings and complete transfer/refund reconciliation remain
open. The test-only adapter has no automatic client-facing financial entry.
No real money is moved and no bank verification is fabricated.

Tenant linked-home/flatmates/rent-share confirmation now persists/reopens actual
agreement data and correction requests. Four production callables are active,
with normal Auth/role guards and private acknowledgement storage. Three live
normal configured-phone-OTP scenario groups pass and remove their temporary
records. Admin resolution checks a newer actual signed revision; the full
operational amendment/re-sign/reconciliation workflow is not yet accepted.

Broker Records now uses real searchable properties/owners/tenants with private
read-only documents, photo checks, and live source/access removal. Owner payouts
are excluded from brokerage earnings without an explicit brokerage recipient.
Approved mobile/desktop broker web handoff includes an actual QR, app-intent
fallback and user-initiated link composer; public Play availability remains
unverified (an unauthenticated listing lookup returns 404).

All 394 Flutter tests and 237 backend tests pass; analysis is clean.
Firebase Hosting build 44 is published with all four checked assets matching the
final local bytes. Five hosted startup/retry regressions pass, including slow
load, unavailable/read-only browser storage and preserving the original link.
The signed build-44 AAB and separate offline UI Test APK are archived in
Downloads. Bundle structure, upload certificate, cryptographic entry signatures
and unchanged source snapshot are verified. Physical build-44 UI checks remain
pending: the phone is in use and its foreground is not interrupted.
At preflight the original phone app is already build 43,
not the older build-37 baseline; its new APK hash is saved before the separate
UI Test update. The final original-app version, timestamp and APK hash still
match that baseline. Neither phone package is updated by this batch.

This is not acceptance of all 394 active artboards. See
`docs/product-completion-plan.md`, `docs/build44-tenant-confirmation-and-records.md`
and `docs/build44-testing-guide.md`.

## Tenant documents and optional LinkedIn (build 43, 13 October 2026)

The current Aman artboard includes LinkedIn as an optional fourth tenant
detail; the older export omitted it. Broker Add/Send link, waiting, received,
change/delete and skipped states now use persisted private request data.
Recipients can add or skip a profile after the requested phone's normal OTP.
Tenant document pages use the tenant-specific request and Upload controls.

File selection no longer waits for another proof-read network round trip.
Private acceptance still rechecks phone/revision/scope on the backend.
Bounded request/verification waits, generation-safe reloads and cancellable
file selection prevent a stalled operation from permanently freezing the
page. All 369 Flutter tests and all 225 backend tests pass; analysis is clean.
The five affected document callables are deployed to production Firebase.
Both brokers also pass 12 live server scenario groups each, including bundled
documents, plus 12 total real browser OTP/upload/LinkedIn cases. The final
build-41 correction scopes LinkedIn deletion correctly even inside a bundle
and labels it as a profile rather than a photo.
Build 42 also clears a pending picker when a link or recipient identity
changes, preventing stale cancellation controls from freezing a replacement
invitation. Physical-device checking additionally corrects cramped contact
details, clipped adjacent person tabs and compact action spacing. Final
Android/Hosting evidence uses build 43.
The signed build-43 AAB is archived in Downloads and Firebase Hosting matches
the final web bytes. The connected phone's isolated UI Test APK matches its
archive; owner received, tenant waiting/received and the editable LinkedIn
dialog are checked. The original phone app remains version 37 with its APK
hash and update timestamp unchanged. Native production authentication/uploads
and Android push delivery are not established by the offline fixture checks.
Hosting, signed artifacts, both-broker live checks and phone evidence are
tracked in `docs/build40-tenant-documents-linkedin.md`. No whole-product 100%
acceptance claim follows from this targeted correction.

## Recipient web startup hotfix (12 October 2026; web audit 38)

The Firebase-hosted recipient page no longer puts slow SDK downloads inside
the short app-initialization deadline or crashes on denied/read-only browser
storage. Restricted recipients use a page-only auth session; normal recipients
keep tab-only persistence. Phone verification and private document scopes are
unchanged. Startup failure and retry preserve the original document URL rather
than losing it to the main-app route. Slow loading is not an automatic failure.

All 325 Flutter tests pass and analysis is clean. Final published asset bytes
match the release build. Five hosted startup/retry cases and five additional
auth-gate routes pass. Two configured broker identities each pass nine live
Firebase scenario groups and eight owner/tenant mobile-browser cases, with
all temporary records/files removed. No original-phone app update, new AAB,
function/rule deployment, credential change, Git push, DNS or Vercel operation
is performed. The build-37 AAB remains the Android artifact; audit 38 is a
web hotfix, not an Android version increment. Recipients should reopen their
original valid invitation. See `docs/build38-recipient-web-startup.md`.

## Inline validation without duplication (build 37, 12 October 2026)

The user requested removal of the repeated bottom error box when editable
fields already show their errors. Owner/tenant/money/date/brokerage steps now
show inline guidance only. Read-only review retains correction navigation;
opening a correction replaces that summary with the current fields' inline
messages. Missing dates in resumed periods open the actual date controls.
The final optional-property-text rule from build 36 remains unchanged.

All 15 targeted regressions and all 319 Flutter tests pass; analysis is clean.
The signed build-37 AAB and isolated APK are archived in Downloads, with an
unchanged-source snapshot and verified Play upload signature. Firebase Hosting
matches the build-37 web bytes. The installed UI Test APK matches its archived
SHA-256; fresh phone XML shows one name error, one phone error and no repeated
footer. Correcting the synthetic owner opens the working document step. The
original build-33 app and its update timestamp remain unchanged.
See `docs/build37-inline-field-errors.md` and
the build-37 guide in Downloads. Build 36 is superseded for error presentation.

## Fully optional property text (build 36, 12 October 2026)

The user clarified that name/address/flat text may all be blank; `rjh` or any
other arbitrary property label also works. No required-label, minimum-length,
format or free-text uniqueness check remains. Foreign property IDs and active
tenancies are protected independently of labels. Other field/type/payload
validation remains intact. Blank cards use a display placeholder, not an
invented stored address. Name-only owner properties preserve the supplied name.

All 215 backend tests and all 318 Flutter tests pass; analysis is clean. Two
live Firebase document-link runs pass all nine scenario groups each, once with
blank property text and once with `rjh`; temporary records/files are removed.
All 26 affected functions are ACTIVE, and their deployed source archives match
the three changed local backend modules byte-for-byte. Firebase CLI reports an
IAM warning for the test webhook's public binding; its existing
`invokerIamDisabled` transport is already enabled, and an unsigned callback is
correctly rejected with HTTP 400. No IAM policy/role change or real payment was
needed. The build-36 signed artifacts are archived and superseded by build 37
for error presentation. Builds 34/35 are also superseded.
See `docs/build36-optional-property-labels.md` and the build-36 guide in Downloads.

## Short flat names/addresses (build 35, 12 October 2026)

The user explicitly withdrew the eight/ten-character address minimum. Broker
properties, agreement checkpoints, owner onboarding, document requests and
shared review snapshots now accept short non-blank text such as `A` or `402`.
No flat/building/area format is forced. Optional flat name remains optional.
Payload-size/ownership guards and other field validation are unchanged.

The clear field errors and Fix actions remain. Fourteen targeted Flutter checks
and all 213 backend tests pass. The affected backend callables, updated web
build, signed Android artifacts and fresh phone checks are being completed.
Build 34 is superseded; do not distribute it as the address-rule fix.
See `docs/build35-short-addresses.md` and the build-35 guide in Downloads.

## Agreement field guidance (build 34, 12 October 2026)

The property and draft checkpoint address rules now agree. The old generic
invalid-progress warning is replaced by specific missing/incorrect field
guidance, inline field errors and a rounded footer card using existing design
tokens. Fix navigates to the correct person/step and focuses or scrolls to its
field. The property editor returns to the same draft, retaining owner count and
entered people. Partial progress still saves without requiring future steps.
Operational connection/approval/concurrent-edit failures remain truthful errors.

Thirteen targeted new regressions pass, including 320/363.4/440-pixel layouts,
keyboard insets, address correction, optional email, tenant 2 field targeting,
and correction of tenant 2 money fields with only one owner. Non-party step
navigation keeps a valid person checkpoint rather than introducing a new
invalid-progress failure. All 316 Flutter tests pass and analysis is clean.
Signed Android artifact verification and phone checks are pending.

No backend function or security-rule change is needed. The original phone app
baseline for this turn is build 33; only the isolated UI Test package may be
updated. See `docs/build34-field-validation.md` and the build-34 testing guide
in Downloads. This is a validated field-guidance fix, not whole-product
pixel-perfect or production acceptance certification.

## Broker draft recovery and upload updates (build 33)

Build 33 restores unfinished broker agreements from Home and Agreements →
Drafts, preserves the exact owner/tenant and saved stage, and adds the approved
Updates layout with real unread receipts. A successful owner/tenant document
submission atomically creates one private broker receipt. Duplicate completion
preserves its read state; partial/failed uploads do not claim success.
Opening an unfinished agreement's upload update redirects to that exact person's
approved document step, rather than inserting a different upload interface.
Changed-person, deleted and obsolete-revision requests fail safely.

Firebase `trustkeyper` has the updated completion callable, Firestore rules and
new Firestore-created notification trigger deployed. The runtime has the narrow
messaging permission. Navigation no longer removes the registered device;
logout unregisters it and invalidates its messaging token. Pushes contain a
generic document-received message, not identity/bank details. Invalid devices
are disabled and transient delivery retries avoid already-accepted devices.
The inbox is persistent regardless of operating-system notification permission.

559 automated checks pass: 303 Flutter, 210 backend and 46 real
Auth/Firestore/Storage emulator checks. The analyzer is clean. Nine live
Firebase scenario groups pass, including same-UID broker session reopening,
saved draft recovery, exact-person private upload receipts, read-state
preservation and deployed trigger processing. Temporary fixtures/files are
removed. Physical Android push delivery is not implied by the server checks.

Firebase Hosting's final index, bootstrap and main bytes match build 33.
The signed AAB and isolated offline APK are verified and archived in Downloads.
The source snapshot is unchanged throughout tests and builds. The upload
certificate and bundle signature are verified. AAB SHA-256:
`67F9E0841216C618591157FCCAC54EFEF384399A825C6FA9B119F8C5FBA9BC87`.
Source snapshot SHA-256:
`F3125D985FF6CB12C1CA7AF27DEBBA48830621AD2F5566DA013CFCB52C5B5BDB`.

The connected OnePlus passes five scoped native preview checks: single-row
agreement filters, saved draft reopening the tenant document step, an upload
update opening the matching owner, sharing controls and interactive Aadhaar
add controls. Its installed UI Test APK matches the final archived APK exactly.
The original phone app remains build 32 with its original update time unchanged;
only the separate offline UI Test package is updated. The normal build-33 app
still requires Play internal-test distribution before authenticated device and
operating-system push acceptance. Crashlytics symbol upload is deferred;
the release mapping is archived.
See `docs/build33-broker-drafts-and-updates.md`, the build-33 guide in Downloads,
and `output/ui-audit/build33-*`. This is scoped document-flow recovery, not
whole-product pixel-perfect certification. No Git push, Vercel/DNS change,
original-app reinstall, Play publication or real payment is performed.

## Current Flutter/Firebase follow-up (11 October 2026)

Build 32 source adds the broker-to-owner/tenant whole-document web journey and
approved upload/share controls. Phone OTP stays backend-driven; request scope,
immutable private snapshots and session-change clearing remain enforced.
Typed bank/UPI data is validated and private, not provider-verified.
The test plan is `docs/build32-owner-document-links.md`. 536 automated checks
pass (287 Flutter, 205 backend, 44 real Auth/Firestore/Storage emulator checks)
and the analyzer is clean. A visual regression caught clipped owner tabs;
width now follows the actual approved font metrics while preserving selected
chip centering, and both owner labels render without ellipsis.
The offline recipient preview now injects synthetic PDFs for both photo/file
actions instead of opening personal camera/file pickers. A regression covers
all four recipient request scopes. Production pickers remain unchanged.

The five document callables and Storage rules are deployed on production
`trustkeyper`. Seven live test scenario groups pass with the configured Firebase
test-phone accounts: private invitations, wrong-phone denials, two-page Aadhaar,
single-paper PAN/bank, four-page tenant bundles, owner bundles with captured
typed bank data, and file-free typed UPI. Immutable snapshots are read by the
requesting broker, forged completion overrides cannot replace captured data,
and temporary fixture records/files are removed. These are actual backend
checks, not proof of external-message delivery or full browser/device acceptance.
See `output/ui-audit/build32-firebase-document-roundtrip.log`.

The signed normal build-32 AAB and separate offline APK are archived in Downloads.
The package/version/upload certificate, cryptographic signature, permissions and
bundle validation pass. The unchanged 284-file app/test/asset/config snapshot is
`45D6DE539DE8C21B7F2C8C3030849047F233EF7A24E88461B54CE507A27F631B`.
Normal AAB SHA-256 is
`E1EA226D9E116638D05A229BCFCD48259501AF430E10F3D0CF7F1B5C560AF9F7`.
Firebase Hosting matches the final index/bootstrap/main bytes; web main SHA-256 is
`EBECF1F25A55240D51B32E5BB1F26E60280A0E9FCAF292C1B8CC101F55A6DCF8`.

Android initially rejected the final preview update. A subsequent install succeeds
without changing global app protection. The installed UI Test APK matches final
SHA-256 `32A67B8A137ED447298CB713E966B7C5434B22292DAA405D7AD6DA726A16F091`.
The original `com.trustkeyper.mobile` remains build 30 with its prior update time.
Native offline checks and fresh UI dumps are recorded separately; these do not
certify the normal AAB, live message delivery or whole-product visual acceptance.
The final APK passes synthetic recipient front/back/PAN review and typed bank
form required/mismatch/correction checks through the local submission receipt.
Eight saved UI-state assertions verify completeness and submit-button gates.
Build/deployment and final device evidence are under `output/ui-audit/build32-*`.
The release wrapper refuses to archive artifacts when the tracked app-source
snapshot changes during testing or builds. Crashlytics symbols remain deferred
with mapping archived. No Git push, Vercel/DNS change or Play upload is made.

### Prior build 31 (historical evidence)

Build 31 implements private owner contract terms, fresh same-account Firebase
phone consent, genuine externally signed-original publication, owner-approved
real listing/photos, tenant browser enquiries, actual evidence-based review and
visit/selection, paused private status receipts and matching agreement linkage.
The owner agreement deep entry selects the actual linked record. No tenancy,
legal signature, payment or provider notification is fabricated by these steps.

520 local checks pass (276 Flutter, 201 backend, 43 actual emulator checks); the
analyzer is clean. Actual four-screen Flutter renders and rule/security results
are under `output/ui-audit/build31-*`. Coverage remains 298 partial/96 missing
active boards, plus 44 archived boards; none is certified fully pixel-accepted.
See `docs/build31-owner-contracts-and-listings.md` for test steps and boundaries.

Firebase CLI login is restored. The owner backend and Firestore/Storage rules
are deployed; all six new callable transports are ready. Twenty anonymous
production checks pass (19 private calls denied, missing public listing denied).
Participant detail routes now hide stale records on account changes, access
revocation and query errors, including stacked child routes and modal previews.
The signed normal AAB and isolated offline APK are archived in Downloads;
version/package/signature/freshness/permissions and bundle validation pass.
Normal AAB SHA-256 is
`2CAE3B58F54ACF8A17792C1F0D0CA1650B0F7ED021CC0C1BE9FDFA4606AA03FA`.
Firebase Hosting matches the final index/bootstrap/main bytes; web main SHA-256
is `412B1B9C35781902786DDB6DD33FCA397F2ABE10697C2A74B11F48EF2DBB55E1`.
Evidence is in `output/ui-audit/build31-artifacts.json`, `build31-hosted-assets.json`
and the corresponding validation/deployment logs. The build-31 testing guide is
in Downloads. ADB reports no device, so no phone installation or physical-device
acceptance is claimed. Crashlytics symbol upload remains deferred, with the
release mapping archived. Existing app,
Vercel, GitHub, custom-domain DNS and Play publication remain untouched.

## Current Flutter/Firebase follow-up (10 October 2026)

Build 30 adds private signing-only agreement imports and five-step owner
property setup, including reviewed photos, plan/check requests, actual admin
appointment confirmation and evidenced fee offers. These are saved backend
workflows, not static preview cards. Private files are served through authorized
calls without public Storage download tokens. Anonymous production checks caught
a missing-grant photo-completion error; it is fixed with authentication before
the grant lookup and a regression test. See `docs/build30-owner-and-signing.md`
for testing instructions and the deliberately unfinished contract/listing and
other whole-product acceptance requirements. Production/test artifact evidence
is recorded under `output/ui-audit/build30-*`; the coverage inventory remains
conservative: 290 partial and 104 missing active boards, plus 44 archived boards.
No whole-product or all-artboard acceptance is claimed.

Build-30 release validation passes 494 automated checks (263 Flutter, 191
backend, 40 real Auth/Firestore/Storage emulator checks) and a clean analyzer.
Camera-page conversion now handles JPEG EXIF rotations/mirrors and pooled buffer
offsets. The signed normal AAB and isolated offline APK are archived in Downloads;
Firebase Hosting matches the final index/bootstrap/main bytes. Backend/rules and
indexes are deployed on authorized production `trustkeyper`; no live payment,
Git push, Vercel/DNS change, Play upload or original-phone-app update was made.
ADB detects no phone for this release. See `output/ui-audit/build30-artifacts.json`
and the build-30 release guide for evidence and the remaining acceptance gates.

Ajay now confirms email OTP sign-in succeeds. This supersedes the unresolved
production-login report below; it is user-reported acceptance. Build 29 adds
email-first Firebase phone-credential linking on the existing UID, alongside
the phone-first verified-email binding already present. Both directions have
actual SDK/Auth-emulator same-UID checks; collision/session protection and
profile routing are tested. See `docs/build29-account-linking.md`. Build/release
validation passes 464 checks (253 Flutter, 175 backend, 36 emulator), with a clean
analyzer. The signed build-29 AAB and isolated APK are archived in Downloads;
Firebase Hosting matches the final web bytes. No phone installation, Git push,
Vercel/DNS change or functions/rules deployment was made. Whole-product acceptance
remains open; see `output/ui-audit/build29-artifacts.json` for artifact evidence.

The September GitHub/Vercel/Supabase notes below are historical. Ajay's current
work continues locally on the Flutter/Firebase migration worktree, with
Firebase project `trustkeyper` as the authorized deployment target. No GitHub
push, commit, Vercel deployment or staging release was made for build 28.

Build 28 enables real email OTP and same-UID phone-profile email verification,
strict linked-phone authorization, functional remember-login preferences,
splash retry and callback rescheduling/contact recovery. 455 checks pass:
245 Flutter, 175 backend, 35 Auth/Firestore/Storage emulator checks; analyzer clean.
See `docs/build28-testing-release.md` and `docs/email-otp-setup.md` for current
artifacts, deployment/runtime evidence, exact testing steps and public-release
gates. Real inbox acceptance and key rotation remain separate checks. No ADB
phone was detected for build 28; the existing app was not replaced or cleared.
The previous build's installed-device results below are historical, not build-28
physical acceptance. Whole-product/design acceptance is still not certified.

The browser email request now succeeds after fixing stale Cloud Functions web
plugin registration with a clean dependency-resolved build. A real inbox
challenge is open for Ajay to enter the code; this is provider acceptance,
not yet proof of inbox receipt or successful production custom-token login.
The release script and artifact checks guard against missing web registration.
Actual verification then exposed missing Auth user-management permission. The
reviewed lookup/create/update-only runtime grant is now assigned, and a fresh
challenge is awaiting user entry. No broad Editor/Auth Admin role was granted.
Ajay subsequently reports continued OTP login failure. The newest challenge
remains sent, with zero incorrect attempts and no newly created Auth identity.
The original agent-owned browser tab no longer exists after interruption.
The active device/page and exact error are needed to distinguish an older
client/challenge from server failure. This is not a passed production login.

Build 27 added secure owner manager callbacks and the actual admin queue,
assignment, confirmation and outcome workflow. It extends build 26's move-out
workflows. Its signed normal AAB and separate offline APK are archived in
Downloads. Firebase Hosting and callback functions are deployed; hosted bytes
match the final build. The original Android app remains build 18. Only the
isolated offline UI Test package was updated on the connected phone.

425 automated checks pass, along with a clean analyzer, five anonymous browser
routes, production authentication/access-denial checks and selected offline
callback phone interactions. Detailed current evidence and test steps are in
`docs/build27-manager-callbacks.md`. This is not whole-product acceptance:
`docs/product-requirements-coverage.md` and the design coverage audit retain the
remaining owner onboarding/listing, identity, renewal, financial reconciliation,
notifications and full-design/device acceptance work. Build 28 supersedes only
the earlier email-OTP deferral; the other open requirements remain.

## Historical September reconciliation

Checked 2026-09-11 against Sumit's 2026-08-19 handoff, fetched Git refs and
code, and the authenticated GitHub, Vercel, Supabase, Sentry, and Play Console
dashboards. Production remains unchanged and no live payment was initiated.

## Current release state

- `main` remains at `0a23e3a`.
- PR #271 (server/API Sentry monitoring) merged to `staging` as `4f7b20f` after
  all four checks passed. The resulting Vercel staging deployment is Ready.
- PR #275 (renewal and calendar-month rent billing) merged to `staging` as
  `6afe36f` after all four checks passed. The resulting Vercel staging deployment
  is Ready.
- The additive renewal migration
  `20260817155535_lease_agreement_renewal_link.sql` was applied only to Supabase
  staging (`jvupbmmzyxizjwjjfrac`). The column, lookup index, and unique active
  renewal index were queried afterward and all were present.
- PR #277 (broker payout setup, Payments tab, and consultancy-fee copy) was
  updated onto `6afe36f`. Its only merge conflict retained `Consultancy fee`.
  Deployment typechecks, 311 API tests, and 431 mobile tests passed locally;
  GitHub CI and both Vercel checks passed. It merged to `staging` as `46e1c76`,
  and the resulting Vercel staging deployment is Ready.
- PR #278 is this documentation-only reconciliation and must be updated onto
  the final staging commit before it is merged.

## Implemented agreement and payment rules

- Agreements use calendar-month rent periods, not anniversary-to-anniversary
  months. A lease beginning September 10 bills September 10-30 and allows five
  days to pay. Full later months bill from the first through month end with the
  same five-day grace period.
- An agreement ending August 10 bills August 1-10. If its renewal begins August
  11, the renewal bills August 11-31 using the renewal agreement's rent.
- Split-month amounts use each agreement's monthly rent and the actual number of
  calendar days. Paise rounding preserves the exact monthly total when adjacent
  periods have the same rent.
- Renewal creation is signed-only, links the new draft to its source agreement,
  prevents duplicate active renewals, clones the required agreement data, and
  returns to the existing review/signing flow.
- Owner/tenant portal list and detail access are signed-only; unfinished original
  agreements and renewal drafts are hidden.
- Rent checkout, portal display, and payment history share the server-calculated
  periods and preserve paid/settled history.
- Broker payout setup and the Payments tab are now in staging. Razorpay Route
  broker recipients must be activated before consultancy-fee checkout can work.

## Signing decision

- Automated digital signing and Leegality are deferred.
- The broker completes and shares the document for customer review. After all
  parties approve, Aman/admin stamps it manually, uploads the final signed PDF,
  and delivers it to the customer or broker.
- Broker self-declaration of signed status is rejected by the API. Admin upload
  is the completion path.

## Verification completed

- Combined pre-merge validation passed: 311 API tests, 204 web-app tests, 431
  mobile tests, 45 marketing tests, deployment typechecks, app/API build,
  marketing build, and required artifact checks (991 tests total).
- After the final #277 rebase, deployment typechecks plus all 311 API and 431
  mobile tests passed again.
- Fresh Vercel previews exposed strict TypeScript inference gaps in the Sentry
  callbacks that local CI had missed. The callbacks were explicitly typed and a
  subsequent Vercel preview passed before #271 was merged.
- The Android device was previously authorized with TrustKeyper 1.0.0
  (versionCode 6) installed. It was no longer visible over USB/ADB when the final
  staging deployment became Ready, so physical-device regression remains pending
  reconnection.

## External readiness

- Vercel invoice $47.20 is paid with $0 due. Supabase invoice $41.30 is paid.
  New Git-triggered previews and staging deployments are working again.
- Ajay's Vercel team entry is Developer. The earlier Viewer warning on old PR
  comments is historical.
- Supabase staging contains the brokerage/portal migration and the renewal-link
  migration. Production must not receive migrations until a separate approved
  staging-to-main release.
- Sentry has IP-address storage prevention enabled. Preview still lacks the
  server `SENTRY_DSN`, `SENTRY_ENABLED`, and controlled-probe variables, so live
  API ingestion and source-map resolution remain unverified.
- Play Console closed testing 1.0.0 (version code 6) is active with 14 email-list
  testers. The production-access questionnaire must use factual tester
  recruitment, engagement, and feedback answers.
- App Store Connect work remains deferred at Ajay's request.
- Razorpay dashboard configuration review remains deferred. Code uses Razorpay
  Route, and transfer webhooks should be checked before production promotion.

## Remaining release order

1. Reconnect the authorized Android device and run the broker payout/Payments and full
   agreement/review/manual-signing/payment/renewal staging regression.
2. Merge this documentation update to staging after its checks pass.
3. Prepare a staging-to-main pull request with exact database migration and
   rollback notes.
4. Obtain explicit production approval before applying production migrations or
  merging to `main`, then verify the released app and stores.
