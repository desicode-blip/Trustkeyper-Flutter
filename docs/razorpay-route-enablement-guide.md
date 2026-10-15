# Check or enable Razorpay Route for TrustKeyper

Having working Razorpay checkout keys does not by itself confirm Route access
or activated beneficiary accounts. We have selected Route; account capability
has not yet been checked against actual linked-account identifiers.

1. Log in to the TrustKeyper merchant account at
   [Razorpay Dashboard](https://dashboard.razorpay.com/).
2. Select Test Mode. Keep this work separate from Live Mode and real money.
3. Open PAYMENT PRODUCTS → Route. Razorpay documents this as the Route entry.
   If the page opens, check its Accounts tab and existing linked accounts.
   A visible menu alone does not prove transfer readiness.
4. If Route is absent, locked, disabled or asks for activation, follow the
   account's displayed activation instructions or ask
   [Razorpay Support](https://razorpay.com/support/) to enable it.
   Suggested ticket:

   “Please confirm/enable Razorpay Route for the TrustKeyper merchant account
   in Test Mode for owner rent disbursements and broker payouts. Please also
   confirm Live Mode eligibility and the approved rental-deposit/refund flow.”

   Support may require merchant/KYC/compliance review. Do not assume a toggle
   overrides those requirements or authorise real transfers just to test access.
5. If existing Test linked accounts are available, open an owner and a broker
   account and copy their Account IDs beginning `acc_`. Share those IDs or a
   redacted screenshot of the Route/Accounts page, not bank details or API secrets.
6. If none exist, Razorpay's documented path is Route → Accounts → + Add Account,
   followed by name/contact/KYC and settlement details. Use the appropriate
   provider-supported test setup; don't enter invented Live KYC details or
   accept terms on a real beneficiary's behalf without the proper authority.
   We need verified identities/mappings before wiring app transfers.

An activated matching Route configuration and usable Linked Account must be
verified before funds are transferred. This is different from choosing Route
as the intended service. The app still uses Test checkout; Route's complete
application transfer/settlement/refund integration remains unfinished.

Official instructions:
[Route entry and eligibility](https://razorpay.com/docs/payments/route/),
[adding Linked Accounts](https://razorpay.com/docs/payments/route/linked-account),
[Route integration](https://razorpay.com/docs/payments/route/integration-guide).
