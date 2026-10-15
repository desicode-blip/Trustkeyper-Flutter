# Build 35: no minimum flat-name/address length

The user withdrew the address-length restriction from build 34. Flat names and
addresses such as `A`, `1`, `402`, `22/B` and local-language text are accepted.
No flat-number/building/area format is forced. A required address must only be
non-blank; an optional flat name can remain empty. Backend payload-size safety
limits, ownership checks and unrelated person/money/document validation stay
unchanged.

The minimum is removed from broker property selection, agreement validation,
partial checkpoints, owner onboarding, document invitations and the shared
agreement-review snapshot. Because that snapshot is used by approvals, agreement
copies, renewals, tenancy/move-out and payments, their affected callables must
also receive the updated implementation. This is a code deployment, not a
payment or legal-signature operation.

Specific missing/incorrect field messages and Fix actions from build 34 remain.
They must not report `402` as an invalid address. The offline gallery's address
correction example now starts with a genuinely empty required address instead
of manufacturing an error for a short valid name.

## Checks

1. Enter `402` or `A` as the property address. Continue to owners, save partial
   progress and reopen it. No minimum-length or formatting error should appear.
2. In owner onboarding, use the same short address and optional flat name `A`.
   Save the step. A blank optional name is valid too.
3. Share a document invitation for a TEST agreement with a short address; its
   recipient should still be able to verify and submit scoped synthetic papers.
4. Complete the draft and use the existing review flow. No later review or
   approval stage may reintroduce the old address minimum.
5. Leave a required address blank. Only the missing-address message should show.
   The full-name/phone/email, share-total and other field messages still work.

Only the separate UI Test app is updated directly on the connected phone.
Normal device acceptance uses the build-35 AAB through Play internal testing.
Build 34 is superseded and still contains the old minimum. No Git/Vercel/DNS
change, original-app reinstall, real payment or personal-document upload is
performed.
