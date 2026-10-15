import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAgreementRenewalService } from '../agreement-renewals.js';
import { reviewSnapshot } from '../agreement-review.js';
import { approvalDigest } from '../agreement-approvals.js';

function fixture() {
  const owner = { id: 'owner-1', name: 'TEST Owner', phone: '+911111111111', email: '', rentSharePaise: 0, depositSharePaise: 0 };
  const tenant = { id: 'tenant-1', name: 'TEST Tenant', phone: '+912222222222', email: '', rentSharePaise: 2200000, depositSharePaise: 4400000 };
  const source = { schemaVersion: 2, propertyId: 'home', propertyAddress: 'TEST 402, Test Towers',
    owners: [owner], tenants: [tenant], monthlyRentPaise: 2200000, monthlyMaintenancePaise: 100000,
    securityDepositPaise: 4400000, ownerBrokeragePaise: 0, tenantBrokeragePaise: 2200000,
    startDateISO: '2025-11-01T00:00:00.000', endDateISO: '2026-09-30T00:00:00.000',
    rentDueDay: 5, lockInMonths: 6, noticeMonths: 1, status: 'active', revision: 3,
    brokerUid: 'broker', participantUids: ['broker', 'owner', 'tenant'],
    rentPaid: true, reviewDigest: 'SOURCE REVIEW MUST NOT CARRY', photoSlots: { private: 'source-evidence' } };
  const digest = approvalDigest(reviewSnapshot(source));
  source.agreementCopy = { mode: 'externally_signed', agreementId: 'source', revision: 3, digest,
    uploadId: 'original', file: { generation: '123', sha256: 'a'.repeat(64) } };
  let records = new Map([
    ['users/broker', { roles: ['broker'], approvalStatus: 'approved' }],
    ['users/other', { roles: ['broker'], approvalStatus: 'approved' }],
    ['users/owner', { roles: ['owner'] }],
    ['agreements/source', source],
    ['properties/home', { brokerUid: 'broker', participantUids: ['broker', 'owner', 'tenant'], activeAgreementId: 'source' }],
  ]);
  const store = { timestamp: () => new Date(1000), transaction: async handler => {
    const next = structuredClone(records);
    let written = false;
    const result = await handler({
      get: async path => { assert.equal(written, false); return next.get(path); },
      set: (path, data) => { written = true; next.set(path, structuredClone(data)); },
      update: (path, data) => { written = true; next.set(path, { ...next.get(path), ...structuredClone(data) }); },
    });
    records = next;
    return result;
  } };
  return { get: path => records.get(path), set: (path, value) => records.set(path, value), size: () => records.size,
    input: { sourceAgreementId: 'source', revision: 3, digest, operationId: 'b'.repeat(32) },
    service: uid => createAgreementRenewalService({ store, auth: uid ? { uid } : null, now: () => 1000 }) };
}

test('renewal clones only reviewed terms into a new private unsigned draft with calendar dates and audit', async () => {
  const flow = fixture();
  const original = structuredClone(flow.get('agreements/source'));
  const result = await flow.service('broker').create(flow.input);
  const draft = flow.get(`agreements/${result.agreementId}`);
  assert.equal(draft.startDateISO, '2026-10-01T00:00:00.000');
  assert.equal(draft.endDateISO, '2027-08-31T00:00:00.000');
  assert.equal(draft.renewalSourceId, 'source');
  assert.equal(draft.renewalSourceDigest, flow.input.digest);
  assert.equal(draft.revision, 1);
  assert.deepEqual(draft.participantUids, ['broker']);
  assert.deepEqual(draft.tenants, original.tenants);
  for (const field of ['agreementCopy', 'reviewDigest', 'rentPaid', 'photoSlots', 'activeRenewalId']) assert.equal(draft[field], undefined);
  assert.equal(flow.get('agreements/source').status, 'active');
  assert.equal(flow.get('agreements/source').agreementCopy.file.generation, '123');
  assert.equal(flow.get('properties/home').activeAgreementId, 'source');
  assert.equal(flow.get(`adminAuditLogs/renewal-${result.agreementId}`).action, 'renewal_draft_created');
  assert.doesNotThrow(() => reviewSnapshot(draft));
});

