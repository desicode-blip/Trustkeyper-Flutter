# Razorpay Route decision and integration boundary

Aman confirmed Razorpay Route on 13 October 2026. This selects the transfer
provider; it does not prove account activation, linked-beneficiary onboarding,
bank verification, or live funds readiness. Existing checkout remains TEST.

## Implemented foundation

- `functions/razorpay-route-test-provider.js` supports read-only linked account
  and product checks, payment transfer lookup, transfer lookup, explicitly held
  INR transfers and settlement-hold changes. It rejects Live keys.
- A destination is ready only when its matching Route product is activated and
  its linked account has the documented created status. Missing/unknown states
  fail closed. No personal/KYC/bank fields are returned by the readiness command.
- A processed transfer is not a settled bank credit. The transfer must also have
  a matching processed recipient settlement. Partial/full reversals remain
  distinct from bank settlement and tenant refunds.
- `scripts/verify-razorpay-route-test.cjs` reads the existing Firebase Test secrets
  privately and checks a specified Linked Account/product without provider writes.
- Broker earnings now require explicit `recipientUid` and `kind: brokerage`.
  Being a participant in an owner's payout is not a broker earning.

The provider adapter is not exported as a client callable or connected to an
automatic transfer job. Its mutators have no application entry point yet.
It must not be used by retrying a payment-transfer POST after a timeout:
the later service needs a durable operation reservation, payment/transfer
reconciliation, and an admin-visible unknown state before any retry.
The saved operation note is a reconciliation reference, not a provider
idempotency guarantee for payment transfers.

## Approved money rules to preserve

The product/user journey says the first tenant payment contains only the current
rental month, deposit and maintenance; advance months are allowed afterwards
through the agreement end. Deposit is held by TrustKeyper, not paid as owner rent.
The owner's contractual fee is 5–20%; 5% is an example, not a universal default.
Owner rent is paid on the 7th after contractual fee and approved repairs.
Brokerage is held until signing and reaches the bank about two days after move-in.
Keys require every tenant's first rent and deposit. Move-out deposit refunds
follow agreed deductions and unpaid bills; disputed deductions are reviewed.

The final service must not infer equal co-owner payouts or fund brokerage from
the deposit/first tenant invoice: that invoice excludes brokerage. An explicit
approved beneficiary allocation and brokerage collection source are necessary.
Any existing captured/paid record without a valid external signed copy remains
ineligible for automatic release.

## Remaining work

1. Verify actual Test owner/broker Linked Account IDs and matching product IDs.
2. Bind approved beneficiaries server-side to the relevant identities and
   contracts, with re-verification for changed bank details.
3. Persist immutable allocation plans against captured invoices and exact
   contractual revisions, plus reservations preventing over-allocation.
4. Reconcile uncertain/partial provider responses before any further transfer.
5. Release holds only when the actual agreement, move-in/payment gates and
   scheduled payout dates pass; track real recipient settlements/webhooks.
6. Implement deposit refund/reversal reconciliation and approved admin queues.
7. Obtain business/compliance sign-off and separately test live capability
   before real-money launch. Do not create a Linked Account or accept terms
   on a real person's behalf merely because their uploaded bank file exists.

## Read-only readiness command

`node scripts/verify-razorpay-route-test.cjs --project=trustkeyper --linked-account=acc_ACTUAL_TEST_ID --product=acc_prd_ACTUAL_TEST_ID`

Use actual identifiers, not the placeholders. No secret keys belong in chat.

Official references: [Route integration](https://razorpay.com/docs/payments/route/integration-guide),
[Linked Account lookup](https://razorpay.com/docs/api/payments/route/fetch-with-id),
[product configuration](https://razorpay.com/docs/api/payments/route/fetch-product-config),
[payment transfers](https://razorpay.com/docs/api/payments/route/create-transfers-payments).
