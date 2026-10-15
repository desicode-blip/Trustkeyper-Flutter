import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createOwnerPropertyService, validateOwnerPropertyStep } from '../owner-properties.js';

test('owner setup accepts empty labels and arbitrary optional flat names', () => {
  for (const address of ['', 'rjh', '1', '402', 'A', '22/B', 'घर']) {
    assert.doesNotThrow(() => validateOwnerPropertyStep(0, { address, name: 'A', homeType: 'Apartment' }));
  }
  assert.doesNotThrow(() => validateOwnerPropertyStep(0, { address: '402', name: '', homeType: 'Apartment' }));
  assert.doesNotThrow(() => validateOwnerPropertyStep(0, { address: '   ', name: 'rjh', homeType: 'Apartment' }));
});

const steps = [
  { address: 'TEST ONLY Flat 1, Example Road, Hyderabad', name: 'TEST home', homeType: 'Apartment' },
  { rooms: '2 BHK', bathrooms: 2, balconies: 1, floor: 2, totalFloors: 5, sizeSqFt: 1000, furnishing: 'Semi' },
  { features: ['AC', 'Lift'], pets: 'Ask me' },
  { rentPaise: 2000000, maintenancePaise: 200000, depositPaise: 4000000, availableFrom: '2026-10-11', whoCanStay: 'Anyone', negotiable: false },
  { teamPhotos: true },
];
function fixture() {
  let records = new Map([['users/owner', { roles: ['owner'], phone: '+911111111111' }],
    ['users/other', { roles: ['owner'], phone: '+912222222222' }], ['users/admin', { roles: ['admin'] }]]);
  const clock = { value: Date.parse('2026-10-10T06:00:00Z') };
  const store = { transaction: async handler => {
    const next = structuredClone(records); let wrote = false;
    const result = await handler({
      get: async path => { assert.equal(wrote, false); return next.get(path); },
      findAddress: async address => { assert.equal(wrote, false); return [...next.entries()]
        .filter(([path, value]) => path.startsWith('properties/') && value.address === address)
        .map(([path, value]) => ({ ...value, id: path.split('/')[1] })); },
      set: (path, value) => { wrote = true; next.set(path, structuredClone(value)); },
      update: (path, value) => { wrote = true; next.set(path, { ...next.get(path), ...structuredClone(value) }); },
    });
    records = next; return result;
  }, list: async uid => [...records.entries()].filter(([path, value]) => path.startsWith('ownerProperties/') && (!uid || uid === value.ownerUid))
    .map(([path, value]) => ({ ...value, id: path.split('/')[1] })) };
  const state = { failed: false, snapshots: 0 };
  const files = { read: async () => 'TEST_PRIVATE_PHOTO', cleanup: async () => {}, snapshot: async (grant, uploadId) => {
    if (state.failed) throw new Error('TEST offline');
    state.snapshots++;
    return grant.specs.map((spec, index) => ({ ...spec, path: `ownerPropertyPhotos/${grant.propertyId}/${uploadId}/${index}`, generation: '123' }));
  } };
  const service = (uid, token = { phone_number: records.get(`users/${uid}`)?.phone, firebase: { sign_in_provider: 'phone' } }) =>
    createOwnerPropertyService({ auth: uid ? { uid, token } : null, store, files, now: () => clock.value });
  async function saveThrough(last = 4) {
    let value;
    for (let step = 0; step <= last; step++) value = await service('owner').save({ id: value?.id, revision: value?.revision ?? 0,
      operationId: String(step + 1).repeat(32), step, input: steps[step] });
    return value;
  }
  return { service, saveThrough, clock, state, get: path => records.get(path), set: (path, value) => records.set(path, value) };
}
test('owner property saves each step, retries once and publishes only a completed real property', async () => {
  const flow = fixture(); const owner = flow.service('owner');
  const input = { revision: 0, operationId: '1'.repeat(32), step: 0, input: steps[0] };
  const first = await owner.save(input);
  assert.equal(first.revision, 1); assert.equal(flow.get(`properties/${first.id}`), undefined);
  assert.deepEqual(await owner.save(input), first);
  await assert.rejects(owner.save({ ...input, input: { ...steps[0], name: 'changed' } }), { code: 'already-exists' });
  await assert.rejects(owner.save({ id: first.id, revision: 0, step: 1, input: steps[1], operationId: '2'.repeat(32) }), { code: 'aborted' });
  const complete = await flow.saveThrough();
  assert.equal(complete.status, 'property_added');
  assert.equal(flow.get(`properties/${complete.id}`).ownerUid, 'owner');
  assert.equal(flow.get(`properties/${complete.id}`).activeAgreementId, undefined);
  assert.equal(flow.get(`ownerProperties/${complete.id}`).feeOffer, undefined);
  assert.equal((await owner.list()).properties.length, 1);
});
test('owner validation rejects invalid amounts, skipped steps, unknown features, impossible dates and floors', async () => {
  assert.throws(() => validateOwnerPropertyStep(3, { ...steps[3], rentPaise: 1.5 }), { code: 'invalid-argument' });
  assert.throws(() => validateOwnerPropertyStep(3, { ...steps[3], availableFrom: '2026-02-30' }), { code: 'invalid-argument' });
  assert.throws(() => validateOwnerPropertyStep(1, { ...steps[1], floor: 8 }), { code: 'invalid-argument' });
  assert.throws(() => validateOwnerPropertyStep(2, { ...steps[2], features: ['secret feature'] }), { code: 'invalid-argument' });
  const flow = fixture(); const value = await flow.saveThrough(0);
  await assert.rejects(flow.service('owner').save({ id: value.id, revision: value.revision, step: 4,
    operationId: 'f'.repeat(32), input: steps[4] }), { code: 'failed-precondition' });
});
test('only the verified owner accesses private drafts, uploads and reads; admin cannot impersonate an owner', async () => {
  const flow = fixture(); const value = await flow.saveThrough();
  await assert.rejects(flow.service('other').read({ id: value.id }), { code: 'permission-denied' });
  await assert.rejects(flow.service('other').read({ id: value.id, admin: true }), { code: 'permission-denied' });
  await assert.rejects(flow.service('admin').read({ id: value.id }), { code: 'permission-denied' });
  await assert.rejects(flow.service('owner', {}).read({ id: value.id }), { code: 'permission-denied' });
  await assert.rejects(flow.service(null).list(), { code: 'unauthenticated' });
  assert.equal((await flow.service('admin').read({ id: value.id, admin: true })).id, value.id);
  flow.set('users/owner', { roles: ['owner'], phone: '+911111111111', paused: true });
  await assert.rejects(flow.service('owner').list(), { code: 'permission-denied' });
});
test('private photos survive retries, strip object paths and require team photos or received uploads', async () => {
  const flow = fixture(); const value = await flow.saveThrough(3); const owner = flow.service('owner');
  await assert.rejects(owner.save({ id: value.id, revision: value.revision, step: 4, operationId: '5'.repeat(32), input: { teamPhotos: false } }), { code: 'failed-precondition' });
  const grant = await owner.beginPhotos({ id: value.id, revision: value.revision, operationId: 'a'.repeat(32),
    specs: [{ contentType: 'image/jpeg', size: 100, sha256: 'b'.repeat(64) }] });
  flow.state.failed = true;
  await assert.rejects(owner.completePhotos({ uploadId: grant.uploadId }));
  assert.equal(flow.get(`ownerProperties/${value.id}`).revision, value.revision);
  flow.state.failed = false;
  const saved = await owner.completePhotos({ uploadId: grant.uploadId });
  assert.equal(saved.photos.length, 1); assert.equal(saved.photos[0].path, undefined);
  assert.deepEqual(await owner.completePhotos({ uploadId: grant.uploadId }), saved);
  assert.equal(flow.state.snapshots, 1);
  assert.equal((await owner.readPhoto({ id: value.id, index: 0 })).base64, 'TEST_PRIVATE_PHOTO');
});
test('photo completion rejects anonymous missing grants before private reads or file processing', async () => {
  const flow = fixture();
  await assert.rejects(flow.service(null).completePhotos({ uploadId: '0'.repeat(64) }), { code: 'unauthenticated' });
  await assert.rejects(flow.service('owner').completePhotos({ uploadId: '0'.repeat(64) }), { code: 'permission-denied' });
  const property = await flow.saveThrough(3);
  const grant = await flow.service('owner').beginPhotos({ id: property.id, revision: property.revision, operationId: 'a'.repeat(32),
    specs: [{ contentType: 'image/jpeg', size: 100, sha256: 'b'.repeat(64) }] });
  await assert.rejects(flow.service('other').completePhotos({ uploadId: grant.uploadId }), { code: 'permission-denied' });
  assert.equal(flow.state.snapshots, 0);
});
test('blank and name-only properties complete without label collision checks', async () => {
  for (const name of ['', 'rjh']) {
    const flow = fixture();
    flow.set('properties/unrelated', { address: '', ownerUid: 'other' });
    let property;
    for (let step = 0; step < steps.length; step++) {
      property = await flow.service('owner').save({ id: property?.id, revision: property?.revision ?? 0,
        step, operationId: String(step + 1).padStart(32, '0'),
        input: step === 0 ? { ...steps[0], address: '', name } : steps[step] });
    }
    assert.equal(property.status, 'property_added');
    assert.equal(flow.get(`properties/${property.id}`).address, name);
    assert.equal(flow.get(`properties/${property.id}`).name, name);
    assert.equal(property.details.address, '');
  }
});

