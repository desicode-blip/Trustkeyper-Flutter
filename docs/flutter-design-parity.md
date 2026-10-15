# Flutter design parity — 7 October 2026

## Current audit — 9 October, build 21

`docs/build20-design-and-device-audit.md`, `docs/build21-repair-photo-audit.md` and
`output/design-reference/implementation-audit.csv` supersede this document's
older implementation-status table. The new ledger maps every one of the 438
artboards to a real component or an explicit gap; it does not count generic
journey descriptions as completed screens. None is certified pixel-perfect.

## Baseline and acceptance

The user supplied 18 HTML exports from Aman’s `TrustKeyper — Rent Agreement
Mobile Flow · v2 (29 Sep 2026)` artifact. They contain 438 reference artboards.
Exports 13 and 14 are the discarded sets (44 boards), leaving 394 active
references. Active references include alternatives, web/desktop layouts, error
states and later-feature notes; these are not 394 separate native routes.

The original export files were not present in Downloads on 9 October, and
`D:\Trustkeyper\Artifacts` was empty. All 18 extracted exports and their
438 local screenshots remain available in `output/design-reference`.
`extract-claude-artboards.py`
records SHA-256 hashes and unpacks HTML, images and fonts without executing
export scripts. `render-claude-reference.cjs` renders only local files, disables
page JavaScript and blocks HTTP(S). `audit-claude-designs.py` creates a local
reference gallery and `output/design-reference/coverage.csv`, with one row for
every reference. `output/design-reference/native-review.html` pairs 16 native
test captures with their reference states for manual comparison. Fixture values
and error/selection states are not always identical. The large generated outputs
are ignored by Git.

No reference currently has final visual or updated-device acceptance. Matching
copy, using correct assets or passing overflow tests is not a pixel-parity claim.
Fixtures from artboards must not become invented live people, homes or payments.

## Build 19: document-link increment (9 October 2026)

The broker's owner/tenant paper step now has separate Add/Send link actions for
Aadhaar, PAN and bank proof. Request and recipient routes have live Firebase
scope, OTP, upload, receipt and retry behavior rather than static links.
Recipient previews and the invalid-link recovery state were rendered at
440 × 956; this verifies loading/control availability, not exact pixel parity.
The sender-channel dialog and per-paper recipient layout still need comparison
against the full approved alternative states and physical-device acceptance.
There is no claim of zero mismatches across all 18 exports. The user-supplied
`D:/Trustkeyper/Artifacts` directory was empty when inspected; cached approved
exports and the supplied screenshot are the available references for this work.

## Coverage by export

| Export | Boards | Scope | Current Flutter state |
| --- | ---: | --- | --- |
| 01 | 23 | Common authentication | Shared visual foundation and onboarding/login/OTP/paused UI updated; profile email binding implemented locally; deployment, multi-role and error-state parity pending |
| 02 | 24 | Admin workspace | Existing live Firebase workspace; full visual comparison pending |
| 03 | 31 | Broker new agreement | Native entry choices and property journey added; remaining parties/documents/terms still generic |
| 04 | 29 | Bank, UPI and secure links | Generic prototype; bank verification, provider delivery and secure-link backend pending |
| 05 | 18 | Tenants, rent and brokerage | Generic wizard; multi-party forms, date/amount policy and payer splits pending |
| 06 | 21 | Review, edit and send | Generic prototype; native preview, edits and authoritative approvals pending |
| 07 | 20 | Signing and move-in | Generic journey; trusted manual-signing completion and move-in workflow pending |
| 08 | 18 | Renewal and sign-only | Designs available; generic prototype is not accepted parity |
| 09 | 31 | Broker tabs | Broker profile/agreements/payouts read live data; floating navigation updated; property/people records and remaining states pending |
| 10 | 22 | Owner login and documents | Generic link/upload states; real upload and token validation pending |
| 11 | 31 | Owner dashboard | Preview shell; participant-scoped real data and individual states pending |
| 12 | 30 | Tenant web | Preview shell; participant-scoped real data and individual states pending |
| 13 | 22 | Discarded broker flow | Retained for traceability; not shipping scope |
| 14 | 22 | Discarded review flow | Retained for traceability; not shipping scope |
| 15 | 19 | Owner/tenant agreement approval | Generic journey; real approvals and document access pending |
| 16 | 28 | Move-out | Generic journey; notices, inspections and backend settlement pending |
| 17 | 29 | Owner self-onboarding | Generic journey; property and admin review workflow pending |
| 18 | 20 | Late rent | Generic journey; server-ledger obligations and reminders pending |

## Changes made in this pass

- Extracted exact logo, onboarding/choice/navigation/property SVGs and Roboto
  fonts from the exports. Corrected shared colors, spacing and CTA shapes.
- Added the skyline login hero, four vector onboarding pages, approval status
  handling and paused-account screen. Approval reads update without restarting
  streams, fail closed on errors and do not claim unverified channels are verified.
- Corrected the profile/role screens' fixed bottom actions, exact role SVGs,
  circle treatments and selected state. Profile setup now requests a
  same-UID-bound email OTP before role
  selection; already-verified emails continue without a redundant code.
- Replaced the old broker home layout with the approved blue agreement card,
  white start button, vertical house/tenant tiles, orange bank reminder and help
  strip. Greetings still use the persisted account name. No sample agreements or
  notification counts are inserted into live accounts. Unconnected notifications
  and unsupported languages now explain their limitation instead of silently
  doing nothing or opening the design catalog as if it were a live inbox.
