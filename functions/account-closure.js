import { createHash, randomUUID } from 'node:crypto';

export class AccountClosureError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const requireValue = (condition, message, code = 'failed-precondition') => {
  if (!condition) throw new AccountClosureError(code, message);
};
const safe = value => typeof value === 'string' && /^[\w-]{1,128}$/.test(value);
const closedStates = ['closing', 'closed', 'restoring'];
const terminalAgreements = ['cancelled', 'terminated', 'completed'];

export function createAccountClosureService({ auth, store, identity, now = Date.now }) {
  async function profile(transaction, admin = false) {
    requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
    const current = await transaction.get(`users/${auth.uid}`);
    requireValue(current && (admin
      ? current.roles?.includes('admin') && current.paused !== true
      : !current.roles?.includes('admin') &&
        current.roles?.some(role => ['broker', 'owner', 'tenant'].includes(role)) &&
        (current.paused !== true || closedStates.includes(current.accountClosure?.status))),
    'This account is unavailable.', 'permission-denied');
    return current;
  }
  async function eligibility(transaction, current) {
    const agreements = await transaction.related('agreements', 'participantUids', auth.uid, true);
    const payouts = await transaction.related('payouts', 'participantUids', auth.uid, true);
    const intents = await transaction.related('rentPaymentIntents', 'payerUid', auth.uid, false);
    const refunds = await transaction.related('moveOutRefundRequests', 'uid', auth.uid, false);
    const blockers = [];
    if (agreements.some(record => !terminalAgreements.includes(record.status) &&
      record.agreementCopy?.mode === 'externally_signed')) {
      blockers.push('Close or transfer your active signed agreements with the team first.');
    }
    const due = payouts.filter(record => record.mode !== 'test' &&
      record.recipientUid === auth.uid && !['paid', 'settled', 'cancelled', 'reversed'].includes(record.status));
    if (payouts.some(record => record.mode !== 'test' && !record.recipientUid &&
        !['paid', 'settled', 'cancelled', 'reversed'].includes(record.status))) {
      blockers.push('The team must reconcile an unsettled payment record first.');
    }
    if (due.length) blockers.push('Money still due to you must be settled before closing your account.');
    if (intents.some(record => record.mode !== 'test' &&
      !['paid', 'creation_failed', 'cancelled', 'refunded'].includes(record.status))) {
      blockers.push('Finish or reconcile your outstanding payment checkout first.');
    }
    for (const refund of refunds) {
      if (['paid', 'refunded', 'cancelled'].includes(refund.status)) continue;
      const payment = /^pay_[A-Za-z0-9]+$/.test(refund.paymentId ?? '')
        ? await transaction.get(`payments/${refund.paymentId}`) : null;
      if (payment?.mode !== 'test' || payment.payerUid !== auth.uid) {
        blockers.push('Your outstanding deposit refund must be settled or reconciled first.');
        break;
      }
    }
    const duePaise = due.reduce((total, record) => total + record.amountPaise, 0);
    const amountKnown = Number.isSafeInteger(duePaise) && due.every(record => Number.isSafeInteger(record.amountPaise) && record.amountPaise >= 0);
    if (!amountKnown) blockers.push('The outstanding amount needs team review.');
    return { canClose: blockers.length === 0, blockers,
      duePaise: amountKnown ? duePaise : null,
      status: current.accountClosure?.status ?? 'open',
      requiresLogin: !Number.isSafeInteger(auth.token?.auth_time) ||
        now() - auth.token.auth_time * 1000 > 10 * 60000 ||
        auth.token.auth_time * 1000 > now() + 60000 };
  }

  async function complete(uid, operation, restore = false, admin = false) {
    const attempt = randomUUID();
    const status = restore ? 'restoring' : 'closing';
    const result = await store.transaction(async transaction => {
      if (admin) await profile(transaction, true);
      const person = await transaction.get(`users/${uid}`);
      const closure = await transaction.get(`accountClosures/${uid}`);
      requireValue(person && closure && closure.operation === operation &&
        person.accountClosure?.operation === operation,
      'The account request changed. Contact the team.', 'aborted');
      if (closure.status === (restore ? 'restored' : 'closed')) {
        requireValue(person.paused === !restore && person.accountClosure.status === closure.status,
          'The account access state needs team review.', 'aborted');
        return closure;
      }
      requireValue(closure.status === status && person.paused === true,
        'The account request is not ready.', 'aborted');
      requireValue(!closure.mutationUntilMs || closure.mutationUntilMs <= now(),
        'This request is already being confirmed. Wait a moment and retry.', 'unavailable');
      transaction.update(`accountClosures/${uid}`, { mutationAttempt: attempt, mutationUntilMs: now() + 120000 });
      return null;
    });
    if (result) return restore ? { restored: true } : { closed: true, status: 'closed',
      restoreUntilMs: result.restoreUntilMs, recordsRetained: true };
    try {
      if (restore) {
        await identity.enable(uid);
      } else {
        await identity.disable(uid);
        await identity.revoke(uid);
      }
      return await store.transaction(async transaction => {
        if (admin) await profile(transaction, true);
        const person = await transaction.get(`users/${uid}`);
        const closure = await transaction.get(`accountClosures/${uid}`);
        requireValue(person && closure && closure.operation === operation &&
          person.accountClosure?.operation === operation && closure.status === status &&
          closure.mutationAttempt === attempt,
        'The account request changed. Access remains paused.', 'aborted');
        const confirmedAtMs = now();
        const completed = { ...person.accountClosure, status: restore ? 'restored' : 'closed',
          ...(restore ? { restoredAtMs: confirmedAtMs } : { closedAtMs: confirmedAtMs,
            restoreUntilMs: confirmedAtMs + 7 * 86400000 }) };
        transaction.update(`users/${uid}`, { paused: !restore, accountClosure: completed, updatedAtMs: now() });
        transaction.update(`accountClosures/${uid}`, { ...completed, mutationAttempt: '', mutationUntilMs: 0 });
        transaction.set(`adminAuditLogs/account_${restore ? 'restored' : 'closed'}_${operation}`,
          { action: restore ? 'account_restored' : 'account_closed', actorUid: auth.uid, targetUid: uid, createdAtMs: now() });
        return restore ? { restored: true } : { closed: true, status: 'closed',
          restoreUntilMs: completed.restoreUntilMs, recordsRetained: true };
      });
    } catch (_) {
      await store.transaction(async transaction => {
        const closure = await transaction.get(`accountClosures/${uid}`);
        if (closure?.mutationAttempt === attempt && closure.operation === operation) {
          transaction.update(`accountClosures/${uid}`, { mutationAttempt: '', mutationUntilMs: 0 });
        }
      }).catch(() => {});
      throw new AccountClosureError('unavailable', `${restore ? 'Restoration' : 'Closure'} could not be confirmed. Retry; access remains paused.`);
    }
  }
  return {
    async read() {
      return store.transaction(async transaction => eligibility(transaction, await profile(transaction)));
    },
    async close(input) {
      requireValue(safe(input.operationId) && input.confirmed === true,
        'Confirm the final account closure step.', 'invalid-argument');
      requireValue(['', 'stopped', 'difficult', 'another_app', 'other'].includes(input.reason ?? '') &&
        typeof (input.note ?? '') === 'string' && (input.note ?? '').trim().length <= 500,
      'Choose an optional reason and keep the note within 500 characters.', 'invalid-argument');
      const requestedOperation = createHash('sha256').update(JSON.stringify([auth?.uid, input.operationId])).digest('hex');
      const operation = await store.transaction(async transaction => {
        const current = await profile(transaction);
        if (current.accountClosure?.status === 'closed') return current.accountClosure.operation;
        if (current.accountClosure?.status === 'closing') {
          return current.accountClosure.operation;
        }
        requireValue(!current.accountClosure || current.accountClosure.status === 'restored',
          'The team is processing this account.');
        const result = await eligibility(transaction, current);
        requireValue(result.canClose, result.blockers.join('\n'));
        requireValue(!result.requiresLogin, 'For safety, log in again before closing your account.', 'unauthenticated');
        const closure = { status: 'closing', operation: requestedOperation, requestedAtMs: now(), restoreUntilMs: now() + 7 * 86400000,
          reason: input.reason ?? '', note: (input.note ?? '').trim() };
        transaction.update(`users/${auth.uid}`, { paused: true, accountClosure: closure, updatedAtMs: now() });
        transaction.set(`accountClosures/${auth.uid}`, { uid: auth.uid, displayName: current.displayName ?? '', ...closure });
        transaction.set(`adminAuditLogs/account_closure_${requestedOperation}`,
          { action: 'account_closure_started', actorUid: auth.uid, createdAtMs: now() });
        return requestedOperation;
      });
      return complete(auth.uid, operation);
    },
    async list() {
      await store.transaction(transaction => profile(transaction, true));
      return { requests: await store.pending() };
    },
    async finish(input) {
      requireValue(safe(input.uid), 'Choose the pending closure.', 'invalid-argument');
      const operation = await store.transaction(async transaction => {
        await profile(transaction, true);
        const closure = await transaction.get(`accountClosures/${input.uid}`);
        requireValue(closure && ['closing', 'closed'].includes(closure.status), 'Only an already requested closure can be completed.');
        return closure.operation;
      });
      return complete(input.uid, operation, false, true);
    },
    async restore(input) {
      requireValue(safe(input.uid), 'Choose the closed account.', 'invalid-argument');
      const operation = await store.transaction(async transaction => {
        await profile(transaction, true);
        const person = await transaction.get(`users/${input.uid}`);
        const closure = await transaction.get(`accountClosures/${input.uid}`);
        requireValue(person && !person.roles?.includes('admin') &&
          person.roles?.some(role => ['broker', 'owner', 'tenant'].includes(role)) &&
          closure && ['closed', 'restoring', 'restored'].includes(closure.status) &&
          person.accountClosure?.operation === closure.operation &&
          (closure.restoreUntilMs > now() || closure.status === 'restoring' &&
            closure.restorationStartedAtMs < closure.restoreUntilMs),
        'Only a confirmed closure within its seven-day restoration window can be restored.');
        if (closure.status === 'closed') {
          transaction.update(`users/${input.uid}`, { accountClosure: { ...person.accountClosure, status: 'restoring' } });
          transaction.update(`accountClosures/${input.uid}`, { status: 'restoring', restorationStartedAtMs: now() });
        }
        return closure.operation;
      });
      return complete(input.uid, operation, true, true);
    },
  };
}
