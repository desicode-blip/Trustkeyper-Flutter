import { verifiedPhone } from './verified-phone.js';
import { approvalDigest } from './agreement-approvals.js';
import { reviewSnapshot } from './agreement-review.js';

export class TenantSetupError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const requireValue = (condition, message, code = 'failed-precondition') => {
  if (!condition) throw new TenantSetupError(code, message);
};
const money = value => Number.isSafeInteger(value) && value >= 0;
const safeId = value => typeof value === 'string' && /^[\w-]{1,128}$/.test(value);
const clean = value => typeof value === 'string' ? value.trim() : '';

export function createTenantSetupService({ auth, store, now = Date.now }) {
  async function profile(transaction, admin = false) {
    requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
    const user = await transaction.get(`users/${auth.uid}`);
    requireValue(user && user.paused !== true && user.roles?.includes(admin ? 'admin' : 'tenant'),
      'This account cannot open this request.', 'permission-denied');
    return user;
  }
  async function context(transaction, input) {
    await profile(transaction);
    requireValue(safeId(input.agreementId), 'Choose your linked agreement.', 'invalid-argument');
    const agreement = await transaction.get(`agreements/${input.agreementId}`);
    requireValue(agreement && agreement.participantUids?.includes(auth.uid),
      'This home is not linked to your account.', 'permission-denied');
    requireValue(!['cancelled', 'deleted', 'terminated'].includes(agreement.status), 'This agreement is no longer active.');
    requireValue(safeId(agreement.brokerUid), 'Your broker details need team review.');
    const broker = await transaction.get(`users/${agreement.brokerUid}`);
    const tenants = Array.isArray(agreement.tenants) ? agreement.tenants : [];
    const links = (agreement.agreementCopy?.people ?? []).filter(person => person.role === 'tenant' && person.uid === auth.uid);
    const phone = verifiedPhone(auth);
    const matches = tenants.filter(party => party && (party.uid === auth.uid ||
      links.some(link => link.id === party.id && link.phone === party.phone) || (phone && party.phone === phone)));
    requireValue(matches.length === 1, 'Your tenant details need team review.', 'permission-denied');
    requireValue(Number.isSafeInteger(agreement.revision) && agreement.revision > 0,
      'Your agreement needs a saved revision. Ask your broker to review it.');
    requireValue(tenants.length > 0 && money(agreement.monthlyRentPaise) &&
      tenants.every(party => money(party.rentSharePaise) && money(party.depositSharePaise)) &&
      tenants.reduce((total, party) => total + party.rentSharePaise, 0) === agreement.monthlyRentPaise,
      'The rent shares need correction by your broker before you confirm.');
    const key = `${input.agreementId}_${agreement.revision}_${auth.uid}`;
    const saved = await transaction.get(`tenantSetups/${key}`);
    return { agreement, party: matches[0], tenants, key, saved, broker };
  }
  function response(current) {
    const { agreement, party, tenants, saved, broker } = current;
    return {
      revision: agreement.revision, property: clean(agreement.propertyAddress) || clean(agreement.propertyName) || 'Your linked home',
      ownerNames: (Array.isArray(agreement.owners) ? agreement.owners : []).map(owner => clean(owner?.name)).filter(Boolean),
      brokerName: clean(broker?.displayName) || clean(agreement.brokerName) || 'your broker',
      tenants: tenants.map(tenant => ({ name: clean(tenant.name) || 'Tenant', phone: clean(tenant.phone),
        you: tenant === party, rentSharePaise: tenant.rentSharePaise })),
      rentSharePaise: party.rentSharePaise, depositSharePaise: party.depositSharePaise,
      monthlyRentPaise: agreement.monthlyRentPaise,
      homeConfirmed: saved?.homeConfirmed === true, flatmatesConfirmed: saved?.flatmatesConfirmed === true,
      complete: saved?.complete === true, request: saved?.request ?? null,
    };
  }
  return {
    async read(input) { return store.transaction(async transaction => response(await context(transaction, input))); },
    async record(input) {
      return store.transaction(async transaction => {
        const current = await context(transaction, input);
        const { agreement, saved, key, party } = current;
        requireValue(input.revision === agreement.revision, 'The agreement changed. Reopen it before confirming.', 'aborted');
        requireValue(['home', 'flatmates', 'complete', 'request'].includes(input.action), 'Choose a confirmation.', 'invalid-argument');
        if (saved?.request?.status === 'pending' && input.action === 'request' &&
          saved.request.kind === input.kind && saved.request.note === clean(input.note) &&
          (input.kind !== 'share' || saved.request.rentSharePaise === input.rentSharePaise)) return response(current);
        requireValue(!saved?.request || saved.request.status === 'resolved', 'Your correction is waiting for team review.');
        const next = { ...(saved ?? {}), agreementId: input.agreementId, revision: agreement.revision,
          tenantUid: auth.uid, tenantName: clean(party.name), brokerUid: agreement.brokerUid,
          property: clean(agreement.propertyAddress) || clean(agreement.propertyName), updatedAtMs: now() };
        if (input.action === 'home') next.homeConfirmed = true;
        if (input.action === 'flatmates') {
          requireValue(next.homeConfirmed, 'Confirm your home first.'); next.flatmatesConfirmed = true;
        }
        if (input.action === 'complete') {
          requireValue(next.homeConfirmed && next.flatmatesConfirmed, 'Confirm your home and flatmates first.');
          next.complete = true; next.confirmedRentSharePaise = party.rentSharePaise;
          next.confirmedDepositSharePaise = party.depositSharePaise;
        }
        if (input.action === 'request') {
          requireValue(['home', 'flatmates', 'share'].includes(input.kind), 'Choose what needs correction.', 'invalid-argument');
          const note = clean(input.note);
          requireValue(note.length <= 2000, 'Keep your note within 2,000 characters.', 'invalid-argument');
          if (input.kind === 'share') {
            requireValue(next.homeConfirmed && next.flatmatesConfirmed, 'Confirm your home and flatmates first.');
            requireValue(money(input.rentSharePaise) && input.rentSharePaise > 0 &&
              input.rentSharePaise <= agreement.monthlyRentPaise, 'Your share must be within the total rent.', 'invalid-argument');
            requireValue(input.rentSharePaise !== party.rentSharePaise, 'Enter a different share.', 'invalid-argument');
          }
          next.complete = false;
          next.request = { kind: input.kind, note, status: 'pending', requestedAtMs: now(),
            ...(input.kind === 'share' ? { rentSharePaise: input.rentSharePaise } : {}) };
          transaction.set(`adminAuditLogs/tenant_setup_${key}`, { action: 'tenant_setup_correction_requested',
            actorUid: auth.uid, agreementId: input.agreementId, revision: agreement.revision,
            requestId: key, createdAtMs: now() });
        }
        transaction.set(`tenantSetups/${key}`, next);
        return response({ ...current, saved: next });
      });
    },
    async list() {
      await store.transaction(async transaction => profile(transaction, true));
      return { requests: await store.pending() };
    },
    async resolve(input) {
      requireValue(safeId(input.agreementId) && safeId(input.tenantUid) && Number.isSafeInteger(input.revision),
        'Choose the original request.', 'invalid-argument');
      const key = `${input.agreementId}_${input.revision}_${input.tenantUid}`;
      return store.transaction(async transaction => {
        await profile(transaction, true);
        const saved = await transaction.get(`tenantSetups/${key}`);
        const agreement = await transaction.get(`agreements/${input.agreementId}`);
        requireValue(saved?.request && agreement, 'This request is unavailable.');
        if (saved.request.status === 'resolved') return { resolved: true };
        requireValue(agreement.revision > saved.revision && ['signed_copy_received', 'active'].includes(agreement.status) &&
          agreement.agreementCopy?.revision === agreement.revision && agreement.agreementCopy?.mode === 'externally_signed',
          'Publish the corrected, externally signed agreement revision before resolving this request.');
        requireValue(agreement.agreementCopy.digest === approvalDigest(reviewSnapshot(agreement)),
          'The signed copy does not match the corrected agreement terms.');
        const links = (agreement.agreementCopy.people ?? []).filter(person => person.role === 'tenant' && person.uid === saved.tenantUid);
        const matches = (agreement.tenants ?? []).filter(party => links.some(link => link.id === party.id && link.phone === party.phone));
        if (saved.request.kind === 'home') {
          requireValue(!agreement.participantUids?.includes(saved.tenantUid) && matches.length === 0,
            'The tenant is still linked to this home. Correct the agreement membership first.');
        } else {
          requireValue(matches.length === 1 && agreement.participantUids?.includes(saved.tenantUid),
            'The tenant must remain correctly linked to the revised agreement.');
          if (saved.request.kind === 'share') requireValue(matches[0].rentSharePaise === saved.request.rentSharePaise &&
            (agreement.tenants ?? []).every(party => money(party.rentSharePaise)) &&
            agreement.tenants.reduce((total, party) => total + party.rentSharePaise, 0) === agreement.monthlyRentPaise,
            'The signed revision does not contain the requested share.');
        }
        transaction.update(`tenantSetups/${key}`, { request: { ...saved.request, status: 'resolved',
          resolvedBy: auth.uid, resolvedAtMs: now(), correctedRevision: agreement.revision }, updatedAtMs: now() });
        transaction.set(`adminAuditLogs/tenant_setup_resolved_${key}`, { action: 'tenant_setup_correction_resolved',
          actorUid: auth.uid, agreementId: input.agreementId, revision: agreement.revision,
          requestId: key, createdAtMs: now() });
        return { resolved: true };
      });
    },
  };
}