- Added native broker new/renew/sign-only entry choices and the property journey:
  searchable actual properties, address, optional size/direction, parking, rooms,
  floor counts, furnishing, inventory, custom items and saved summary.
- Rebuilt the agreement introduction with the exported step icons, colored
  badges, decorative stars and dotted curved timeline. The timeline adjusts for
  smaller screens and enlarged text instead of hiding required labels.
- Physical-device testing exposed an Agreements navigation label breaking across
  multiple lines. Navigation now keeps every complete label on one line within
  its allotted width; regression checks cover 440, 363 and 320 logical pixels.
- Added a Firestore property repository and pass property IDs plus snapshots into
  agreement drafts. Property edits leave participant IDs and broker ownership
  untouched. Save failures preserve the entered draft and never show success.
- Added layout checks at 440×956 and 320×640 with enlarged text, plus tests for
  approval changes, property validation, failed-save retry and existing-property
  edit behavior. These tests use fake repositories, not production writes.

## Known gaps and constraints

- The remaining owner/tenant shells use sample data; payment checkout is a local
  test simulation. These are not provider-complete features and cannot ship as live
  money/account data. No payment or document-signing provider call was made here.
- The broker Add tenant entry still opens the agreement starter rather than a
  standalone multi-tenant record editor. Bank entry remains a prototype. Matching
  home-card appearance does not imply these downstream flows are complete.
- Profile email OTP must verify the same Firebase UID as phone login. Do not solve
  this by writing `emailVerified` from the client or replacing the phone session
  with a separate email account. Resend sending, backend secrets and deployed
  functions still require verification in an authorized test environment.
- Storage provisioning and authenticated upload/download must be verified before
  document collection, photo checks and signed-PDF delivery are accepted.
- Signing remains admin/manual upload with broker/customer review, per the
  existing project decision. Provider automation is not assumed. Inventory
  extraction remains inventory-only with review and explicit save, even where
  an artboard suggests reading a complete old agreement.
- Broker-owned property writes still require approved/unpaused status under the
  server rules. No production Firestore data, rules, credentials or deployments
  were changed during this audit.

## Connected Android phone

The connected CPH2707 phone has Google Play build 15 installed. Its app-signing
certificate differs from the local upload certificate. A locally signed APK
cannot safely replace it. Do not uninstall, clear app data, change signing keys
or discard the existing session to bypass this.

With the user's explicit approval, a separate **TrustKeyper UI Test** build 16
(`com.trustkeyper.mobile.uitest`) was installed. It has no Android INTERNET
permission or Firebase initialization provider. Authentication previews are
read-only; interactive properties use an in-memory repository. The original
`com.trustkeyper.mobile` package remains build 15 with its existing update time
and was not uninstalled, cleared or replaced.

Device inspection covered the gallery, role/login previews, broker home, the
agreement introduction and the property journey. An offline property with address, room/furnishing selections
and inventory was saved and carried into the explicitly local-only result.
This is not real authentication, storage, payment or full-app acceptance. See
`docs/flutter-ui-test-app.md` for the test app's limitations and usage.

## Local validation

- Flutter analyzer: no issues.
- Flutter tests: 107 passed, including demo agreement snapshots, linked-record demo reading, participant session isolation, private-document operations, profile routing/recovery, normal-width and enlarged-text layouts,
  accessible role selection, live approval revocation, failed-save retry and
  preservation of property data.
- The native agreement wizard now captures multiple owners/tenants, exact rent
  and deposit shares, calendar terms and separate brokerage. Saved private drafts
  reopen with revision protection. Legal documents, delivery and consent are not
  implemented by these summaries; full visual comparison remains pending.
- Saved drafts now support separate broker-private document slots with image
  review, explicit confirmation, progress and replace/delete. PDF page review,
  participant links and admin verification remain pending. The Storage emulator
  could not start with Java 17; deployed access rules are not accepted by these
  widget tests. The offline gallery exercises only a labelled in-memory fixture.
- Email OTP backend tests: 26 passed, including five-minute expiry, fifteen-minute lockout, cooldown, attempt limits, same-UID profile binding,
  failed delivery and single-use consumption.
- Android debug compilation is for local validation only; it is not a Play-signed
  internal-testing release, full-app acceptance or proof of deployed providers.
- Only the separately identified offline UI-test app was installed on the phone.
  No production writes, original-app replacement, release upload or signing-key
  change was performed. All remaining parity requirements above still apply.

## Completion gate

The current demo preview fills validated draft terms and highlights captured or
changed fields. It is explicitly not signable or legally approved. Normal owner
and tenant tabs use linked live-record lists instead of sample financial facts;
those lists still require replacement/acceptance against the detailed approved
dashboard designs and real ledger operations. These additions do not constitute
whole-product visual acceptance.

Every applicable active reference needs a real route/state mapping, exact native
assets/copy/layout comparison, large-text/keyboard checks, true persisted behavior
and failure/retry coverage. Follow the broker agreement path through parties,
documents, terms and review first, then backend approvals/manual signing and
move-in, then broker tabs, owner/tenant flows and lifecycle states. Run full
automated validation and review the updated Play build on the connected phone.
Do not call the app complete until the coverage ledger has explicit visual and
functional acceptance for all shipping states.
