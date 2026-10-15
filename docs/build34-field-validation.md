# Build 34: actionable agreement-field validation

Superseded by build 35: the user withdrew the address-length rule. This report
describes the historical build-34 behaviour, not the current acceptance rule.
See `docs/build35-short-addresses.md`.

## Root cause and behaviour

The property step accepted any non-empty address, but agreement checkpoint
validation rejected addresses shorter than eight characters. This could leave
the owner-count screen displaying an internal draft-progress error for an
address supplied on the previous screen. Both checks now use the same rule.

The agreement footer uses the existing rounded-card, blue-action and error
colour tokens. It lists each missing or incorrect field rather than a generic
invalid-draft message. Matching text inputs show inline errors. Tap **Fix** to
open the relevant person/step and focus or scroll to its field. Optional email
can remain empty. Phone validation keeps the existing backend-compatible test
number rules and does not introduce an app-level OTP bypass.

An invalid address has an **Edit property** recovery path that returns to the
same draft, retaining entered people and their count. The property is saved
through the normal property repository only when Save property is confirmed.
Rent, maintenance, deposit, tenant shares, dates, notice, lock-in and brokerage
have specific correction targets. Next dismisses the keyboard; the error list
compacts when a keyboard is open. Partial progress saving remains allowed;
future-step fields are not falsely required before their step.

Network, approval and concurrent-edit failures remain operational errors, not
invented missing-field warnings. A failed save does not erase the inputs or
claim that progress was saved. Backend privacy and concurrency rules are not
weakened. This change does not modify OTP, payment or signed-document logic.

## Acceptance checks

1. In the normal build-34 app, add a TEST property with address `402`. Next must
   highlight the address and stay on the property step. Use a complete synthetic
   address to continue.
2. For a previously selected short-address property, the owner-count screen
   must show **Property address** and **Fix**. Correct it in the property editor,
   save, and return. Owner count and draft identity must remain unchanged.
3. On owner details, tap Next with name/phone empty and an invalid email. All
   applicable fields must be listed and highlighted together. No generic
   invalid-progress message should appear.
4. Tap a field's Fix action. Check the correct owner tab and input focus. Fill a
   synthetic full name and configured Firebase test phone. Correct or clear the
   optional email. Errors disappear and Next opens the working document step.
5. Repeat for tenant 2. Its errors must identify tenant 2, not overwrite tenant 1.
   Duplicate phones within one role must identify the affected phone fields.
6. On money details, try empty rent, malformed maintenance/deposit and mismatched
   tenant shares. Correct the fields or split equally; totals must still match.
7. Test a missing start date, a lock-in longer than the term, and Both brokerage
   with a zero payer amount. Each must name the relevant field and allow fixing
   it without restarting the agreement.
8. Save incomplete progress before later steps are filled. Reopening must retain
   the saved inputs; Next still validates only the applicable step.
9. Test offline save on a disposable TEST draft. The message must mention the
   connection rather than invent field errors, and inputs must remain present.

## Release boundaries

The isolated UI Test preview includes **Broker · missing fields and address
correction (offline)**. It uses synthetic in-memory data and has no Internet
permission. It does not certify Firebase persistence or OTP/push delivery.
Normal app acceptance requires the build-34 AAB distributed through Play
internal testing. An AAB is not installed by tapping it on a phone.

The original connected phone app was build 33 at the start of this change.
Only the separate UI Test package may be installed by this task. No Git push,
Vercel/DNS change, Play upload, real payment or personal-document upload is
performed. Existing backend acceptance evidence remains build 33; no backend
function or security-rule change is needed for this frontend fix.
