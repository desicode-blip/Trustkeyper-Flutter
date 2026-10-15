import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createAgreementReviewService, reviewSnapshot } from '../agreement-review.js';

function draft() {
  return { schemaVersion: 2, propertyAddress: 'Demo Test Flat 402, Test Towers',
    owners: [{ id: 'owner-1', name: 'Demo Owner', phone: '+919000000001', email: '', rentSharePaise: 0, depositSharePaise: 0 }],
    tenants: [{ id: 'tenant-1', name: 'Demo Tenant', phone: '+919000000002', email: '', rentSharePaise: 2200000, depositSharePaise: 4400000 }],
    monthlyRentPaise: 2200000, monthlyMaintenancePaise: 0, securityDepositPaise: 4400000,
    ownerBrokeragePaise: 1100000, tenantBrokeragePaise: 2200000,
    startDateISO: '2026-10-01T00:00:00.000', endDateISO: '2027-08-31T00:00:00.000',
    rentDueDay: 5, lockInMonths: 6, noticeMonths: 1, status: 'draft', revision: 1,
    brokerUid: 'broker', participantUids: ['broker'] };
}

test('review accepts short flat names and addresses without a formatting requirement', () => {
  for (const address of ['', '   ', 'rjh', '1', '402', 'A', '22/B', 'घर']) {
    assert.equal(reviewSnapshot({ ...draft(), propertyAddress: address }).propertyAddress, address.trim());
  }
});

function fixture() {
  let data = new Map([
    ['users/broker', { roles: ['broker'], approvalStatus: 'approved' }],
    ['users/admin', { roles: ['admin'] }],
    ['users/tenant', { roles: ['tenant'] }],
    ['agreements/test', draft()],
  ]);
  let sequence = 0;
  function approve(revision) {
    const snapshot = reviewSnapshot(data.get('agreements/test'));
    const digest = createHash('sha256').update(JSON.stringify(snapshot)).digest('hex');
    const roundId = createHash('sha256').update(JSON.stringify(['test', revision])).digest('hex');
    data.set(`agreementApprovalRounds/${roundId}`, { revision, digest,
      replies: Object.fromEntries([...snapshot.owners, ...snapshot.tenants].map(party => [party.id, { status: 'agreed', revision, digest }])) });
  }
  approve(1);
  const store = { transaction: async handler => {
    const next = structuredClone(data);
    let written = false;
    const result = await handler({
      get: async path => { assert.equal(written, false, 'Firestore reads must precede writes'); return next.get(path); },
      set: (path, value) => { written = true; next.set(path, structuredClone(value)); },
      update: (path, value) => { written = true; next.set(path, { ...next.get(path), ...structuredClone(value) }); },
    });
    data = next;
    return result;
  } };
  return { approve, get: path => data.get(path), set: (path, value) => data.set(path, value),
    size: () => data.size,
    service: uid => createAgreementReviewService({ store, uid, now: () => 1000, eventId: () => `event-${++sequence}` }) };
}

test('review freezes a non-signable snapshot and atomically records evidence', async () => {
  const flow = fixture();
  assert.deepEqual(await flow.service('broker').submit({ agreementId: 'test', revision: 1 }),
    { agreementId: 'test', revision: 1, status: 'review_requested' });
  assert.equal(flow.get('agreements/test').status, 'review_requested');
  assert.equal(flow.get('agreements/test').reviewSignable, false);
  const review = flow.get('agreements/test/reviews/1');
  assert.equal(review.snapshot.signable, false);
  assert.equal(review.snapshot.templateVersion, 'demo-v1');
  assert.equal(review.digest.length, 64);
  assert.equal(flow.get('adminAuditLogs/event-1').actorUid, 'broker');
  flow.get('agreements/test').owners[0].name = 'Changed original';
  assert.equal(review.snapshot.owners[0].name, 'Demo Owner');
});

test('configured Indian test-phone contacts pass structural validation without creating authentication proof', () => {
  const value = draft();
  value.owners[0].phone = '+911111111111'; value.tenants[0].phone = '+912222222222';
  assert.doesNotThrow(() => reviewSnapshot(value));
});

test('repeated submission returns current status without duplicate audit or snapshots', async () => {
  const flow = fixture();
  await flow.service('broker').submit({ agreementId: 'test', revision: 1 });
  const size = flow.size();
  await flow.service('broker').submit({ agreementId: 'test', revision: 1 });
  assert.equal(flow.size(), size);
});

