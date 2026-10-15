import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHash } from 'node:crypto';
import { createTenancyService } from '../tenancy-workflow.js';
import { moveInPlan } from '../move-in-plan.js';
import { reviewSnapshot } from '../agreement-review.js';
import { approvalDigest } from '../agreement-approvals.js';

const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const initialTime = Date.parse('2026-10-10T12:00:00+05:30');
export function tenancyFixture() {
  const person = (id, phone, role) => ({ id, name: `Test ${id}`, phone, email: '',
    rentSharePaise: role === 'tenant' ? 1100000 : 2200000, depositSharePaise: role === 'tenant' ? 2200000 : 4400000 });
  const agreement = { schemaVersion: 2, revision: 1, propertyAddress: 'Emulator Test Flat 402', propertyId: 'tenancy-flat',
    propertyDetails: { rooms: '2 BHK' }, owners: [person('owner', '+911111111111', 'owner')],
    tenants: [person('tenant', '+912222222222', 'tenant'), person('flatmate', '+913333333333', 'tenant')],
    monthlyRentPaise: 2200000, monthlyMaintenancePaise: 0, securityDepositPaise: 4400000,
    startDateISO: '2026-10-01T00:00:00.000Z', endDateISO: '2027-08-31T00:00:00.000Z', rentDueDay: 5,
    lockInMonths: 6, noticeMonths: 1, ownerBrokeragePaise: 0, tenantBrokeragePaise: 0,
    brokerUid: 'broker', participantUids: ['broker', 'owner', 'tenant', 'flatmate'], status: 'signed_copy_received' };
  agreement.agreementCopy = { mode: 'externally_signed', revision: 1, digest: approvalDigest(reviewSnapshot(agreement)),
    people: [...agreement.owners.map(person => ({ ...person, role: 'owner', uid: person.id })),
      ...agreement.tenants.map(person => ({ ...person, role: 'tenant', uid: person.id }))] };
  const records = new Map(Object.entries({ 'agreements/tenancy-home': agreement,
    'properties/tenancy-flat': { brokerUid: 'broker', address: agreement.propertyAddress },
    'users/broker': { roles: ['broker'], approvalStatus: 'approved' },
    'users/owner': { roles: ['owner'] }, 'users/tenant': { roles: ['tenant'] },
    'users/flatmate': { roles: ['tenant'] }, 'users/outsider': { roles: ['tenant'] }, 'users/admin': { roles: ['admin'] } }));
  records.set('tenancies/tenancy-home', { version: 0, phase: 'preparing', revision: 1, digest: agreement.agreementCopy.digest,
    absentItems: {}, roomConfiguration: { bedrooms: 2, washrooms: 2, balcony: true }, photoSlots: {} });
  let time = initialTime;
  const store = { transaction: async handler => {
    let wrote = false;
    const writes = [];
    const result = await handler({
      get: async path => { assert.equal(wrote, false, 'Firestore reads must precede writes'); return structuredClone(records.get(path)); },
      list: async path => { assert.equal(wrote, false); return [...records].filter(([key]) => key.startsWith(`${path}/`))
        .map(([key, value]) => ({ ...structuredClone(value), id: key.split('/').at(-1) })); },
      set: (path, value) => { wrote = true; writes.push(() => records.set(path, structuredClone(value))); },
      update: (path, value) => { wrote = true; writes.push(() => records.set(path, { ...records.get(path), ...structuredClone(value) })); },
    });
    writes.forEach(write => write()); return result;
  } };
  const service = uid => createTenancyService({ store, now: () => time, code: () => '654321', auth: uid ? { uid,
    token: { phone_number: agreement.agreementCopy.people.find(person => person.uid === uid)?.phone,
      firebase: { sign_in_provider: 'phone' } } } : null });
  const base = { agreementId: 'tenancy-home', role: 'broker' };
  let operation = 0;
  const action = async (name, payload, uid = 'broker', role = uid) => service(uid).record({ ...base, role,
    version: records.get('tenancies/tenancy-home')?.version ?? 0, action: name, payload, operationId: (++operation).toString(16).padStart(32, '0') });
  function addPayments(mode = 'live') {
    for (const person of agreement.tenants) {
      const accountId = hash([mode, 'tenancy-home', 1, person.id]);
      records.set(`rentPaymentAccounts/${accountId}`, { depositPaid: true, paidMonths: ['2026-10'], firstPaymentId: `pay_${person.id}`,
        firstPaymentMonth: '2026-10' });
      records.set(`payments/pay_${person.id}`, { mode, currency: 'INR', status: 'paid', providerVerified: true, captured: true,
        agreementId: 'tenancy-home', revision: 1, payerUid: person.id, amountPaise: 3300000, depositPaise: 2200000,
        lines: [{ month: '2026-10', totalPaise: 1100000 }] });
    }
  }
  function addPhotos() {
    const slots = records.get('tenancies/tenancy-home').photoSlots;
    for (const room of moveInPlan(agreement)) for (const item of room.items) {
      slots[`move_in:${item.id}`] = item.id;
      records.set(`properties/tenancy-flat/photoChecks/${item.id}`, { agreementId: 'tenancy-home', revision: 1,
        actorRole: 'broker', createdBy: 'broker', purpose: 'move_in', itemId: item.id, status: 'submitted', file: { generation: '1' } });
    }
    for (const kind of ['electricity', 'water', 'gas']) {
      slots[`move_in_meter:${kind}`] = `meter-${kind}`;
      records.set(`properties/tenancy-flat/photoChecks/meter-${kind}`, { agreementId: 'tenancy-home', revision: 1,
        actorRole: 'broker', createdBy: 'broker', purpose: 'move_in_meter', itemId: kind, status: 'submitted', file: { generation: '1' } });
    }
  }
  const meters = { noGas: true, electricity: { reading: '14582', checkId: 'meter-electricity' }, water: { reading: '3210.5', checkId: 'meter-water' } };
  const keys = { personId: 'tenant', counts: { mainDoor: 2, bedrooms: 2, letterBox: 1, parkingCard: 1 } };
  async function ready() { addPayments(); addPhotos(); await action('meters', meters); }
  return { records, service, base, action, addPayments, addPhotos, meters, keys, ready, advance: milliseconds => { time += milliseconds; } };
}