test('arbitrary labels never permit claiming another account property ID', async () => {
  const flow = fixture();
  const id = 'b'.repeat(64);
  flow.set(`properties/${id}`, { ownerUid: 'other', participantUids: ['other'], address: '' });
  await assert.rejects(flow.service('owner').save({ id, revision: 0, step: 0,
    operationId: 'c'.repeat(32), input: { ...steps[0], address: '', name: 'rjh' } }), { code: 'permission-denied' });
  assert.equal(flow.get(`properties/${id}`).ownerUid, 'other');
});

test('free-text duplicates are allowed while active tenancies stay protected', async () => {
  const flow = fixture(); flow.set('properties/other', { address: steps[0].address, ownerUid: 'other' });
  assert.equal((await flow.saveThrough()).status, 'property_added');
  const safe = fixture(); const value = await safe.saveThrough();
  safe.set(`properties/${value.id}`, { ownerUid: 'owner', activeAgreementId: 'existing' });
  await assert.rejects(safe.service('owner').save({ id: value.id, revision: value.revision, operationId: 'c'.repeat(32), step: 0, input: steps[0] }), { code: 'failed-precondition' });
});
test('real appointment and versioned fee need admin evidence, a completed check, 5–20% and future effective date', async () => {
  const flow = fixture(); const value = await flow.saveThrough(); const owner = flow.service('owner'); const admin = flow.service('admin');
  const check = { id: value.id, revision: value.revision, plan: 'diy', method: 'visit', day: '2026-10-11', slot: '10:00–12:00' };
  await assert.rejects(owner.requestPlan({ ...check, day: '2026-10-10' }), { code: 'invalid-argument' });
  const requested = await owner.requestPlan(check);
  const details = { id: value.id, revision: requested.revision, action: 'confirm', managerName: 'TEST manager',
    managerPhone: '+919999999999', day: '2026-10-11', slot: '10:00–12:00', reference: 'TEST calendar booking' };
  await assert.rejects(owner.recordCheck(details), { code: 'permission-denied' });
  const booked = await admin.recordCheck(details);
  const offer = { id: value.id, revision: booked.revision, action: 'offer_fee', checkCompleted: true,
    reference: 'TEST completed check', feeBps: 800, effectiveFrom: '2026-10-12', notes: 'TEST evidence' };
  await assert.rejects(admin.recordCheck(offer), { code: 'failed-precondition' });
  flow.clock.value = Date.parse('2026-10-11T06:00:00Z');
  await assert.rejects(admin.recordCheck({ ...offer, feeBps: 499 }), { code: 'invalid-argument' });
  await assert.rejects(admin.recordCheck({ ...offer, effectiveFrom: '2026-10-10' }), { code: 'invalid-argument' });
  const offered = await admin.recordCheck(offer);
  assert.equal(offered.status, 'fee_offered'); assert.equal(offered.feeOffer.feeBps, 800);
  assert.equal(offered.feeOffer.status, 'offered'); assert.equal(flow.get(`properties/${value.id}`).activeAgreementId, undefined);
  assert.equal(flow.get(`adminAuditLogs/owner-property-${value.id}-${offered.revision}`).action, 'owner_fee_offered');
});