test('rejects unsigned sessions, other brokers, unapproved brokers and stale revisions', async () => {
  for (const uid of [null, 'tenant', 'another-broker']) {
    const flow = fixture();
    await assert.rejects(flow.service(uid).submit({ agreementId: 'test', revision: 1 }));
    assert.equal(flow.get('agreements/test').status, 'draft');
  }
  for (const changes of [{ approvalStatus: 'pending' }, { paused: true }]) {
    const flow = fixture();
    flow.set('users/broker', { ...flow.get('users/broker'), ...changes });
    await assert.rejects(flow.service('broker').submit({ agreementId: 'test', revision: 1 }), { code: 'permission-denied' });
  }
  await assert.rejects(fixture().service('broker').submit({ agreementId: 'test', revision: 2 }), { code: 'aborted' });
});

test('rejects malformed contracts, money coercion, mismatched shares and impossible dates', () => {
  const changes = [
    { monthlyRentPaise: '2200000' }, { securityDepositPaise: 1.5 },
    { owners: [] }, { monthlyRentPaise: 100 }, { startDateISO: '2026-02-30T00:00:00.000' },
    { noticeMonths: 12 }, { rentDueDay: 4 }, { ownerBrokeragePaise: -1 },
    { tenants: [{ ...draft().tenants[0], id: 'owner-1' }] },
  ];
  for (const change of changes) assert.throws(() => reviewSnapshot({ ...draft(), ...change }));
  assert.doesNotThrow(() => reviewSnapshot({ ...draft(), startDateISO: '2026-01-31T00:00:00.000', endDateISO: '2026-02-27T00:00:00.000', noticeMonths: 1, lockInMonths: 1 }));
});

test('admin review records only permitted transitions; demo signing is always rejected', async () => {
  const flow = fixture();
  const input = { agreementId: 'test', revision: 1 };
  await flow.service('broker').submit(input);
  await assert.rejects(flow.service('admin').record({ ...input, step: 'reviewed' }));
  await assert.rejects(flow.service('broker').record({ ...input, step: 'request_received' }), { code: 'permission-denied' });
  await flow.service('admin').record({ ...input, step: 'request_received' });
  await flow.service('admin').record({ ...input, step: 'reviewed' });
  for (const step of ['signed', 'sent_to_sign', 'stamp_paper', 'printed', 'final_check']) {
    await assert.rejects(flow.service('admin').record({ ...input, step }), { code: 'failed-precondition' });
  }
  await assert.rejects(flow.service('admin').record({ ...input, step: 'request_received' }));
  assert.equal(flow.get('agreements/test').status, 'reviewed');
});

test('corrections require a reason and a newly saved revision before resubmission', async () => {
  const flow = fixture();
  const input = { agreementId: 'test', revision: 1 };
  await flow.service('broker').submit(input);
  await assert.rejects(flow.service('admin').record({ ...input, step: 'return_to_broker', reason: 'x' }), { code: 'invalid-argument' });
  await flow.service('admin').record({ ...input, step: 'return_to_broker', reason: 'Please correct the property address.' });
  assert.equal(flow.get('agreements/test').status, 'draft');
  assert.equal(flow.get('agreements/test').reviewReturnReason, 'Please correct the property address.');
  await assert.rejects(flow.service('broker').submit(input));
  flow.get('agreements/test').revision = 2;
  flow.approve(2);
  await flow.service('broker').submit({ ...input, revision: 2 });
  assert.ok(flow.get('agreements/test/reviews/1'));
  assert.ok(flow.get('agreements/test/reviews/2'));
});

test('missing or altered evidence and paused admins cannot review', async () => {
  for (const tamper of ['evidence', 'admin']) {
    const flow = fixture();
    const input = { agreementId: 'test', revision: 1 };
    await flow.service('broker').submit(input);
    if (tamper === 'evidence') flow.set('agreements/test/reviews/1', { digest: 'wrong' });
    else flow.set('users/admin', { roles: ['admin'], paused: true });
    await assert.rejects(flow.service('admin').record({ ...input, step: 'request_received' }));
    assert.equal(flow.get('agreements/test').status, 'review_requested');
  }
});

test('invalid IDs and linked participants are rejected with no writes', async () => {
  for (const agreementId of ['../test', 'test/path', '', null]) {
    await assert.rejects(fixture().service('broker').submit({ agreementId, revision: 1 }), { code: 'invalid-argument' });
  }
  const flow = fixture();
  flow.get('agreements/test').participantUids.push('tenant');
  await assert.rejects(flow.service('broker').submit({ agreementId: 'test', revision: 1 }));
  assert.equal(flow.size(), 5);
});
