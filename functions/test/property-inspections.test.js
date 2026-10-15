import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createInspectionService } from '../property-inspections.js';
import { moveInPlan } from '../move-in-plan.js';

const time = Date.parse('2026-10-10T12:00:00+05:30');
function fixture() {
  const records = new Map(Object.entries({
    'users/broker': { roles: ['broker'], approvalStatus: 'approved', displayName: 'Test Broker' },
    'users/owner': { roles: ['owner'], displayName: 'Test Owner' },
    'users/tenant': { roles: ['tenant'] }, 'users/outsider': { roles: ['tenant'] },
    'users/admin': { roles: ['admin'] },
    'properties/flat': { brokerUid: 'broker', address: 'Test Property', agreementId: 'home', participantUids: ['outsider'] },
    'agreements/home': { propertyId: 'flat', revision: 1, participantUids: ['broker', 'owner', 'tenant'],
      agreementCopy: { mode: 'externally_signed', revision: 1, people: [{ uid: 'owner', role: 'owner' }, { uid: 'tenant', role: 'tenant' }] } },
  }));
  const store = { timestamp: () => 'SERVER', transaction: async handler => {
    let wrote = false;
    const writes = [];
    const result = await handler({
      get: async path => { assert.equal(wrote, false); return structuredClone(records.get(path)); },
      list: async path => { assert.equal(wrote, false); return [...records].filter(([key]) => key.startsWith(`${path}/`))
        .map(([key, value]) => ({ ...structuredClone(value), id: key.split('/').at(-1) })); },
      set: (path, value) => { wrote = true; writes.push(() => records.set(path, structuredClone(value))); },
      update: (path, value) => { wrote = true; writes.push(() => records.set(path, { ...records.get(path), ...structuredClone(value) })); },
    });
    writes.forEach(write => write()); return result;
  } };
  let currentTime = time;
  const files = { snapshot: async (uid, id) => ({ path: `inspectionPhotos/${id}/photo`, generation: '1', size: 10, source: uid }),
    read: async () => ({ size: 10, base64: 'TEST' }), cleanup: async () => {} };
  const service = uid => createInspectionService({ auth: uid ? { uid } : {}, store, files, now: () => currentTime });
  return { records, service, files, advance: () => { currentTime += 16 * 60 * 1000; } };
}
const input = { propertyId: 'flat', agreementId: 'home', role: 'broker', room: 'Kitchen', title: 'Sink tap',
  note: 'A small leak under the sink.', source: 'camera', operationId: 'a'.repeat(32) };

test('camera upload, private snapshot, timeline and versioned admin review are authoritative and idempotent', async () => {
  const flow = fixture();
  const grant = await flow.service('broker').begin(input);
  assert.equal(grant.actorName, 'Test Broker'); assert.equal(grant.startedAtMs, time);
  assert.equal((await flow.service('broker').begin(input)).checkId, grant.checkId);
  assert.equal((await flow.service('broker').submit(grant)).submitted, true);
  await flow.service('broker').submit(grant);
  const list = await flow.service('tenant').list({ propertyId: 'flat' });
  assert.equal(list.checks.length, 1); assert.equal(list.checks[0].receivedAtMs, time);
  assert.equal(list.checks[0].status, 'submitted');
  assert.equal((await flow.service('owner').readPhoto({ propertyId: 'flat', checkId: grant.checkId })).base64, 'TEST');
  const review = { propertyId: 'flat', checkId: grant.checkId, version: 1, operationId: 'b'.repeat(32), status: 'approved' };
  await flow.service('admin').review(review); await flow.service('admin').review(review);
  assert.equal((await flow.service('broker').list({ propertyId: 'flat' })).checks[0].status, 'approved');
  assert.equal([...flow.records.keys()].filter(path => path.startsWith('adminAuditLogs/')).length, 1);
  assert.equal([...flow.records.keys()].some(path => path.startsWith('payouts/') || path.startsWith('payments/')), false);
});