test('2 BHK move-in plan has the approved 64 room items, not invented progress', () => {
  const plan = moveInPlan({ propertyDetails: { rooms: '2 BHK' } });
  assert.deepEqual(plan.map(room => room.items.length), [10, 12, 9, 8, 8, 7, 4, 6]);
  assert.equal(plan.flatMap(room => room.items).length, 64);
  assert.equal(moveInPlan({}).length, 0);
});

test('the physical room plan is explicit, supports studio/half rooms, and freezes when evidence is received', async () => {
  const flow = tenancyFixture(); delete flow.records.get('tenancies/tenancy-home').roomConfiguration;
  assert.equal((await flow.service('broker').read(flow.base)).photoComplete, false);
  await flow.action('rooms', { bedrooms: 1, washrooms: 1, balcony: false, confirmedPhysicalLayout: true });
  assert.equal((await flow.service('broker').read(flow.base)).rooms.length, 5);
  await assert.rejects(flow.action('rooms', { bedrooms: -1, washrooms: 1, balcony: true, confirmedPhysicalLayout: true }), { code: 'invalid-argument' });
  flow.addPhotos();
  await assert.rejects(flow.action('rooms', { bedrooms: 2, washrooms: 2, balcony: true, confirmedPhysicalLayout: true }), { code: 'failed-precondition' });
  assert.ok(moveInPlan({ propertyDetails: { rooms: '1 RK' } }).length > 0);
  assert.ok(moveInPlan({ propertyDetails: { rooms: '1.5 BHK' } }).length > 0);
});

test('normal authenticated single-use key flow activates only after every live gate and schedules a quarterly check', async () => {
  const flow = tenancyFixture(); await flow.ready(); await flow.action('keys', flow.keys);
  const tenant = flow.service('tenant');
  const code = await tenant.issueCode({ ...flow.base, role: 'tenant', countsConfirmed: true });
  assert.equal(code.delivery, 'authenticated_tenant_screen');
  assert.equal((await flow.service('broker').read(flow.base)).challenge.code, undefined);
  const state = flow.records.get('tenancies/tenancy-home');
  const operation = { ...flow.base, action: 'confirm', version: state.version, operationId: 'f'.repeat(32),
    payload: { code: code.code, challengeId: code.challengeId } };
  assert.equal((await flow.service('broker').record(operation)).phase, 'active');
  assert.equal((await flow.service('broker').record(operation)).phase, 'active');
  assert.equal(flow.records.get('properties/tenancy-flat').occupancyStatus, 'rented');
  assert.equal(flow.records.get('properties/tenancy-flat').nextInspectionDate, '2027-01-10');
  assert.equal(flow.records.get(`keyHandoverChallenges/${code.challengeId}`).status, 'used');
  assert.equal([...flow.records.keys()].some(path => path.startsWith('payouts/')), false);
  await assert.rejects(flow.action('meters', flow.meters), { code: 'failed-precondition' });
});

