export class AccountRoleError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const clientRoles = ['broker', 'owner', 'tenant'];
const requireValue = (condition, message, code = 'failed-precondition') => {
  if (!condition) throw new AccountRoleError(code, message);
};
export function createAccountRoleService({ auth, store, now = Date.now }) {
  async function profile(transaction) {
    requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
    const current = await transaction.get(`users/${auth.uid}`);
    requireValue(current && current.paused !== true, 'This account is unavailable.', 'permission-denied');
    requireValue(!current.roles?.includes('admin'), 'Use the team login for this account.', 'permission-denied');
    return current;
  }
  function route(current, role) {
    return role === 'broker' ? current.approvalStatus === 'approved' ? '/broker' : '/broker/approval' : `/${role}`;
  }
  return {
    async read() {
      return store.transaction(async transaction => {
        const current = await profile(transaction);
        return { displayName: current.displayName ?? '', roles: clientRoles.filter(role => current.roles?.includes(role)),
          brokerApproved: current.approvalStatus === 'approved' };
      });
    },
    async select(input) {
      requireValue(clientRoles.includes(input.role), 'Choose your role.', 'invalid-argument');
      return store.transaction(async transaction => {
        const current = await profile(transaction);
        requireValue(current.roles?.includes(input.role), 'This role is not linked to your account.', 'permission-denied');
        return { role: input.role, route: route(current, input.role) };
      });
    },
    async add(input) {
      requireValue(clientRoles.includes(input.role), 'Choose a customer role, not a team role.', 'invalid-argument');
      return store.transaction(async transaction => {
        const current = await profile(transaction);
        if (!current.roles?.includes(input.role)) {
          const roles = [...new Set([...(current.roles ?? []), input.role])];
          requireValue(roles.every(role => clientRoles.includes(role)), 'The role profile needs team review.');
          transaction.update(`users/${auth.uid}`, { roles, updatedAtMs: now(),
            ...(input.role === 'broker' && current.approvalStatus !== 'approved' ? { approvalStatus: 'pending' } : {}) });
          transaction.set(`users/${auth.uid}/roleEvents/${input.role}`, { action: 'customer_role_added', role: input.role,
            actorUid: auth.uid, createdAtMs: now(), grantsHomeAccess: false });
        }
        return { role: input.role, route: route(current, input.role) };
      });
    },
  };
}