test('forged property participant arrays and self-declared customer roles cannot access photos', async () => {
  const flow = fixture(); const grant = await flow.service('broker').begin(input); await flow.service('broker').submit(grant);
  for (const operation of ['list', 'readPhoto']) {
    await assert.rejects(flow.service('outsider')[operation]({ propertyId: 'flat', checkId: grant.checkId }), { code: 'permission-denied' });
  }
  await assert.rejects(flow.service('tenant').begin(input), { code: 'permission-denied' });
  await assert.rejects(flow.service('broker').begin({ ...input, role: 'admin' }), { code: 'permission-denied' });
  await assert.rejects(flow.service(null).list({ propertyId: 'flat' }), { code: 'unauthenticated' });
});

test('a multi-role account captures under its selected linked role without changing another device session', async () => {
  const flow = fixture();
  flow.records.get('users/broker').roles.push('owner');
  flow.records.get('agreements/home').agreementCopy.people.push({ uid: 'broker', role: 'owner' });
  const listed = await flow.service('broker').list({ propertyId: 'flat', agreementId: 'home', role: 'owner' });
  assert.equal(listed.actorRole, 'owner');
  assert.equal((await flow.service('broker').begin({ ...input, role: 'owner' })).actorRole, 'owner');
  assert.equal((await flow.service('broker').list({ propertyId: 'flat', role: 'broker' })).actorRole, 'broker');
  assert.equal(flow.records.get('users/broker').activeRole, undefined);
});

test('owners and tenants are bound to the current external original, property and revision', async () => {
  const flow = fixture();
  assert.equal((await flow.service('owner').begin({ ...input, role: 'owner' })).actorRole, 'owner');
  flow.records.get('agreements/home').revision = 2;
  await assert.rejects(flow.service('owner').list({ propertyId: 'flat' }), { code: 'permission-denied' });
  await assert.rejects(flow.service('broker').begin({ ...input, agreementId: 'other-home' }), { code: 'permission-denied' });
});

test('an explicitly selected linked agreement works without an unmaintained property agreement pointer', async () => {
  const flow = fixture(); delete flow.records.get('properties/flat').agreementId;
  assert.equal((await flow.service('tenant').list({ propertyId: 'flat', agreementId: 'home' })).canCapture, true);
  const grant = await flow.service('tenant').begin({ ...input, role: 'tenant' });
  await flow.service('tenant').submit(grant);
  assert.equal((await flow.service('owner').readPhoto({ propertyId: 'flat', checkId: grant.checkId })).size, 10);
});

test('upload ownership, expiry, payload binding, camera-only source and item limits are enforced', async () => {
  const flow = fixture(); const grant = await flow.service('broker').begin(input);
  await assert.rejects(flow.service('owner').submit(grant), { code: 'permission-denied' });
  await assert.rejects(flow.service('broker').begin({ ...input, title: 'Other item' }), { code: 'aborted' });
  for (const invalid of [{ source: 'gallery' }, { title: 'x' }, { room: 'invented' }, { operationId: 'unsafe/path' }, { note: 'x'.repeat(1001) }]) {
    await assert.rejects(flow.service('broker').begin({ ...input, ...invalid }), { code: 'invalid-argument' });
  }
  flow.advance();
  await assert.rejects(flow.service('broker').submit(grant), { code: 'failed-precondition' });
});

test('retry IDs cannot reuse a photo grant under a different linked agreement', async () => {
  const flow = fixture();
  await flow.service('broker').begin(input);
  flow.records.set('agreements/other-home', structuredClone(flow.records.get('agreements/home')));
  await assert.rejects(flow.service('broker').begin({ ...input, agreementId: 'other-home' }), { code: 'aborted' });
  assert.equal((await flow.service('broker').begin(input)).submitted, false);
});

