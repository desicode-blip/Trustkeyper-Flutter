import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createMoveOutService, splitMoveOutCost } from '../../move-out-workflow.js';
import { createTenancyService } from '../../tenancy-workflow.js';
import { moveInPlan } from '../../move-in-plan.js';
import { reviewSnapshot } from '../../agreement-review.js';
import { approvalDigest } from '../../agreement-approvals.js';
import { createInspectionService } from '../../property-inspections.js';

const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
export function moveOutFixture() {
  let time = Date.parse('2026-11-10T12:00:00+05:30');
  let operation = 0;
  const party = (id, phone, role) => ({ id, name: `TEST ${id}`, phone, email: '',
    rentSharePaise: role === 'tenant' ? 1100000 : 2200000, depositSharePaise: role === 'tenant' ? 2200000 : 4400000 });
  const agreement = { schemaVersion: 2, revision: 1, propertyAddress: 'TEST move-out flat', propertyId: 'move-out-flat',
    propertyDetails: { rooms: 'Studio' }, owners: [party('owner', '+911111111111', 'owner')],
    tenants: [party('tenant', '+912222222222', 'tenant'), party('flatmate', '+913333333333', 'tenant')],
    monthlyRentPaise: 2200000, monthlyMaintenancePaise: 0, securityDepositPaise: 4400000,
    startDateISO: '2026-10-01T00:00:00.000Z', endDateISO: '2027-08-31T00:00:00.000Z', rentDueDay: 5,
    lockInMonths: 0, noticeMonths: 1, ownerBrokeragePaise: 0, tenantBrokeragePaise: 0,
    brokerUid: 'broker', participantUids: ['broker', 'owner', 'tenant', 'flatmate'], status: 'active' };
  agreement.agreementCopy = { mode: 'externally_signed', revision: 1, digest: approvalDigest(reviewSnapshot(agreement)),
    people: [...agreement.owners.map(person => ({ ...person, uid: person.id, role: 'owner' })),
      ...agreement.tenants.map(person => ({ ...person, uid: person.id, role: 'tenant' }))] };
  const layout = { bedrooms: 0, washrooms: 1, balcony: false };
  const notice = { date: '2026-11-10', personIds: ['tenant', 'flatmate'], createdAtMs: time - 31 * 86400000,
    createdBy: 'tenant', participantUids: agreement.participantUids, status: 'notice_received' };
  const records = new Map(Object.entries({ 'agreements/move-out-home': agreement,
    'properties/move-out-flat': { brokerUid: 'broker', activeAgreementId: 'move-out-home' },
    'moveOuts/move-out-home': { ...notice, version: 1 },
    'tenancies/move-out-home': { version: 1, revision: 1, digest: agreement.agreementCopy.digest, phase: 'active',
      notice, roomConfiguration: layout, photoSlots: {}, baselinePhotoIds: [], absentItems: {},
      keys: { mainDoor: 2, bedrooms: 0, letterBox: 1, parkingCard: 1 }, meters: { noGas: true,
        electricity: { reading: '100', checkId: 'before-electricity' }, water: { reading: '100', checkId: 'before-water' } } },
    'users/broker': { roles: ['broker'], approvalStatus: 'approved' }, 'users/owner': { roles: ['owner'] },
    'users/tenant': { roles: ['tenant'] }, 'users/flatmate': { roles: ['tenant'] }, 'users/outsider': { roles: ['tenant'] },
    'users/admin': { roles: ['admin'] } }));
  const store = { timestamp: () => new Date(time), transaction: async handler => {
    let wrote = false;
    const writes = [];
    const result = await handler({
      get: async path => { assert.equal(wrote, false, 'All Firestore reads precede writes'); return structuredClone(records.get(path)); },
      set: (path, value) => { wrote = true; writes.push(() => records.set(path, structuredClone(value))); },
      update: (path, value) => { wrote = true; writes.push(() => records.set(path, { ...records.get(path), ...structuredClone(value) })); },
    });
    writes.forEach(write => write()); return result;
  } };
  const auth = uid => uid ? { uid, token: { phone_number: agreement.agreementCopy.people.find(person => person.uid === uid)?.phone,
    firebase: { sign_in_provider: 'phone' } } } : null;
  const service = uid => createMoveOutService({ auth: auth(uid), store, now: () => time, code: () => '654321',
    tenancy: createTenancyService({ auth: auth(uid), store, now: () => time }) });
  const base = { agreementId: 'move-out-home', role: 'broker' };
  const action = (name, payload, uid = 'broker') => service(uid).record({ ...base, role: uid === 'flatmate' ? 'tenant' : uid,
    version: records.get('moveOuts/move-out-home').version, operationId: (++operation).toString(16).padStart(32, '0'), action: name, payload });
  const addPhoto = (id, purpose, itemId, uid = 'broker') => records.set(`properties/move-out-flat/photoChecks/${id}`, {
    agreementId: 'move-out-home', revision: 1, actorRole: uid === 'broker' ? 'broker' : 'tenant', createdBy: uid,
    purpose, itemId, file: { generation: '1', sha256: 'a'.repeat(64) }, status: 'submitted' });
  const state = records.get('tenancies/move-out-home');
  for (const room of moveInPlan(agreement, layout)) for (const item of room.items) {
    const id = hash(['before', item.id]).slice(0, 32);
    addPhoto(id, 'move_in', item.id); state.photoSlots[`move_in:${item.id}`] = id; state.baselinePhotoIds.push(id);
  }
  for (const kind of ['electricity', 'water']) {
    addPhoto(`before-${kind}`, 'move_in_meter', kind); state.photoSlots[`move_in_meter:${kind}`] = `before-${kind}`;
  }
  for (const person of agreement.tenants) {
    records.set(`rentPaymentAccounts/${hash(['live', 'move-out-home', 1, person.id])}`, { depositPaid: true,
      firstPaymentId: `pay_${person.id}`, firstPaymentMonth: '2026-10', paidMonths: ['2026-10', '2026-11'], paymentIdsByMonth: { '2026-11': `pay_${person.id}` } });
    records.set(`payments/pay_${person.id}`, { mode: 'live', status: 'paid', currency: 'INR', captured: true, providerVerified: true,
      agreementId: 'move-out-home', revision: 1, payerUid: person.id, depositPaise: person.depositSharePaise, amountPaise: 4400000,
      lines: [{ month: '2026-10', totalPaise: 1100000 }, { month: '2026-11', totalPaise: 1100000 }] });
  }
  async function inspect(cost = 0) {
    const current = await service('broker').read(base);
    for (const room of current.rooms) for (const item of room.items) {
      const id = hash(['after', item.id]).slice(0, 32);
      addPhoto(id, 'move_out', item.id);
      const record = records.get('moveOuts/move-out-home');
      record.photoSlots = { ...record.photoSlots, [`move_out:${item.id}`]: id };
      await action('compare', { itemId: item.id, checkId: id, condition: cost && item.id === current.rooms[0].items[0].id ? 'repair' : 'same',
        costPaise: item.id === current.rooms[0].items[0].id ? cost : 0, note: 'Reviewed actual before and after.' });
    }
    const meters = {};
    for (const kind of ['electricity', 'water']) {
      addPhoto(`after-${kind}`, 'move_out_meter', kind);
      meters[kind] = { reading: '120', checkId: `after-${kind}` };
    }
    await action('meters', meters);
    await action('keys', { counts: state.keys, personId: 'tenant' });
    const issued = await service('tenant').issueCode({ ...base, role: 'tenant', countsConfirmed: true });
    await action('confirm_keys', { code: issued.code, challengeId: issued.challengeId });
  }
  return { records, store, auth, service, base, action, inspect, addPhoto, advance: amount => { time += amount; },
    photos: uid => createInspectionService({ auth: auth(uid), store, now: () => time, files: {
      snapshot: async () => ({ generation: '1', sha256: 'a'.repeat(64) }), cleanup: async () => {} } }) };
}

