# Build 33: broker drafts and document-upload updates

## What this change covers

- A broker's unfinished agreement is saved in Firebase before sharing an owner or tenant upload link.
- Home exposes saved agreements; Agreements has All, In progress, Signed and Drafts filters. Continue restores the saved stage and people.
- A successfully completed document request creates one private, persistent Updates entry for the requesting broker. Partial or failed uploads do not claim completion.
- The bell shows unread entries. Opening an entry shows the exact owner or tenant and agreement revision that received the documents.
- Android notification registration survives navigation. Logout removes the current device registration and invalidates its messaging token. A paused or unapproved broker does not receive new pushes.
- Signed agreements are not mislabeled as unfinished drafts. Deleted, changed-person and obsolete-revision requests cannot silently open another person's documents.

## Test on the normal Firebase app

Use build 33 distributed through Play internal testing. An AAB is uploaded to Play; it is not directly installed by tapping it on the phone. The separately labelled UI Test APK is an offline design preview and does not send real invitations, authenticate, or receive Firebase push messages.

Verified release files are `C:\Users\ajayb\Downloads\TrustKeyper-v2.0.0-build33-testing.aab` and `C:\Users\ajayb\Downloads\TrustKeyper-UI-Test-build33.apk`. The original app on the connected phone is still build 32; checking that original app does not test the new build-33 UI. Only the separate offline UI Test app is updated on the phone.

1. Log in as the approved broker test account already configured in Firebase. Enable Android notifications when asked.
2. Start an agreement using a clearly marked TEST property and synthetic people/documents. Do not upload real Aadhaar, PAN, banking data or legally signed documents for this test.
3. Add owner 1 and owner 2 with distinct names. Use the configured owner test phone for the person who will upload. Record that person's name and selected tab.
4. In that person's document step, choose Send link. The approved sheet offers WhatsApp, SMS and email; sharing opens the selected external service. Confirm sending there. Merely opening a share sheet is not evidence of delivery.
5. Leave the agreement and return to Home. The saved agreement must appear there and under Agreements → Drafts. Close the app normally, reopen it and log in as the same broker if necessary. Continue must restore the same people, selected stage and entered values without creating a duplicate agreement.
6. Open the link in another browser/device as the intended owner. Complete its Firebase phone verification. No app installation is required. A different phone must not be allowed to upload to this request.
7. Upload synthetic documents, including both Aadhaar sides where requested. For an all-documents request, complete PAN and validated bank/UPI details too. Before the final successful submission, the broker must not get a false “documents received” update.
8. Submit successfully. On the broker phone, inspect Updates using the bell. A new unread entry must identify the correct person and property. If the broker app is in the background and notifications are permitted, check for the generic TrustKeyper notification.
9. Open the update. An unfinished agreement must reopen directly at that exact owner's or tenant's approved document step, not at owner 1 by default. Preview the synthetic files and captured bank details there. A completed agreement instead opens its current private document review.
10. Return to Updates and reopen the app. The read state must remain saved. Retrying the same already-completed submission must not create duplicate inbox entries.
11. Repeat with a tenant and, separately, a second owner/tenant. Verify that their documents and links remain separate.
12. Repeat sharing, then edit that person's identity or delete the unfinished draft. The old request must not reveal a replacement person's records. A stale update must show a safe unavailable/changed message rather than silently navigating elsewhere.
13. On a disposable TEST draft, tap Delete → Cancel: the draft must remain. Confirm Delete: only that unfinished draft progress is removed. Do not perform deletion tests on a real or signed agreement.
14. Finish saving the agreement. Verify that obsolete unfinished progress is no longer listed alongside its current agreement. Only an actual externally signed agreement belongs in Signed.
15. Sign out and log in as broker 2. Broker 1's drafts, inbox, documents and unread badge must not appear. Repeat on a second device to check independent device registration.

## Notification boundaries

The inbox is the durable source of truth. Denied notification permission, an invalid/expired device token, network failure or Android force-stop can prevent an operating-system notification without removing the saved inbox update. The offline UI Test app cannot certify physical Firebase push delivery. WhatsApp/SMS/email share intents are not delivery receipts.

No payment, legal signature, identity-provider validation or whole-product pixel-perfect acceptance is implied by these document-flow checks.

## Verified evidence

- 303 Flutter tests, 210 backend tests and 46 Auth/Firestore/Storage emulator checks pass; Flutter analysis is clean.
- Nine live Firebase scenario groups pass, including a new broker session restoring saved progress, exact-person receipts, read state and the deployed notification trigger. Temporary fixtures and files are removed.
- Five connected-phone preview checks pass, and the installed isolated APK hash matches the final archived APK. The original app is unchanged.
- The signed AAB, package/version, unchanged source snapshot and published Firebase Hosting bytes are verified. Reports and screenshots are saved under `output/ui-audit/build33-*`.
- Authenticated build-33 phone acceptance and physical push delivery remain explicit normal-app tests, not offline-preview claims.