test('official move-in photos require a confirmed room layout and atomically update the item index without releasing keys', async () => {
  const flow = fixture();
  flow.records.get('agreements/home').propertyDetails = { rooms: '2 BHK' };
  const item = moveInPlan(flow.records.get('agreements/home'))[0].items[0];
  const request = { ...input, room: 'Living room', title: item.title, itemId: item.id, purpose: 'move_in' };
  await assert.rejects(flow.service('broker').begin(request), { code: 'failed-precondition' });
  flow.records.set('tenancies/home', { version: 1, phase: 'preparing', revision: 1, digest: undefined,
    roomConfiguration: { bedrooms: 2, washrooms: 2, balcony: true }, photoSlots: {} });
  await assert.rejects(flow.service('tenant').begin({ ...request, role: 'tenant' }), { code: 'permission-denied' });
  const grant = await flow.service('broker').begin(request);
  await flow.service('broker').submit(grant); await flow.service('broker').submit(grant);
  assert.equal(flow.records.get('tenancies/home').photoSlots[`move_in:${item.id}`], grant.checkId);
  assert.equal(flow.records.get('tenancies/home').version, 2);
  assert.equal(flow.records.get('tenancies/home').phase, 'preparing');
  flow.records.get('tenancies/home').phase = 'active';
  await assert.rejects(flow.service('broker').begin({ ...request, operationId: 'b'.repeat(32) }), { code: 'failed-precondition' });
});

test('official meter and room evidence cannot be published after the handover finishes during storage IO', async () => {
  const flow = fixture();
  flow.records.set('tenancies/home', { version: 1, phase: 'preparing', revision: 1,
    roomConfiguration: { bedrooms: 2, washrooms: 2, balcony: true }, photoSlots: {} });
  const grant = await flow.service('broker').begin({ ...input, room: 'Fixtures & fittings', itemId: 'electricity', purpose: 'move_in_meter' });
  flow.files.snapshot = async () => { flow.records.get('tenancies/home').phase = 'active'; return { generation: '1' }; };
  await assert.rejects(flow.service('broker').submit(grant), { code: 'failed-precondition' });
  assert.deepEqual(flow.records.get('tenancies/home').photoSlots, {});
});

test('role revocation during snapshotting prevents publication; paused users cannot see private history', async () => {
  const flow = fixture(); const grant = await flow.service('tenant').begin({ ...input, role: 'tenant' });
  flow.files.snapshot = async () => { flow.records.get('agreements/home').participantUids = ['broker', 'owner']; return { generation: '1' }; };
  await assert.rejects(flow.service('tenant').submit(grant), { code: 'permission-denied' });
  assert.equal([...flow.records.keys()].some(path => path.includes('/photoChecks/')), false);
  flow.records.get('users/broker').paused = true;
  await assert.rejects(flow.service('broker').list({ propertyId: 'flat' }), { code: 'permission-denied' });
});

test('admin review requires actual private evidence, current version and an explanation for repair flags', async () => {
  const flow = fixture(); const grant = await flow.service('broker').begin(input); await flow.service('broker').submit(grant);
  const review = { propertyId: 'flat', checkId: grant.checkId, version: 1, operationId: 'b'.repeat(32), status: 'flagged', note: 'The pipe appears cracked.' };
  await assert.rejects(flow.service('owner').review(review), { code: 'permission-denied' });
  await assert.rejects(flow.service('admin').review({ ...review, note: 'x' }), { code: 'invalid-argument' });
  await flow.service('admin').review(review);
  await assert.rejects(flow.service('admin').review({ ...review, operationId: 'c'.repeat(32), status: 'approved' }), { code: 'aborted' });
  await assert.rejects(flow.service('admin').review({ ...review, status: 'approved' }), { code: 'aborted' });
});

test('a removed participant cannot receive a download after storage returns; old tenant checks stay private', async () => {
  const flow = fixture(); const grant = await flow.service('broker').begin(input); await flow.service('broker').submit(grant);
  flow.files.read = async () => { flow.records.get('agreements/home').participantUids = ['broker', 'owner']; return { base64: 'PRIVATE' }; };
  await assert.rejects(flow.service('tenant').readPhoto({ propertyId: 'flat', checkId: grant.checkId }), { code: 'permission-denied' });
  flow.records.set('properties/flat/photoChecks/old', { agreementId: 'previous-home' });
  assert.equal((await flow.service('owner').list({ propertyId: 'flat' })).checks.length, 1);
});