test('same operation and another device resume the same renewal without duplicate documents', async () => {
  const flow = fixture();
  const first = await flow.service('broker').create(flow.input);
  const size = flow.size();
  for (const operationId of [flow.input.operationId, 'c'.repeat(32)]) {
    const replay = await flow.service('broker').create({ ...flow.input, operationId });
    assert.equal(replay.agreementId, first.agreementId);
    assert.equal(replay.resumed, true);
    assert.equal(flow.size(), size);
  }
});

test('renewal clamps month-end and leap-year dates without fractional paise', async () => {
  const flow = fixture();
  flow.get('agreements/source').endDateISO = '2026-01-30T00:00:00.000';
  flow.get('agreements/source').startDateISO = '2025-02-01T00:00:00.000';
  const digest = approvalDigest(reviewSnapshot(flow.get('agreements/source')));
  flow.get('agreements/source').agreementCopy.digest = digest;
  const result = await flow.service('broker').create({ ...flow.input, digest });
  assert.equal(flow.get(`agreements/${result.agreementId}`).startDateISO, '2026-01-31T00:00:00.000');
  assert.equal(flow.get(`agreements/${result.agreementId}`).endDateISO, '2026-12-30T00:00:00.000');
  assert.equal(flow.get(`agreements/${result.agreementId}`).monthlyRentPaise, 2200000);
});

test('missing, unrelated, owner and anonymous identities cannot create renewal drafts', async () => {
  for (const uid of [null, 'other', 'owner', 'missing']) {
    const flow = fixture();
    await assert.rejects(flow.service(uid).create(flow.input));
    assert.equal(flow.size(), 5);
  }
  for (const change of [{ paused: true }, { approvalStatus: 'pending' }]) {
    const flow = fixture(); Object.assign(flow.get('users/broker'), change);
    await assert.rejects(flow.service('broker').create(flow.input), { code: 'permission-denied' });
    assert.equal(flow.size(), 5);
  }
});

test('demo, stale, changed or incomplete signed originals cannot be renewed', async () => {
  const alterations = [
    source => { source.status = 'draft'; }, source => { source.agreementCopy.mode = 'demo'; },
    source => { source.agreementCopy.digest = 'f'.repeat(64); }, source => { source.agreementCopy.revision = 2; },
    source => { source.agreementCopy.agreementId = 'another'; }, source => { delete source.agreementCopy.file.generation; },
    source => { source.monthlyRentPaise += 1; }, source => { source.revision += 1; },
    source => { source.startDateISO = '2025-02-30T00:00:00.000'; },
  ];
  for (const alter of alterations) {
    const flow = fixture(); alter(flow.get('agreements/source'));
    await assert.rejects(flow.service('broker').create(flow.input));
    assert.equal(flow.size(), 5);
  }
});

test('changed home ownership or a different active agreement rejects renewal', async () => {
  for (const change of [{ brokerUid: 'other' }, { activeAgreementId: 'another' }, { participantUids: ['owner'] }]) {
    const flow = fixture(); Object.assign(flow.get('properties/home'), change);
    await assert.rejects(flow.service('broker').create(flow.input));
    assert.equal(flow.size(), 5);
  }
});

test('existing sent renewal returns progress but a completed renewal cannot be cloned again', async () => {
  const flow = fixture(); const result = await flow.service('broker').create(flow.input);
  flow.get(`agreements/${result.agreementId}`).status = 'under_review';
  assert.equal((await flow.service('broker').create(flow.input)).status, 'under_review');
  flow.get(`agreements/${result.agreementId}`).status = 'signed_copy_received';
  await assert.rejects(flow.service('broker').create(flow.input), { code: 'failed-precondition' });
});

test('corrupt renewal pointer never creates a second draft or overwrites another broker', async () => {
  const flow = fixture(); flow.get('agreements/source').activeRenewalId = 'missing';
  await assert.rejects(flow.service('broker').create(flow.input));
  assert.equal(flow.size(), 5);
});

test('malformed operations, IDs, digests and revisions have no side effects', async () => {
  for (const input of [{ sourceAgreementId: '../source' }, { revision: 0 }, { revision: '3' },
    { digest: 'wrong' }, { operationId: 'not-a-replay-key' }]) {
    const flow = fixture();
    await assert.rejects(flow.service('broker').create({ ...flow.input, ...input }), { code: 'invalid-argument' });
    assert.equal(flow.size(), 5);
  }
});
