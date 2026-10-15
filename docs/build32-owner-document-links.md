# Build 32: broker document collection

11 October 2026. Focused testing release, not whole-product completion.

## Ready testing files

- Normal Firebase app: `C:\Users\ajayb\Downloads\TrustKeyper-v2.0.0-build32-testing.aab`.
  This is the signed Play testing bundle, not the offline preview.
- Separate offline preview: `C:\Users\ajayb\Downloads\TrustKeyper-UI-Test-build32.apk`.
  The corrected APK is installed on the connected OnePlus Nord 5 and its
  on-device SHA-256 matches the final archived APK. The original TrustKeyper
  app remains on build 30 with its installation unchanged.
- Browser app: https://trustkeyper.web.app. Published index, bootstrap and main
  JavaScript bytes match the normal build. The document callables and Storage
  rules are deployed to Firebase project `trustkeyper`.

These files are not a claim that all 18 exports or every product story are
complete. The phone preview cannot test real authentication or backend writes;
use the normal Firebase app/browser for the live sequence below.

## Changes

- Broker owner/tenant steps show the actual selected person, editable contacts
  and functional Add/Send link controls. Add opens camera/file choice, reviewed
  upload, front/back, private view, replacement and confirmed deletion.
- Single-paper links remain supported. Send all documents link creates one
  browser journey for both Aadhaar sides, PAN and bank proof or typed bank/UPI.
- WhatsApp, SMS and email use real composers. Missing email routes to editing
  the person; copying never reports delivery. Provider delivery is not fabricated.
- Recipients need no app installation or profile signup, but must verify the
  intended phone through Firebase OTP. Existing matching sessions still show
  the invitation before the upload hub. Recipient auth is separate from app auth.
- Session changes clear selected files and dismiss previews. File operations
  recheck request proof. Wrong phones, stale revisions and revoked grants fail.
- Typed bank details validate repeated account number and IFSC; UPI validates
  its format. Backend whitelist and captured grant prevent completion overrides.
  These details remain explicitly unverified.
- Backend requires exactly the granted pages before reporting received.
  Private snapshots use exact generations and remove download-token capabilities.
  Broker rows show actual bundle receipt, private files and typed details.

## Exact live test order

Use TEST-labelled agreements, synthetic documents and controlled numbers only.
Never upload real Aadhaar/PAN/bank documents merely to test the interface.

1. Upload the signed build-32 AAB to the authorized Play testing track and
   install from that track. An AAB cannot be installed by tapping it.
2. Log in as the approved test broker. Start/resume a TEST property's agreement.
   Complete the intended Owner name, phone and email, then open Step 2.
3. Press Aadhaar Add. Cancel first: no change. Reopen → Upload → review the
   synthetic file → confirm upload. Add the back, view, replace and delete a copy.
4. Press Send link. Check the actual name/phone and all channels. Cancel first:
   no request is created. Email without a saved address must not guess one.
5. Press Send all documents link. Finish sending the private URL through the
   chosen composer, then confirm sharing. A composer opening is not delivery.
6. Open the URL in another browser/private window. Confirm broker/property.
   Press Continue with the intended phone and enter its Firebase OTP. A wrong
   code must not reveal upload controls. Test numbers use console-defined codes,
   not an application bypass. Do not publish the private URL in screenshots/chat.
7. Add both Aadhaar sides and PAN. Send remains disabled until all requested
   documents or valid typed bank details are present.
8. Test cancelled-cheque/PDF, then the alternate Bank form with matching repeated
   account number and valid IFSC, or TEST UPI. No account may appear verified.
9. Press Send to the broker. Failure must remain retryable without success.
   After confirmation, reopen the broker step and check actual status/files/details.
10. Repeat for Tenant and PAN-only requests. PAN-only must ask for nothing else.
    Wrong authenticated phones must fail. Contact/new-revision changes require
    a corrected new link, not reuse of the former person's private request.
11. End/change the recipient session during selection/preview: private files
    disappear. Retest expired and revoked links.

## Separate phone preview

Use TrustKeyper UI Test → Broker · owner Add and Send link (offline), or
Owner document link · all three · offline. Synthetic local fixtures demonstrate
UI only. This APK has no Internet permission, live OTP, messages or production
data. It never updates the original TrustKeyper package.
Photo/file buttons in recipient previews use clearly labelled synthetic PDFs;
they do not open your personal camera or files. The normal app retains its real
camera and file pickers.

### Phone preview sequence

1. Open **TrustKeyper UI Test**, not your original TrustKeyper app.
2. Choose **Broker · owner Add and Send link (offline)**. Switch Owner 1/2,
   edit contacts, open Add, and check the Send link channel choices and Cancel.
   This preview deliberately refuses to create or deliver a live link.
3. Return to the preview gallery with the phone Back button. Scroll to
   **Owner document link · all three · offline** and open it.
4. Press **Continue with +919000000001**. This is an already-verified synthetic
   fixture, not an OTP bypass in the normal app. Check the upload hub.
5. Choose Aadhaar **Photo**, select Front, review the TEST PDF and choose
   **Use this file**. Add Back in the same way, then **Save**. Choose PAN **File**
   and review the TEST PDF. Nothing has been sent yet.
6. Open Bank **Type**. Choose Bank and try saving empty/mismatching fields;
   errors must keep you in the form. Fill TEST-only details with matching account
   numbers and valid IFSC format, then **Save details**. Alternatively use a
   synthetic cancelled-cheque file. Details are not bank-verified.
7. **Send to Offline** is enabled only when all three requirements are ready.
   Its receipt is local simulation; it is not a real broker submission.

## Acceptance boundaries

The 18 exports contain hundreds of variants; this release targets document
collection, not every product state. Actual renders do not certify full pixel
parity. Automatic identity/cheque extraction, verified bank/UPI lookup, contact
collision recovery, full localization, provider delivery and complete
mobile/admin acceptance remain separate work. Real finances/legal processing
retain existing evidence gates; admins upload the genuine externally signed copy.

Successful validation, artifact signatures, published bytes and phone evidence
are recorded separately under output/ui-audit/build32-*.

## Validation

536 automated checks pass: 287 Flutter, 205 backend and 44 real Firebase
Auth/Firestore/Storage emulator checks. The analyzer is clean. The visual test
checks that both owner-tab labels remain fully readable at the approved width.
Seven additional live Firebase scenario groups pass using existing console-defined
test phones and synthetic PDFs: full tenant and owner bundles, typed bank/UPI,
incomplete uploads, wrong-phone denial, private broker viewing and immutable
idempotent completion. All temporary fixture records/files are removed.
No real identity document, financial transaction or external message is sent.

The final matching offline APK passes connected-phone checks for owner tabs,
share choices/cancel, missing-email editing, the recipient invitation/upload hub,
synthetic front/back/PAN review, required and mismatching bank-form values,
corrected typed-bank completion, disabled/enabled submission gates and the local
receipt. Eight saved UI-state assertions pass. These checks use no live Firebase
session, personal files, bank verification or message delivery. Evidence is
`output/ui-audit/build32-device-evidence.json` and the `build32-final-*` UI dumps
and screenshots. The phone is left on the separate preview gallery.

`scripts/build-testing-release.ps1` records a SHA-256 snapshot of app source,
assets and configuration before/after the serial validation and builds. It
refuses to archive artifacts if source changed. Package identity, permissions,
Google Play upload certificate, cryptographic signatures and bundle validation
are checked separately before the Downloads copies are produced.