test('TEST payments, missing flatmate payment, refunded money and reused another tenant payment cannot release keys', async () => {
  for (const variant of ['test', 'flatmate', 'refunded', 'payer', 'uncaptured', 'currency']) {
    const flow = tenancyFixture(); flow.addPhotos(); flow.addPayments(variant === 'test' ? 'test' : 'live');
    await flow.action('meters', flow.meters);
    const accountId = hash(['live', 'tenancy-home', 1, 'flatmate']);
    if (variant === 'flatmate') flow.records.delete(`rentPaymentAccounts/${accountId}`);
    if (variant === 'refunded') flow.records.get('payments/pay_flatmate').refundedPaise = 100;
    if (variant === 'payer') flow.records.get('payments/pay_flatmate').payerUid = 'tenant';
    if (variant === 'uncaptured') flow.records.get('payments/pay_flatmate').captured = false;
    if (variant === 'currency') flow.records.get('payments/pay_flatmate').currency = 'USD';
    await assert.rejects(flow.action('keys', flow.keys), { code: 'failed-precondition' });
    assert.equal(flow.records.get('properties/tenancy-flat').occupancyStatus, undefined);
  }
});

test('tenant photo, wrong revision, flagged item, unrelated meter and unknown room plan do not satisfy official evidence', async () => {
  const flow = tenancyFixture(); await flow.ready();
  const photo = flow.records.get('properties/tenancy-flat/photoChecks/room-0-item-0');
  photo.actorRole = 'tenant'; assert.equal((await flow.service('broker').read(flow.base)).photoComplete, false);
  photo.actorRole = 'broker'; photo.revision = 2; assert.equal((await flow.service('broker').read(flow.base)).photoComplete, false);
  photo.revision = 1; photo.status = 'flagged'; assert.equal((await flow.service('broker').read(flow.base)).photoComplete, false);
  await assert.rejects(flow.action('meters', { ...flow.meters, electricity: { reading: '12', checkId: 'room-0-item-0' } }), { code: 'invalid-argument' });
  await assert.rejects(flow.action('absent', { itemId: 'room-0-item-0', reason: 'No entrance door here.' }), { code: 'invalid-argument' });
  await flow.action('absent', { itemId: 'room-0-item-8', reason: 'No ceiling fans installed.' });
  assert.equal((await flow.service('owner').read({ ...flow.base, role: 'owner' })).rooms[0].items[8].absentReason, 'No ceiling fans installed.');
});

test('ownership, phone binding, paused profiles and changed signed terms are checked for every action', async () => {
  const flow = tenancyFixture(); await flow.ready();
  await assert.rejects(flow.service(null).read(flow.base), { code: 'unauthenticated' });
  await assert.rejects(flow.service('outsider').read({ ...flow.base, role: 'tenant' }), { code: 'permission-denied' });
  await assert.rejects(flow.action('keys', flow.keys, 'owner', 'owner'), { code: 'permission-denied' });
  await assert.rejects(flow.action('keys', flow.keys, 'tenant', 'broker'), { code: 'permission-denied' });
  flow.records.get('users/broker').paused = true;
  await assert.rejects(flow.service('broker').read(flow.base), { code: 'permission-denied' });
  flow.records.get('users/broker').paused = false;
  flow.records.get('agreements/tenancy-home').monthlyRentPaise = 2400000;
  await assert.rejects(flow.service('broker').read(flow.base));
});

test('code expiry, recipient isolation, cooldown and five attempts are server enforced across new challenges', async () => {
  const flow = tenancyFixture(); await flow.ready(); await flow.action('keys', flow.keys);
  await assert.rejects(flow.service('flatmate').issueCode({ ...flow.base, role: 'tenant', countsConfirmed: true }), { code: 'permission-denied' });
  const code = await flow.service('tenant').issueCode({ ...flow.base, role: 'tenant', countsConfirmed: true });
  await assert.rejects(flow.service('tenant').issueCode({ ...flow.base, role: 'tenant', countsConfirmed: true }), { code: 'resource-exhausted' });
  for (let index = 0; index < 5; index++) {
    assert.equal((await flow.action('confirm', { challengeId: code.challengeId, code: '000000' })).codeAccepted, false);
  }
  flow.advance(31000);
  await assert.rejects(flow.action('keys', flow.keys), { code: 'failed-precondition' });
  flow.advance(16 * 60000);
  await flow.action('keys', flow.keys);
  const replacement = await flow.service('tenant').issueCode({ ...flow.base, role: 'tenant', countsConfirmed: true });
  flow.advance(6 * 60000);
  await assert.rejects(flow.action('confirm', { challengeId: replacement.challengeId, code: replacement.code }), { code: 'failed-precondition' });
});

