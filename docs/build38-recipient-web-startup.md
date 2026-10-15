# Recipient link startup hotfix — web audit 38

Published to Firebase Hosting project `trustkeyper` on 12 October 2026.
Audit 38 identifies this web verification run, not a new Android bundle.
The existing build-37 AAB remains the Android testing artifact; recipients do
not need an app update to get the hosted fix.

## Diagnosis and fix

The reported card is the application bootstrap failure, before the recipient
request or broker identity is read. The old published build reproduces that
card with a 24-second Firebase SDK download and when browser session storage
throws. These are reproduced failure conditions, not a recovered exception
trace from the original affected recipient's phone.

The official Firebase JS modules now load before the short app-initialization
deadline, with a separate 120-second preparation limit. Core loads first,
followed by service modules, and its global becomes available only after the
whole preparation succeeds. The version matches the resolved FlutterFire
dependency; the release script checks this before building.

Throwing storage getters and read-only/full storage use per-page memory for
SDK configuration. Working browser storage and existing data are left alone.
The isolated recipient Firebase app chooses non-persistent authentication in
that situation. Normal recipients retain tab-only authentication. A restricted
browser may ask for phone verification again after a reload; no static OTP or
authentication bypass is added.

Slow loading is no longer declared fatal after 30 seconds. Genuine startup
failure offers Try again. The fallback route and retry preserve the original
document link, including its fragment, instead of dropping into the main app.
Legacy service-worker recovery also preserves it and avoids a reload loop
when session storage is blocked.

No broker-specific exception, authentication configuration, security-rule,
backend function, DNS or Vercel change is used.

## Final published verification

- All 325 Flutter tests pass; analysis has no issues; the release web build succeeds.
- The bootstrap regression and Firebase SDK-version checks pass.
- The served index, bootstrap, Firebase preparation script and main JS match
  the local release bytes exactly.
- Five hosted startup scenarios pass: fresh mobile browser, 24-second SDK
  delay, unavailable session storage, read-only storage, and real startup
  failure followed by retry. The error screen retains the document URL even
  before retry, so browser refresh does not lose the request.
- Two configured broker test-phone identities each pass nine live Firebase
  scenario groups and eight mobile-browser recipient cases: owner and tenant
  links under fresh, slow, storage-denied and read-only storage conditions.
  The correct broker and recipient phone render; private uploads are not
  exposed before verification.
- The live API checks retain wrong-phone and private-data denials, real
  synthetic document uploads, immutable broker-readable snapshots, whole
  document bundles, idempotent submission, saved flow recovery and private
  upload notifications. Both runs remove their temporary records and files.
- Five additional hosted login/auth-gate routes render without JS errors.

Evidence is in `output/ui-audit/build38-*`, especially
`build38-hosted-broker1-web-links.log`,
`build38-hosted-broker2-web-links.log`, `build38-after-startup.json`,
`build38-hosted-assets.json` and `build38-final-hosted-smoke.log`.
Browser tests use fresh Chrome mobile-emulation contexts, not every physical
browser/device. No actual SMS/WhatsApp message, real personal document,
real-money transaction or physical push-delivery claim is involved.

## Recipient retest

Close the failed page and reopen the original received link. If the connection
temporarily fails, use Try again; it keeps the same request. Valid existing
links do not need regeneration for this fix. An expired or revoked link still
requires a new invitation from the broker. Never share private invitation
tokens in logs or public reports.

This is a scoped startup/recipient-access fix, not whole-product acceptance.
