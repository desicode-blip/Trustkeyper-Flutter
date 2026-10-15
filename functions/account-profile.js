export class AccountProfileError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const requireValue = (condition, message, code = 'failed-precondition') => {
  if (!condition) throw new AccountProfileError(code, message);
};
const clean = value => typeof value === 'string' ? value.trim() : '';

export function createAccountProfileService({ auth, identity, store, now = Date.now }) {
  async function profile(transaction) {
    requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
    const current = await transaction.get(`users/${auth.uid}`);
    requireValue(current && current.paused !== true &&
      current.roles?.some(role => ['broker', 'owner', 'tenant'].includes(role)),
    'This account cannot edit its profile.', 'permission-denied');
    return current;
  }
  function details(current, person) {
    requireValue(person.uid === auth.uid && person.disabled !== true, 'This login is unavailable.', 'permission-denied');
    return { displayName: clean(current.displayName) || clean(person.displayName),
      phone: clean(person.phoneNumber), phoneVerified: !!person.phoneNumber,
      email: clean(person.email), emailVerified: person.emailVerified === true,
      city: clean(current.city), reraNumber: clean(current.reraNumber),
      language: 'en',
      bankName: clean(current.bankName), bankAccountLast4: clean(current.bankAccountLast4 ?? current.payoutBankAccountLast4),
      bankVerified: false };
  }
  return {
    async read() {
      const current = await store.transaction(profile);
      return details(current, await identity.read(auth.uid));
    },
    async save(input) {
      requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
      const name = clean(input.displayName), city = clean(input.city), reraNumber = clean(input.reraNumber);
      requireValue(name.length > 0 && name.length <= 120, 'Enter your full name, up to 120 characters.', 'invalid-argument');
      requireValue(city.length <= 100 && reraNumber.length <= 100, 'Keep city and RERA number within 100 characters.', 'invalid-argument');
      const person = await identity.read(auth?.uid);
      requireValue(person.uid === auth.uid && person.disabled !== true, 'This login is unavailable.', 'permission-denied');
      const requestedEmail = clean(input.email).toLowerCase();
      requireValue(!requestedEmail || person.emailVerified === true && requestedEmail === clean(person.email).toLowerCase(),
        'Verify this email before saving it.', 'failed-precondition');
      await store.transaction(profile);
      await identity.updateName(auth.uid, name);
      return store.transaction(async transaction => {
        const current = await profile(transaction);
        const next = { ...current, displayName: name, city, reraNumber,
          email: person.emailVerified === true ? clean(person.email).toLowerCase() : clean(current.email),
          updatedAtMs: now() };
        transaction.update(`users/${auth.uid}`, { displayName: next.displayName, city, reraNumber,
          email: next.email, updatedAtMs: next.updatedAtMs });
        return details(next, { ...person, displayName: name });
      });
    },
  };
}