test('revoked payment, occupied property and pre-start date block even a valid tenant code', async () => {
  const flow = tenancyFixture(); await flow.ready(); await flow.action('keys', flow.keys);
  const code = await flow.service('tenant').issueCode({ ...flow.base, role: 'tenant', countsConfirmed: true });
  flow.records.get('payments/pay_tenant').refundedPaise = 3300000;
  await assert.rejects(flow.action('confirm', { challengeId: code.challengeId, code: code.code }), { code: 'failed-precondition' });
  flow.records.get('payments/pay_tenant').refundedPaise = 0;
  flow.records.get('properties/tenancy-flat').activeAgreementId = 'another-home';
  assert.equal((await flow.service('broker').read(flow.base)).canHandOver, false);
  flow.records.get('properties/tenancy-flat').activeAgreementId = null;
  flow.advance(-15 * 86400000);
  assert.equal((await flow.service('broker').read(flow.base)).canHandOver, false);
});

test('optimistic version and payload replay prevent stale meters and changed key counts', async () => {
  const flow = tenancyFixture(); await flow.ready();
  const request = { ...flow.base, version: 1, action: 'keys', payload: flow.keys, operationId: 'a'.repeat(32) };
  await flow.service('broker').record(request); await flow.service('broker').record(request);
  await assert.rejects(flow.service('broker').record({ ...request, payload: { ...flow.keys, personId: 'flatmate' } }), { code: 'aborted' });
  await assert.rejects(flow.service('broker').record({ ...request, operationId: 'b'.repeat(32) }), { code: 'aborted' });
});

test('move-out notice uses calendar-month notice, warns for lock-in and records in-app delivery without claiming a refund', async () => {
  const flow = tenancyFixture(); await flow.ready(); await flow.action('keys', flow.keys);
  const code = await flow.service('tenant').issueCode({ ...flow.base, role: 'tenant', countsConfirmed: true });
  await flow.action('confirm', { challengeId: code.challengeId, code: code.code });
  const notice = { date: '2026-11-10', personIds: ['tenant'], requestedBy: 'tenant', reason: 'Moving for work.' };
  await assert.rejects(flow.action('notice', { ...notice, date: '2026-11-09' }, 'tenant', 'tenant'), { code: 'invalid-argument' });
  await assert.rejects(flow.action('notice', notice, 'tenant', 'tenant'), { code: 'invalid-argument' });
  await flow.action('notice', { ...notice, lockInAcknowledged: true }, 'tenant', 'tenant');
  const saved = flow.records.get('moveOuts/tenancy-home');
  assert.equal(saved.deliveryStatus, 'in_app_only'); assert.equal(saved.refundStatus, 'not_started');
  assert.equal(flow.records.get('properties/tenancy-flat').occupancyStatus, 'rented');
  await assert.rejects(flow.action('notice', { ...notice, lockInAcknowledged: true }, 'tenant', 'tenant'), { code: 'failed-precondition' });
});

async function activeRentFixture() {
  const flow = tenancyFixture(); await flow.ready(); await flow.action('keys', flow.keys);
  const code = await flow.service('tenant').issueCode({ ...flow.base, role: 'tenant', countsConfirmed: true });
  await flow.action('confirm', { challengeId: code.challengeId, code: code.code });
  flow.advance(30 * 86400000);
  return flow;
}

