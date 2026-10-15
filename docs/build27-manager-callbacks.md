# Build 27: owner manager callbacks

Email OTP is deferred. Build 27 extends build 26; it is not a claim that all
85 stories or 394 active artboards have passed acceptance.

## Implemented

- Owner Home/Profile opens the real manager-support page. Owners without a
  broker-linked home can still request help, without gaining property access.
- Add-property, plan/fee and find-tenant topics; available India-time call
  windows; registered verified phone; cancel and reschedule are server-owned.
  Working hours are 9 am–8 pm. Requested slots are not fictional bookings.
- The admin portal's Owner callbacks section shows actual requests. Select an
  owner, assign an active real team member and publish their actual work phone
  and company email. No sample “Anita” is inserted into Firebase.
- Confirm a specific future time inside the requested window. Record an actual
  completed/no-answer call only after that time. Missed owners can re-request.
  Reassignment invalidates prior confirmation. Events retain actual outcomes.
- The owner sees the assigned manager and actual confirmed slot; call/WhatsApp/
  email open the corresponding composer. Nothing is automatically sent/called.
- Backend role, paused-state, phone-provider and Firebase Auth phone checks;
  bounded request frequency; optimistic versions; exact-payload idempotent retry;
  private assignments, rate-limit and operation/audit records. Replaying an old
  operation returns current state, not an obsolete confirmed time.
- Revoked login clears contact/phone fields. Edited forms cannot overwrite new
  backend versions. Lost responses retain the identical operation for retry.
- The separate offline gallery includes request, confirmed and missed-call
  scenarios. Synthetic contacts cannot dial or message. The original app remains
  untouched. Reference: approved export 17, artboards 19, 20 and 29.

## Test the normal Firebase flow

1. Owner phone login → Home → Our manager can do it for you. Alternatively,
   Profile → Your TrustKeyper manager.
2. Choose the topic and an available time, then Call me. Expect Call requested,
   not a confirmed appointment. The phone is the actual verified account phone.
3. Team login → Owner callbacks → select this owner → Open owner support.
   Choose an active manager, enter their published work phone and company email,
   and Assign manager. These must be real operational contacts, not test samples.
4. Confirm call time using the India-time picker. Stay inside the owner's requested
   date/window. The owner now sees the real manager and confirmed time.
5. After actually calling at/after that time, enter an outcome. Record no answer
   or Record completed call. These buttons do not make phone calls themselves.
6. After no answer, the owner chooses a new slot and Call me again. It returns
   to requested until the team reconfirms. Cancel callback stops an open request.
7. Use Change time to reschedule. Two-device edits must produce a reload warning,
   not overwrite the other device. A connection failure offers Retry same request.

The callback page intentionally uses only the verified phone. Changing an
account's verified phone remains a separate identity-lifecycle requirement.
Never dial Firebase's synthetic test numbers or describe an offline call outcome
as a real call. Use the isolated fixtures/emulators for those outcome tests and
a genuine owner contact for operational calling.
Provider notifications/automatic calling, full owner property/plan/listing setup,
and every-artboard pixel acceptance remain open. No payment/refund is invented.

## Verified release evidence (10 October 2026)

- 231 Flutter tests, 163 backend tests and 31 actual Firestore/Storage emulator
  rules/integration tests pass: 425 total. Flutter analyzer reports no issues.
- All three production callback functions are ACTIVE. Normal Firebase configured-
  phone authentication passes for the four test accounts. Anonymous calls,
  customer-to-admin escalation and private assignment/audit writes are denied.
  This production check creates no callback, property or financial records.
- Firebase Hosting is deployed and its published JavaScript SHA-256 matches the
  build artifact. Five anonymous web routes are checked separately; they are not
  authenticated whole-product acceptance.
- The connected CPH2707's isolated build 27 renders confirmed/missed scenarios,
  saves a local callback request and reschedules a local missed request. These
  are offline fixtures, not evidence of real calls. Original app build 18 and its
  8 October 23:45:12 update time remain unchanged.
- The normal AAB passes bundle validation and matches the Google Play upload
  certificate. The isolated APK has no Internet permission and its installed
  checksum matches the archive. Crashlytics symbol upload remains deferred.

Artifacts in `C:/Users/ajayb/Downloads`:

- `TrustKeyper-v2.0.0-build27-manager-callbacks.aab`, SHA-256
  `17689975B4103AE64F2CCF9E028D42FB15D3C4FEC4EA3E6AECACAADF500CF0DA`.
- `TrustKeyper-UI-Test-build27.apk`, SHA-256
  `DE86D6065F80A94C19ED608DBB48BD107AC9CAA0C0FE846A93B02048CF804E43`.

Detailed evidence is in `output/ui-audit/build27-artifacts.json`,
`build27-firebase-callback-smoke.json`, `build27-hosted-bytes.json`,
`build27-web-runtime.json` and `build27-device-evidence.json`.
AABs must be uploaded to Google Play's internal test track; they cannot be
installed directly as an APK. Do not substitute the offline APK for the normal
Firebase-connected release.
