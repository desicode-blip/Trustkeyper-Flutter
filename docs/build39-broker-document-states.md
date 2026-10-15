# Broker document states — build 39

## Approved reference and scope

This correction uses the cached Aman exports in `output/design-reference`,
not a new interpretation of the design. Owner boards 03/23–31, messaging
boards 04/17–29, and tenant boards 05/05–11 define the relevant states.
Discarded boards 13 and 14 are not acceptance references.

| Broker state | Implemented presentation and behavior |
| --- | --- |
| Individual links shared | Green channel/count banner, three paper rows, orange waiting text, Resend and Add |
| Link opened | Seen / not added yet, reminder action, direct-add takeover confirmation |
| Resent link | Server-timestamp cooldown, disabled countdown action, no fabricated provider delivery |
| One paper received | Green added status, See / Change / Delete, brief row highlight and upload toast |
| All three received | All done pill beside the person, three completed paper rows, no pending banner |
| Delete | Approved destructive confirmation; only the selected paper closes, other bundle papers remain available |
| Take over | Approved confirmation; cancelling does not open the picker or cancel a recipient link |
| Unclear / expired | Red paper guidance with Ask again / New link; a usable existing received copy remains viewable |
| Messaging cannot open | Red Link not sent panel with SMS, email, and Change number recovery |
| More than one person | Accurate Next: Owner N / Next: Tenant N labels; the final person advances to the next real step |

Messaging recovery follows the approved visual language but says what is
actually known: an application launch failed. It does not falsely assert
that a phone number is not registered on WhatsApp. Opening a composer is
not delivery. Sharing status is recorded only after the broker confirms
that they sent the message. Copying a link never marks it as sent.

## Implementation

- Paper-level state resolves the latest individual or bundled request,
  independently of Firestore snapshot ordering.
- Actual server upload receipts drive the broker rows and completion pill.
  Reopening a saved flow reconstructs state without replaying transient toasts.
- Owner and tenant identity edits discard the previous person's request state.
- A scoped delete or successful direct upload closes only that paper's
  capability and invalidates any outstanding upload grant. Cancelling the
  file picker does not revoke a link.
- Original received files remain immutable private audit copies. A UI delete
  does not silently rewrite an already received agreement document.
- Recipient pages and server grants use the remaining bundle scopes. Phone
  proof, cross-broker restrictions, expiry, and private storage stay enforced.
- Narrow-device completed rows retain usable controls without horizontal
  overflow. The 440×956 baseline uses the approved colors, typography,
  spacing, paper icons, action circles, confirmations, highlight, and toast.

## Verification and artifacts

- All 355 Flutter tests pass, including 20 document-state goldens and
  narrow-device regression cases; Flutter analysis reports no issues.
- All 220 final backend tests pass. The five affected document callables are
  deployed to production Firebase `trustkeyper`.
- Both configured broker identities pass all 11 live scenario groups. The
  second identity also passes eight owner/tenant mobile-browser cases with
  fresh, slow, unavailable-storage and read-only-storage contexts. All
  temporary test records and files are removed.
- Firebase Hosting serves the matching production build bytes. Five hosted
  startup/retry cases and five additional authentication/link routes pass.
- Build 39's signed AAB and isolated APK are archived in Downloads with
  matching-source and upload-certificate verification. The isolated APK was
  installed and its owner waiting screen captured; this was not a full
  physical-device acceptance of every broker state. Build 40 supersedes
  the tenant rows and recipient selection handling. Final artifact/device
  evidence is saved in `output/ui-audit/build39-*` and `build40-*`.

The isolated UI Test application has no Internet permission and uses
synthetic documents. It is not a substitute for real server/authentication
acceptance or physical push-notification delivery.

This change is acceptance of the broker document-state correction, not a
claim that every screen in the whole product is pixel-perfect or that all
external-service/device combinations have passed acceptance.

## Test in the real app

1. Open an existing broker draft, enter an owner or tenant, and send one or
   more private document links. Finish the message in WhatsApp/SMS/email and
   confirm that it was sent. The paper changes to Waiting.
2. Leave the app and reopen the same saved draft. The correct person and
   pending documents must remain available.
3. Open the link as that recipient in a separate browser, complete normal
   phone verification, and submit synthetic test documents. No application
   installation is required for the recipient.
4. Reopen the broker draft or its upload update. The uploaded paper must have
   See, Change, and Delete; unopened papers must remain pending. A live upload
   produces a brief highlight/toast only while that screen is already open.
5. Submit all remaining papers. The person header must show All done and the
   pending banner must disappear. Continue to the next owner/tenant.
6. Cancel Delete and verify nothing changes. Confirm Delete and verify only
   that paper requires a new copy. Cancel direct-add takeover and verify the
   recipient link still works.

Use fictitious documents and the configured Firebase testing identities.
Do not upload real identity or bank documents for a UI acceptance exercise.