test('rent follows exact verified unpaid shares, while a tenant promise never pays rent or changes the deadline', async () => {
  const flow = await activeRentFixture();
  const original = (await flow.service('tenant').read({ ...flow.base, role: 'tenant' })).rent[0];
  assert.equal(original.month, '2026-11'); assert.equal(original.amountPaise, 1100000);
  assert.equal(original.deadline, '2026-11-05'); assert.equal(original.daysLate, 4); assert.equal(original.lateFeePaise, 0);
  const payload = { personId: 'tenant', month: '2026-11', note: 'Salary will arrive on Friday.', date: '2026-11-13' };
  await assert.rejects(flow.action('rent_promise', payload, 'flatmate', 'tenant'), { code: 'permission-denied' });
  await flow.action('rent_promise', payload, 'tenant', 'tenant');
  const saved = (await flow.service('owner').read({ ...flow.base, role: 'owner' })).rent[0];
  assert.equal(saved.status, 'unpaid'); assert.equal(saved.deadline, original.deadline);
  assert.equal(saved.followUp.promise.status, 'requested'); assert.equal(saved.followUp.promise.date, '2026-11-13');
  assert.equal(saved.manualNoticeReviewRequired, false);
});

test('rent call notes and extensions require actual role, attestation, current versions and preserve the payment ledger', async () => {
  const flow = await activeRentFixture();
  const payload = { personId: 'tenant', month: '2026-11', note: 'Tenant confirmed a salary delay.', date: '2026-11-13' };
  await assert.rejects(flow.action('rent_call', payload), { code: 'invalid-argument' });
  await assert.rejects(flow.action('rent_call', { ...payload, contacted: true }, 'owner', 'owner'), { code: 'permission-denied' });
  await flow.action('rent_call', { ...payload, contacted: true });
  await assert.rejects(flow.action('rent_extension', payload), { code: 'invalid-argument' });
  await assert.rejects(flow.action('rent_extension', { ...payload, ownerInformed: true }, 'tenant', 'tenant'), { code: 'permission-denied' });
  const state = flow.records.get('tenancies/tenancy-home');
  const request = { ...flow.base, action: 'rent_extension', version: state.version, payload: { ...payload, ownerInformed: true }, operationId: 'e'.repeat(32) };
  await flow.service('broker').record(request); await flow.service('broker').record(request);
  await assert.rejects(flow.service('broker').record({ ...request, payload: { ...request.payload, date: '2026-11-20' } }), { code: 'aborted' });
  await assert.rejects(flow.action('rent_extension', { ...payload, date: '2026-11-12' }, 'owner', 'owner'), { code: 'invalid-argument' });
  const saved = (await flow.service('owner').read({ ...flow.base, role: 'owner' })).rent[0];
  assert.equal(saved.deadline, '2026-11-13'); assert.equal(saved.daysLate, 0); assert.equal(saved.status, 'unpaid');
  assert.equal(saved.followUp.history.length, 2); assert.equal(saved.followUp.extension.deliveryStatus, 'in_app_only');
  assert.equal(saved.followUp.lastCall.actorUid, 'broker');
  assert.equal(flow.records.get('payments/pay_tenant').amountPaise, 3300000);
  assert.equal([...flow.records.keys()].some(path => path.startsWith('payouts/')), false);
});

test('rent payment evidence cannot borrow another share or a TEST capture, and thirty days only requests human review', async () => {
  const flow = await activeRentFixture();
  const path = `rentPaymentAccounts/${hash(['live', 'tenancy-home', 1, 'tenant'])}`;
  flow.records.get(path).paymentIdsByMonth = { '2026-11': 'pay_november' };
  const payment = { mode: 'test', currency: 'INR', status: 'paid', captured: true, providerVerified: true,
    agreementId: 'tenancy-home', revision: 1, payerUid: 'tenant', amountPaise: 1100000, depositPaise: 0,
    lines: [{ month: '2026-11', totalPaise: 1100000 }] };
  flow.records.set('payments/pay_november', payment);
  assert.equal((await flow.service('broker').read(flow.base)).rent[0].status, 'unpaid');
  payment.mode = 'live'; payment.payerUid = 'flatmate';
  assert.equal((await flow.service('broker').read(flow.base)).rent[0].status, 'unpaid');
  payment.payerUid = 'tenant'; payment.amountPaise = 1;
  assert.equal((await flow.service('broker').read(flow.base)).rent[0].status, 'unpaid');
  payment.amountPaise = 1100000;
  assert.equal((await flow.service('broker').read(flow.base)).rent[0].status, 'paid');
  payment.refundedPaise = 1100000; flow.advance(30 * 86400000);
  const late = (await flow.service('broker').read(flow.base)).rent[0];
  assert.equal(late.manualNoticeReviewRequired, true); assert.equal(late.lateFeePaise, 0);
  assert.equal(flow.records.get('moveOuts/tenancy-home'), undefined);
});
