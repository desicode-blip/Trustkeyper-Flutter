# Build 44 — tenant confirmation, broker records and Route decision

This is a targeted implementation/testing batch, not acceptance of every
active artboard or a real-money launch.

## Tenant confirmation

Approved references 12/04–12/10 now use actual linked agreement data:
home, broker and owners; flatmates; exact personal rent/deposit share; confirmation;
home/flatmate correction; requested share; pending team review; completion.
The server saves/reopens each acknowledgement and checks account role,
membership, pause state, exact money totals and revision. A correction request
does not alter signed legal terms or a payment allocation.

The tenant entry uses one bounded read and passes the actual result into
confirmation, rather than launching two competing requests. Timeout/error
retry, changed membership and stale responses have regression coverage.
Invalid inputs appear next to their fields. No duplicate footer error is added.
The layout supports narrow phones and larger text without currency overflow.

The admin Agreements page has a private tenant home/share correction queue.
An admin cannot resolve a money/membership correction merely by clicking OK.
Resolution requires a newer externally signed matching revision. The full
operational amendment/re-sign/reconciliation workflow remains an open track;
unit fixtures that construct a corrected revision do not prove that workflow.

The four new production callables are active. Firebase's deployment CLI could
not set public invoker IAM under the existing policy; the established transport
configuration enables callable HTTP delivery while backend Auth/roles remain
required. Live checks prove anonymous access and wrong-role queue access fail.
No client rule is added for the private tenantSetups collection.

## Broker records and handoff

References 09/05–09/10 now have actual property/owner/tenant tabs, search,
record detail, contact actions, scoped read-only documents and photo-check entry.
Equal arbitrary property names do not merge different property IDs. An active
tenancy is Rented; a draft is not. Private person/property details refresh while
open and disappear if source access is removed.

Broker earnings require an explicit brokerage recipient. Owner payouts cannot
be counted as a broker's earnings just because the broker is a participant.

Web brokers receive the 01/22–01/23 mobile/desktop app handoff, with their actual
phone, Google Play link, user-initiated app opening and a real QR. The isolated
UI Test package uses a separate app-link scheme. Recipient and admin web routes
remain web routes. Sending an app link opens a composer; it never falsely claims
that a WhatsApp message was delivered.

The unauthenticated public Google Play listing lookup returns 404 during this
batch. This does not establish availability for enrolled internal testers.
Public download/QR acceptance remains a distribution gate until the intended
listing/test invitation is actually reachable for its intended audience.

## Provider decision

Aman confirmed Razorpay Route. Its test-only adapter and read-only readiness
command have six backend tests, including activation, invalid IDs, held
transfers, uncertain responses and settlement/reversal distinctions. There
is no automatic transfer job/client callable yet, and no real provider transfer
is performed. Actual owner/broker Linked Account/product IDs and enabled Test
capability are still needed. See `docs/razorpay-route-integration.md`.

## Evidence available before artifact completion

- 25 focused Flutter tests pass, including five reviewed rendered captures and
  three tenant-entry lifecycle tests.
- All 237 backend tests pass. The Route adapter remains a local foundation,
  not a deployed financial application flow.
- Three live Firebase groups pass using configured normal test-phone OTP:
  exact home/share data, confirmations, idempotency, reopened pending correction,
  unchanged agreement terms, stale revision and private/wrong-role guards.
  All temporary agreements/acknowledgements/audit rows are removed.
- Device preflight detects the unlocked OnePlus and no active call. The original
  app is already version 43 when this batch starts; the user has updated it since
  the earlier version-37 baseline. Its new baseline hash is recorded before any
  separate UI Test update. Do not repeat the obsolete claim that it is still 37.

## Final artifact and release verification

All 394 Flutter tests pass and analysis reports no issues. The signed AAB
passes bundle structure, package/version, Internet permission, Play upload
certificate and cryptographic signature/signed-entry checks. The source
snapshot is unchanged throughout tests and builds.

Bundle: `C:/Users/ajayb/Downloads/TrustKeyper-v2.0.0-build44-testing.aab`
SHA-256: `DB21D829294F14BF6731A345C575BBC6A6409B07C8EEEADD35F2BB4503A0FC2D`.

Offline APK: `C:/Users/ajayb/Downloads/TrustKeyper-UI-Test-build44.apk`
SHA-256: `3D1431746EA6208BC70A75968027AE55C09D23A1CD73E1E2149A04E78C8AFD7C`.
It has no Internet permission. Crashlytics symbol upload is deferred and the
release mapping is archived.

Production Hosting build 44 is released; index/bootstrap/startup/main bytes
match the final local build. Five actual hosted startup/retry regressions pass.
The 237 backend tests are local; live tenant callable checks remain the three
explicit scenario groups, not a fabricated full-provider payment acceptance.

The normal phone app remains build 43. Its final APK hash/update timestamp
match the preflight baseline. The phone is being used, so neither app is
updated and no foreground/chat interaction is interrupted. Physical build-44
UI acceptance remains pending; prior offline fixture checks do not certify it.

The shareable guide is
`C:/Users/ajayb/Downloads/TrustKeyper-build44-testing-guide.md`.
Evidence: `output/ui-audit/build44-artifacts.json`,
`build44-source-snapshot.json`, `build44-device-check.json`,
`build44-hosted-assets.json` and `build44-after-startup.json`.
