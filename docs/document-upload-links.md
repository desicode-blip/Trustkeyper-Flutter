# Broker-requested document links

Build 32 follow-up · 11 October 2026 · Firebase project `trustkeyper`.

This implements single-paper and whole-document journeys (B8, related O3/O4/T4). An owner
or tenant opens a mobile web page without installing the app or completing a
profile. The approved journey still requires phone OTP before document access
or upload. A forwarded link is not permission to upload as another person.

References: cached approved artboards 04/17, 05/05, 10/07–15 and 12/12, the
product/user-journey PDF, and Ajay's supplied screenshot. `D:/Trustkeyper/Artifacts`
was empty when inspected. Exact visual acceptance across all 18 designs is not
implied by implementing this feature.

## Test this flow

1. Use the updated normal Android build or the Firebase-hosted app as the
   approved broker. Start a clearly TEST-labelled agreement.
2. Enter the intended person's real/test name and phone, then open that owner's
   or tenant's document step. Use only configured Firebase test numbers for
   automated acceptance. The forms accept these numbers structurally; there is
   no OTP bypass or hardcoded accepted code in the application.
3. Each of Aadhaar card, PAN card and Bank account has **Add** and **Send link**.
   Add opens camera/file choice and working private page controls. Send link saves a
   checkpoint before creating a server-owned request.
4. Choose WhatsApp, SMS or Email; the separate private-link menu also allows copying. Finish sending in the messaging app and
   confirm **I sent it**. Opening a composer or copying a URL is not delivery.
   Email uses the broker's composer, not confirmed Resend/provider delivery.
5. On the recipient's phone, open the private `trustkeyper.web.app` link in a
   browser. It shows who requested the paper, the property and intended number.
   Press **Continue with the intended phone**, enter the Firebase SMS code, then **Verify code**.
   There is no app download, role selection or profile setup.
6. Select **Photo** or **File**, preview the actual image/PDF and press **Use this
   file**. This selects it only; no upload or delivery is reported yet. Aadhaar
   requires both front and back; PAN requires one file; bank
   requires a cancelled cheque/bank-proof file. JPG/PNG/PDF: 10 MB per page.
   Files can be replaced or removed before submission.
7. Press **Send to broker**. Success appears only after the backend commits the
   received manifest. The receipt refers to this paper only, not all documents.
8. On the broker's document step, the live status becomes **Added by [name] ·
   Not verified**. Open each received page. **Unclear** records a reason and
   enables replacement; **Remind** retains a valid link; **Resend** replaces it.
9. Negative tests: a different phone cannot upload; a missing Aadhaar side cannot
   send; an expired/reissued link cannot be used; changing the person's name or
   contact invalidates the previous request; failed upload never reports success.

## Security and backend

- Five callable functions handle creation, invitation reads, broker actions,
  upload grants and finalization. Only an approved, unpaused broker may request
  documents for a party in their current private progress/draft revision.
- Seven-day random capabilities are bound to broker, draft revision, party and
  requested paper. URL fragments keep the capability out of HTTP access logs.
  Share only with the intended person; a valid invitation reveals the intended
  name/phone/property, but no document manifest before matching phone proof.
- Recipient verification uses a separate Firebase app/auth session; it does not
  replace a broker/admin session or fabricate recipient role membership.
- Server-owned metadata is in `brokerDocumentRequests`. This is separate from
  the legacy admin `documentRequests` collection. Clients cannot forge statuses,
  uploads or audit events. Raw reminder capabilities are in backend-only
  `documentRequestSecrets`; metadata contains their hashes, not the capability.
- Ten-minute upload grants restrict authenticated phone identity, attempt and
  exact document slots. Finalization checks size/MIME/header and makes an
  immutable, exact-generation private snapshot before marking the paper added.
  Snapshot copies remove Firebase download tokens. Client overwrites/deletes are
  denied; views use authenticated Storage SDK reads, not public download URLs.
- The runtime Storage role is limited to the request-object prefix, not the
  entire business bucket. Callable transport must allow reaching the function;
  the service then enforces Firebase identity and request-specific permissions.
- Successful submissions attempt to remove temporary upload objects. Failed or
  abandoned attempts and received revisions still need a separately approved
  retention/deletion policy. Link expiry is access expiry, not physical erasure.

## Deliberate boundaries

Document collection is not OCR, Aadhaar/PAN/bank verification, agreement consent,
eSign, payment authorization or dashboard participant binding. WhatsApp/SMS
delivery/read receipts are not provider-integrated; the UI distinguishes broker
reported sharing from delivery confirmation. Seen means matching phone
verification opened the request, not an email tracking pixel.

The isolated UI-test gallery has local recipient upload previews and never uses
Firebase, sends an OTP, or uploads a real document. It is not backend acceptance.
No normal phone installation is changed automatically. See the build-19 audit
for actual validation, deployment and artifact results.
