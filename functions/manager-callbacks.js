import { createHash } from 'node:crypto';
import { verifiedPhone } from './verified-phone.js';

export class ManagerCallbackError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const check = (condition, message, code = 'failed-precondition') => {
  if (!condition) throw new ManagerCallbackError(code, message);
};
const safeUid = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const shift = 330 * 60000;
const day = 86400000;
export function callbackWindow(choice, timestamp) {
  const local = new Date(timestamp + shift);
  const midnight = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()) - shift;
  const ranges = {
    soon: [timestamp + 10 * 60000, timestamp + 30 * 60000],
    today_evening: [Math.max(timestamp + 10 * 60000, midnight + 18 * 3600000), midnight + 20 * 3600000],
    tomorrow_morning: [midnight + day + 9 * 3600000, midnight + day + 12 * 3600000],
    tomorrow_evening: [midnight + day + 18 * 3600000, midnight + day + 20 * 3600000],
  };
  const range = ranges[choice];
  check(range && range[0] < range[1] && range[0] >= midnight + 9 * 3600000
    && (choice !== 'soon' || range[1] <= midnight + 20 * 3600000),
  'Choose an available time between 9 am and 8 pm.', 'invalid-argument');
  return { fromMs: range[0], untilMs: range[1] };
}
export function createManagerCallbackService({ auth, store, phoneForUser = async () => null, now = Date.now }) {
  async function identity(transaction, adminOnly = false) {
    check(safeUid(auth?.uid), 'Log in again.', 'unauthenticated');
    const user = await transaction.get(`users/${auth.uid}`);
    check(user && user.paused !== true, 'This account is unavailable.', 'permission-denied');
    const admin = user.roles?.includes('admin') === true;
    check(adminOnly ? admin : admin || user.roles?.includes('owner'), 'Use your owner or team account.', 'permission-denied');
    if (!admin) check(/^\+91\d{10}$/.test(verifiedPhone(auth) ?? '') && user.phone === verifiedPhone(auth),
    'Verify your account phone first.', 'permission-denied');
    return { user, admin };
  }
  async function manager(transaction, assignment) {
    if (!safeUid(assignment?.managerUid)) return null;
    const profile = await transaction.get(`users/${assignment.managerUid}`);
    if (!profile?.roles?.includes('admin') || profile.paused === true) return null;
    return { uid: assignment.managerUid, name: String(profile.displayName ?? '').trim() || 'TrustKeyper manager',
      phone: assignment.phone, email: assignment.email };
  }
  function view(record, assigned, phone) {
    return { version: record?.version ?? 0, phone, manager: assigned, callback: record ?? null,
      availableWindows: ['soon', 'today_evening', 'tomorrow_morning', 'tomorrow_evening'].filter(choice => {
        try { callbackWindow(choice, now()); return true; } catch { return false; }
      }), serverTimeMs: now(), deliveryStatus: 'in_app_only' };
  }
  return {
    async read(input = {}) {
      return store.transaction(async transaction => {
        const { user, admin } = await identity(transaction);
        const uid = admin ? input.ownerUid : auth.uid;
        check(safeUid(uid), 'Choose an owner.', 'invalid-argument');
        const owner = uid === auth.uid ? user : await transaction.get(`users/${uid}`);
        check(owner?.roles?.includes('owner') && owner.paused !== true, 'This owner is unavailable.', 'permission-denied');
        if (admin) check(owner.phone === await phoneForUser(uid), 'The owner needs to verify their account phone.');
        const record = await transaction.get(`ownerCallbacks/${uid}`);
        const assignment = await transaction.get(`ownerManagers/${uid}`);
        return view(record, await manager(transaction, assignment), owner.phone ?? '');
      });
    },
    async list() {
      return store.transaction(async transaction => {
        await identity(transaction, true);
        return { records: await transaction.list('ownerCallbacks', 100) };
      });
    },
    async record(input) {
      check(input && ['request', 'cancel', 'assign', 'confirm', 'missed', 'complete'].includes(input.action), 'Choose a callback action.', 'invalid-argument');
      check(/^[a-f0-9]{32}$/.test(input.operationId ?? '') && Number.isSafeInteger(input.version) && input.version >= 0,
        'Reopen the request before saving.', 'invalid-argument');
      const payload = input.payload ?? {};
      check(payload && typeof payload === 'object' && !Array.isArray(payload), 'Invalid request.', 'invalid-argument');
      const digest = createHash('sha256').update(JSON.stringify([input.action, input.ownerUid ?? null, input.version, payload])).digest('hex');
      return store.transaction(async transaction => {
        const customerAction = ['request', 'cancel'].includes(input.action);
        const { user, admin } = await identity(transaction, !customerAction);
        check(!customerAction || !admin, 'Use the owner account for a callback request.', 'permission-denied');
        const uid = customerAction ? auth.uid : input.ownerUid;
        check(safeUid(uid), 'Choose an owner.', 'invalid-argument');
        const owner = customerAction ? user : await transaction.get(`users/${uid}`);
        check(owner?.roles?.includes('owner') && owner.paused !== true && /^\+91\d{10}$/.test(owner.phone ?? ''), 'The owner needs a verified phone.', 'failed-precondition');
        if (admin) check(owner.phone === await phoneForUser(uid), 'The owner needs to verify their account phone.');
        const operationKey = createHash('sha256').update(`${auth.uid}:${input.operationId}`).digest('hex');
        const operationPath = `callbackOperations/${operationKey}`;
        const replay = await transaction.get(operationPath);
        const recordPath = `ownerCallbacks/${uid}`;
        const current = await transaction.get(recordPath);
        const assignment = await transaction.get(`ownerManagers/${uid}`);
        let assigned = await manager(transaction, assignment);
        if (replay) {
          check(replay.digest === digest, 'This retry changed. Reopen the request.', 'already-exists');
          return view(current, assigned, owner.phone);
        }
        check((current?.version ?? 0) === input.version, 'This request changed. Reload before saving.', 'aborted');
        const limitsPath = `callbackLimits/${uid}`;
        const limits = customerAction ? await transaction.get(limitsPath) : null;
        const timestamp = now();
        let next = { ...(current ?? {}), ownerUid: uid, ownerName: String(owner.displayName ?? '').trim(),
          phone: owner.phone, version: (current?.version ?? 0) + 1, updatedAtMs: timestamp };
        if (input.action === 'request') {
          check(['property', 'plan', 'tenant'].includes(payload.topic), 'Choose what you need help with.', 'invalid-argument');
          const range = callbackWindow(payload.window, timestamp);
          const dateKey = Math.floor((timestamp + shift) / day);
          const count = limits?.dateKey === dateKey ? limits.count : 0;
          check(timestamp - (limits?.lastRequestMs ?? 0) >= 30000 && count < 6, 'Wait before requesting another call.', 'resource-exhausted');
          next = { ...next, status: 'requested', topic: payload.topic, window: payload.window,
            requestedFromMs: range.fromMs, requestedUntilMs: range.untilMs, requestedAtMs: timestamp,
            confirmedAtMs: null, scheduledAtMs: null, attemptedAtMs: null, outcome: null,
            createdAtMs: current?.createdAtMs ?? timestamp, managerUid: assigned?.uid ?? null };
          transaction.set(limitsPath, { dateKey, count: count + 1, lastRequestMs: timestamp });
        } else if (input.action === 'cancel') {
          check(['requested', 'confirmed', 'missed'].includes(current?.status), 'There is no open callback to cancel.');
          next.status = 'cancelled';
        } else if (input.action === 'assign') {
          check(safeUid(payload.managerUid), 'Choose an active team member.', 'invalid-argument');
          const team = await transaction.get(`users/${payload.managerUid}`);
          check(team?.roles?.includes('admin') && team.paused !== true, 'This team member is unavailable.', 'permission-denied');
          check(/^\+91\d{10}$/.test(payload.phone ?? '') && /^[^\s@]+@trustkeyper\.com$/i.test(payload.email ?? ''),
            'Enter the manager’s published work phone and company email.', 'invalid-argument');
          assigned = { uid: payload.managerUid, name: String(team.displayName ?? '').trim() || 'TrustKeyper manager', phone: payload.phone, email: payload.email.toLowerCase() };
          next.managerUid = assigned.uid;
          if (current?.status === 'confirmed' && current.managerUid !== assigned.uid) {
            next.status = 'requested'; next.scheduledAtMs = null; next.confirmedAtMs = null;
          }
          if (!current) { next.status = 'none'; next.createdAtMs = timestamp; }
          transaction.set(`ownerManagers/${uid}`, { managerUid: assigned.uid, phone: assigned.phone, email: assigned.email, updatedAtMs: timestamp });
        } else {
          check(assigned && current?.managerUid === assigned.uid, 'Assign an active manager before recording the call.');
          if (input.action === 'confirm') {
            check(current.status === 'requested', 'Only a requested callback can be confirmed.');
            check(Number.isSafeInteger(payload.scheduledAtMs) && payload.scheduledAtMs >= timestamp
              && payload.scheduledAtMs >= current.requestedFromMs && payload.scheduledAtMs <= current.requestedUntilMs,
              'Choose a future time inside the owner’s requested window.', 'invalid-argument');
            next.status = 'confirmed'; next.scheduledAtMs = payload.scheduledAtMs; next.confirmedAtMs = timestamp;
          } else {
            check(current.status === 'confirmed' && timestamp >= current.scheduledAtMs, 'Wait for the confirmed call time.');
            check(typeof payload.note === 'string' && payload.note.trim().length >= 10 && payload.note.length <= 1000,
              'Record what actually happened on the call.', 'invalid-argument');
            next.status = input.action === 'missed' ? 'missed' : 'completed';
            next.attemptedAtMs = timestamp; next.outcome = payload.note.trim();
          }
        }
        const result = view(next, assigned, owner.phone);
        transaction.set(recordPath, next);
        transaction.set(`ownerCallbacks/${uid}/events/${operationKey}`, { action: input.action, actorUid: auth.uid,
          version: next.version, createdAtMs: timestamp, status: next.status,
          topic: next.topic ?? null, window: next.window ?? null, managerUid: next.managerUid ?? null,
          scheduledAtMs: next.scheduledAtMs ?? null, attemptedAtMs: next.attemptedAtMs ?? null, outcome: next.outcome ?? null });
        transaction.set(operationPath, { digest, ownerUid: uid, action: input.action, version: next.version, createdAtMs: timestamp });
        return result;
      });
    },
  };
}
