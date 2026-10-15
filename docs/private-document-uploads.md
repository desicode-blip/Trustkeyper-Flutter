# Broker-private draft documents

The production bucket `trustkeyper.firebasestorage.app` was provisioned in
`asia-south1` on 8 October 2026. Build 18 has inline broker-owned owner/tenant
document controls and actual PDF page review. Authenticated live Firebase
checks saved/read/updated/deleted temporary unfinished progress and
uploaded/read/replaced/deleted a non-sensitive test PDF. Other-account reads,
writes and deletes were rejected; the temporary data was confirmed removed.
These SDK checks and offline phone fixtures are not normal Android app native
picker/camera acceptance or a completed participant/admin verification workflow.

## Usage for authorized Firebase testing

1. As an approved broker, start an agreement for a test-labelled property.
2. Enter the owner details and continue to the owner's document step. The three
   paper rows have **Add** and **Send link**. Add expands private upload controls
   (both sides for Aadhaar). The tenant step uses the same working controls.
   Completing every agreement term first is not required. Build 19 also adds
   recipient browser upload links; see `docs/document-upload-links.md`.
3. For an already saved draft, **Manage private documents** also opens the
   manager. Check the person and revision before uploading.
4. Choose Aadhaar front, Aadhaar back, PAN or bank proof. Select a JPG, PNG or
   PDF no larger than 10 MB. Review the image or every PDF page, then confirm
   **Upload private copy**. Unreadable files cannot be confirmed. **Take photo**
   captures a new image in the normal app and uses the same review/upload gate.
5. The slot says **Uploaded · Not verified** after successful storage. View,
   replace or delete that specific private copy. Replacement and deletion require
   confirmation. Failed operations show an error and require metadata reload.
6. Press **Save progress** before leaving an edited incomplete form, or **Next**
   to save a checkpoint. Reopen it through the broker Agreements tab's
   **Resume unfinished drafts**. Saving the complete draft removes the checkpoint
   when possible. Stale-device edits are rejected instead of silently overwritten.

Files live beneath the authenticated broker's private user document directory,
with separate draft/revision/person/document-kind segments. There are no bearer
download URLs in this UI. Each pending revision has its own copies. For an
unchanged person, **Review previous copy** allows explicit reviewed reuse of an
older saved draft's file. Nothing is silently carried forward. Changing a
person's name/contact creates a new document identity and requires new files.
Old revision files remain private until explicitly deleted or a separately
approved retention policy is implemented.

## Acceptance still required

- Ajay explicitly selected production `trustkeyper` rather than staging. Use
  only designated test accounts and non-sensitive fixtures for acceptance.
- Validate user isolation, deleted/replaced files and account changes on device.
- Emulator tests cover authenticated private-owner access, cross-user denial,
  deletion, MIME and size limits; they do not substitute for device acceptance.
- Add server-owned manifests, authenticated participant links with seven-day
  expiry, contact-change invalidation, admin review/re-request and audit history.
- Validate native file selection/camera capture, multi-page and encrypted PDF
  handling, accessibility and exact approved-artboard comparisons on the normal
  Android app. PDF/image header recognition is not identity or PDF verification.
- Validate backgrounding/camera process-death recovery. Unfinished checkpoints
  save on Next/explicit save, not every keystroke; retention expiry is pending.
- Uploaded files do not authorize money movement, bank verification, consent,
  signing, key handover or participant access.

## Local testing

`test/private_documents_test.dart` covers file size/type, immutable byte copies,
slot isolation, revision changes, session changes, replacement, deletion, failed
upload preservation, preview confirmation and recoverable load failures.

**Private documents · offline fixture** in the isolated app uses an in-memory
store and a labelled PDF fixture, not real identity documents or Firebase.

Build 18 validation includes 132 Flutter tests, 34 backend tests and ten
Firestore/Storage access tests, plus the temporary live Firebase checks above.
The PDF viewer was checked on the connected Android phone; the Windows widget
runner does not bundle its native PDFium library, so widget tests do not prove
native PDF rendering. See `docs/build18-functional-audit.md` for final deployment
and artifact evidence.
