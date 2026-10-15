import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createTenantSetupService } from '../tenant-setup.js';
import { approvalDigest } from '../agreement-approvals.js';
import { reviewSnapshot } from '../agreement-review.js';

function fixture(uid = 'tenant') {
  const records = new Map([
    ['users/tenant', { roles: ['tenant'] }], ['users/admin', { roles: ['admin'] }],
    ['users/stranger', { roles: ['tenant'] }],
    ['agreements/agreement', { revision: 1, status: 'signed', brokerUid: 'broker',
      participantUids: ['tenant', 'other'], propertyAddress: 'TEST home',
      schemaVersion: 2, monthlyRentPaise: 2200000, monthlyMaintenancePaise: 0, securityDepositPaise: 4400000,
      ownerBrokeragePaise: 0, tenantBrokeragePaise: 0, startDateISO: '2026-10-01T00:00:00.000', endDateISO: '2027-08-31T00:00:00.000',
      rentDueDay: 5, lockInMonths: 6, noticeMonths: 1,
      owners: [{ id: 'owner-one', name: 'TEST owner', phone: '+913333333333', email: '', rentSharePaise: 0, depositSharePaise: 0 }],
      tenants: [{ id: 'tenant-one', uid: 'tenant', name: 'TEST tenant', phone: '+911111111111', email: '', rentSharePaise: 1100000, depositSharePaise: 2200000 },
        { id: 'tenant-two', uid: 'other', name: 'TEST flatmate', phone: '+912222222222', email: '', rentSharePaise: 1100000, depositSharePaise: 2200000 }] }],
  ]);
  const store = { transaction: async handler => handler({
    get: async path => structuredClone(records.get(path)),
    set: (path, value) => records.set(path, structuredClone(value)),
    update: (path, value) => records.set(path, { ...records.get(path), ...structuredClone(value) }),
  }), pending: async () => [...records].filter(([path, value]) => path.startsWith('tenantSetups/') && value.request?.status === 'pending')
    .map(([path, value]) => ({ id: path.split('/')[1], ...value })) };
  const service = actor => createTenantSetupService({ auth: actor ? { uid: actor } : null, store, now: () => 100 });
  return { records, flow: service(uid), admin: service('admin'), service };
}
const input = { agreementId: 'agreement', revision: 1 };

