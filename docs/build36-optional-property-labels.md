# Build 36: property text is entirely optional

The user clarified that property name, address and flat text can all be blank.
Any arbitrary label, including `rjh`, is valid. There is no required-label,
minimum-length, address-format or free-text label-uniqueness check. This
supersedes the required-address rule in builds 34 and 35.

Broker property entry marks the field optional and leaves Next enabled when it
is blank. Owner onboarding allows an empty address and optional home name.
Checkpoints, complete agreements, document invitations and shared review
snapshots accept blank text. Name-only owner properties retain the supplied
name as their summary label. Unnamed cards show a display-only placeholder;
no invented physical address is saved.

Ownership remains based on property IDs and authenticated participants, not
arbitrary name/address equality. Existing foreign property IDs cannot be
claimed, and active tenancies remain protected. Phone, participant, money,
bank/document validation and payload/type safety guards are unchanged.

## Verified checks

- 318 Flutter tests and 215 backend tests pass; Flutter analysis is clean.
- Live Firebase document-link checks pass nine scenario groups for blank
  property text and nine for `rjh`, including scoped recipient uploads,
  private broker receipts, exact byte reads and restored draft progress.
- Temporary live-test records and synthetic PDF files are removed afterward.
- All 26 affected functions are ACTIVE; the deployed source archives match the
  three updated backend modules. The webhook rejects an unsigned callback;
  the CLI's public-binding warning does not block its existing transport.
- Signed build-36 artifacts are archived. The phone's separate offline preview
  accepts blank property entry and saves `rjh`; no Firebase property or agreement
  is created by that preview. Build 37 supersedes its duplicated error display.

## Acceptance

1. Add a broker property and leave the optional property field blank. Continue
   through its normal detail steps, save it and continue to owners. The field
   must not disable Next or produce an address warning.
2. Repeat with `rjh`, `1`, `402` or any other label. There is no length or
   required-address-format warning.
3. In owner onboarding, save the first step with name/address both blank, then
   repeat with name `rjh` and address blank. Both are valid.
4. Create/reopen broker progress with a blank label. Owner count and draft
   identity must remain intact, and later document/review APIs must not enforce
   an address requirement.
5. Missing or malformed owner/tenant contact and money fields must still name
   their actual fields. Property text must never be listed as missing.
6. Duplicate labels must not imply ownership. A different account's property ID
   and an active tenancy must remain protected independently of its label.

The connected phone receives only the isolated offline UI Test package. The
normal app requires the build-36 AAB through Play internal testing. Offline
previews do not prove Firebase persistence, authentication, push delivery or
whole-product production acceptance. No Git/Vercel/DNS/Play publication, real
payment or personal-document upload is performed.