test('tenant confirms the actual home, flatmates and exact shares; repeat is idempotent and terms unchanged', async () => {
  const { flow, records } = fixture(); const original = structuredClone(records.get('agreements/agreement'));
  const details = await flow.read(input);
  assert.equal(details.property, 'TEST home'); assert.equal(details.rentSharePaise, 1100000);
  assert.equal(details.tenants.filter(tenant => tenant.you).length, 1);
  await assert.rejects(flow.record({ ...input, action: 'complete' }), { code: 'failed-precondition' });
  await flow.record({ ...input, action: 'home' }); await flow.record({ ...input, action: 'flatmates' });
  assert.equal((await flow.record({ ...input, action: 'complete' })).complete, true);
  assert.equal((await flow.record({ ...input, action: 'complete' })).complete, true);
  assert.deepEqual(records.get('agreements/agreement'), original);
});
test('anonymous, unlinked, paused, wrong role and ambiguous parties cannot read or write', async () => {
  const fixtureData = fixture();
  for (const actor of [null, 'stranger', 'admin']) await assert.rejects(fixtureData.service(actor).read(input));
  fixtureData.records.get('users/tenant').paused = true;
  await assert.rejects(fixtureData.flow.record({ ...input, action: 'home' }), { code: 'permission-denied' });
  fixtureData.records.get('users/tenant').paused = false;
  fixtureData.records.get('agreements/agreement').tenants[1].uid = 'tenant';
  await assert.rejects(fixtureData.flow.read(input), { code: 'permission-denied' });
});
test('stale revisions, inconsistent totals and cancelled agreements cannot be confirmed', async () => {
  const { flow, records } = fixture();
  await assert.rejects(flow.record({ ...input, revision: 9, action: 'home' }), { code: 'aborted' });
  records.get('agreements/agreement').monthlyRentPaise = 1;
  await assert.rejects(flow.read(input), { code: 'failed-precondition' });
  records.get('agreements/agreement').status = 'cancelled';
  await assert.rejects(flow.read(input), { code: 'failed-precondition' });
});
test('share request validates exact paise, never edits a signed share, persists queue and cannot be overwritten', async () => {
  const { flow, records, admin } = fixture();
  await flow.record({ ...input, action: 'home' }); await flow.record({ ...input, action: 'flatmates' });
  for (const amount of [-1, 0, 1.5, 2200001, 1100000, NaN]) {
    await assert.rejects(flow.record({ ...input, action: 'request', kind: 'share', rentSharePaise: amount }), { code: 'invalid-argument' });
  }
  const result = await flow.record({ ...input, action: 'request', kind: 'share', rentSharePaise: 1200001 });
  assert.equal(result.pending, undefined); assert.equal(result.request.status, 'pending');
  assert.equal(records.get('agreements/agreement').tenants[0].rentSharePaise, 1100000);
  assert.equal((await admin.list()).requests.length, 1);
  await assert.rejects(flow.list(), { code: 'permission-denied' });
  await assert.rejects(flow.record({ ...input, action: 'complete' }), { code: 'failed-precondition' });
});
test('team resolution requires a newer externally signed matching revision, never a client asserted approval', async () => {
  const { flow, admin, records } = fixture();
  await flow.record({ ...input, action: 'home' }); await flow.record({ ...input, action: 'flatmates' });
  await flow.record({ ...input, action: 'request', kind: 'share', rentSharePaise: 1200000 });
  const request = { ...input, tenantUid: 'tenant' };
  await assert.rejects(flow.resolve(request), { code: 'permission-denied' });
  await assert.rejects(admin.resolve(request), { code: 'failed-precondition' });
  const agreement = records.get('agreements/agreement');
  agreement.revision = 2; agreement.status = 'signed_copy_received';
  agreement.agreementCopy = { revision: 2, mode: 'externally_signed', people: [{ id: 'tenant-one', role: 'tenant', uid: 'tenant', phone: '+911111111111' }] };
  await assert.rejects(admin.resolve(request), { code: 'failed-precondition' });
  agreement.tenants[0].rentSharePaise = 1200000; agreement.tenants[1].rentSharePaise = 1000000;
  agreement.agreementCopy.digest = approvalDigest(reviewSnapshot(agreement));
  assert.equal((await admin.resolve(request)).resolved, true);
  assert.equal((await admin.resolve(request)).resolved, true);
  assert.equal((await admin.list()).requests.length, 0);
  const revised = await flow.read(input); assert.equal(revised.complete, false); assert.equal(revised.rentSharePaise, 1200000);
});
test('wrong-home requests do not unlink a user; team resolution needs corrected signed membership', async () => {
  const { flow, admin, records } = fixture();
  await flow.record({ ...input, action: 'request', kind: 'home', note: 'TEST wrong home' });
  assert.equal(records.get('agreements/agreement').participantUids.includes('tenant'), true);
  const agreement = records.get('agreements/agreement');
  agreement.revision = 2; agreement.status = 'signed_copy_received'; agreement.agreementCopy = { revision: 2, mode: 'externally_signed', people: [{ id: 'tenant-one', role: 'tenant', uid: 'tenant', phone: '+911111111111' }] };
  await assert.rejects(admin.resolve({ ...input, tenantUid: 'tenant' }));
  agreement.participantUids = ['other']; agreement.tenants = agreement.tenants.filter(party => party.uid !== 'tenant'); agreement.agreementCopy.people = [];
  agreement.monthlyRentPaise = 1100000; agreement.securityDepositPaise = 2200000;
  agreement.agreementCopy.digest = approvalDigest(reviewSnapshot(agreement));
  assert.equal((await admin.resolve({ ...input, tenantUid: 'tenant' })).resolved, true);
  await assert.rejects(flow.read(input), { code: 'permission-denied' });
});
