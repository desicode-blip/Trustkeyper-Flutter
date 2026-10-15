import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRepairWorkflowService } from '../repair-workflow.js';

const time = Date.parse('2026-10-10T10:00:00+05:30');
const operationId = 'a'.repeat(32);
const issueId = 'test-repair';

test('inspection repair creation binds its agreement on the server and repeats without orphan or duplicate repairs', async () => {
  const flow = fixture();
  const photoPath = 'properties/photo-property/photoChecks/check-1';
  flow.records.set(photoPath, { status: 'needs_repair' });
  flow.records.set('properties/photo-property', { agreementId: 'home' });
  flow.records.get('agreements/home').propertyId = 'photo-property';
  await assert.rejects(flow.service('tenant').fromPhoto({ photoPath }), { code: 'permission-denied' });
  const created = await flow.service('admin').fromPhoto({ photoPath });
  assert.deepEqual(await flow.service('admin').fromPhoto({ photoPath }), created);
  const record = flow.records.get(`issues/${created.issueId}`);
  assert.equal(record.agreementId, 'home');
  assert.deepEqual(record.participantUids, ['broker', 'owner', 'coowner', 'tenant']);
  assert.equal(flow.records.get(photoPath).issueId, created.issueId);
  await assert.rejects(flow.service('admin').fromPhoto({ photoPath: '../private' }), { code: 'invalid-argument' });
  flow.records.set('properties/orphan/photoChecks/check-1', { status: 'pending' });
  flow.records.set('properties/orphan', {});
  await assert.rejects(flow.service('admin').fromPhoto({ photoPath: 'properties/orphan/photoChecks/check-1' }), { code: 'failed-precondition' });
});
function fixture() {
  const records = new Map(Object.entries({
    'users/admin': { roles: ['admin'] }, 'users/owner': { roles: ['owner'] },
    'users/coowner': { roles: ['owner'] }, 'users/tenant': { roles: ['tenant'] },
    'users/broker': { roles: ['broker'], approvalStatus: 'approved' }, 'users/outsider': { roles: ['owner'] },
    'agreements/home': { revision: 2, brokerUid: 'broker', participantUids: ['broker', 'owner', 'coowner', 'tenant'],
      agreementCopy: { mode: 'externally_signed', revision: 2, people: [
        { uid: 'owner', role: 'owner' }, { uid: 'coowner', role: 'owner' }, { uid: 'tenant', role: 'tenant' }] } },
    [`issues/${issueId}`]: { status: 'open', agreementId: 'home', participantUids: ['broker', 'owner', 'coowner', 'tenant'],
      photos: [{ path: 'TEST-before' }] },
  }));
  const store = { timestamp: () => 'SERVER_TIME', transaction: async handler => {
    const writes = [];
    let wrote = false;
    const result = await handler({ get: async path => { assert.equal(wrote, false, 'All transaction reads precede writes'); return structuredClone(records.get(path)); },
      set: (path, value) => { wrote = true; writes.push(() => records.set(path, structuredClone(value))); },
      update: (path, value) => { wrote = true; writes.push(() => records.set(path, { ...records.get(path), ...structuredClone(value) })); },
    });
    writes.forEach(write => write()); return result;
  } };
  let snapshots = 0;
  const files = { snapshot: async () => { snapshots++; return { bill: { path: 'private-bill' }, after: { path: 'private-after' } }; },
    cleanup: async () => {}, read: async file => ({ path: file.path, base64: 'TEST' }) };
  const service = uid => createRepairWorkflowService({ auth: uid ? { uid } : {}, store, files, now: () => time });
  return { records, service, files, snapshots: () => snapshots, issue: () => records.get(`issues/${issueId}`),
    input: extra => ({ issueId, operationId, version: records.get(`issues/${issueId}`).workflowVersion ?? 0, ...extra }) };
}
const quote = { amountPaise: 280000, vendorName: 'TEST Plumbing', vendorPhone: '+919000090000', description: 'Replace the faulty geyser element.' };
async function approved(flow, amountPaise = 280000) {
  await flow.service('admin').quote(flow.input({ ...quote, amountPaise }));
  if (amountPaise > 200000) {
    await flow.service('owner').approve(flow.input({ quoteVersion: 1 }));
    await flow.service('coowner').approve(flow.input({ quoteVersion: 1 }));
  }
}
async function scheduled(flow) {
  await approved(flow);
  await flow.service('admin').schedule(flow.input({ operationId: 'b'.repeat(32), startsAtMs: time, endsAtMs: time + 3600000 }));
}
const completion = { operationId: 'c'.repeat(32), amountPaise: 280000, invoiceNumber: 'TEST-2091',
  payoutDateISO: '2026-11-07', includeBefore: false, visitDone: true };

test('quote, every-owner approval, scheduled visit, immutable bill and tenant confirmation form an audited workflow', async () => {
  const flow = fixture();
  await scheduled(flow);
  assert.equal(flow.issue().status, 'assigned');
  const upload = await flow.service('admin').beginCompletion(flow.input(completion));
  await flow.service('admin').complete({ uploadId: upload.uploadId });
  assert.equal(flow.issue().status, 'resolved');
  assert.equal(flow.issue().completion.amountPaise, 280000);
  assert.equal(flow.records.get(`repairCharges/${issueId}`).status, 'pending_reconciliation');
  assert.equal([...flow.records.keys()].some(path => path.startsWith('payouts/')), false);
  await flow.service('tenant').confirm(flow.input({ outcome: 'working' }));
  assert.equal(flow.issue().status, 'closed');
  assert.equal([...flow.records.keys()].filter(path => path.startsWith(`issues/${issueId}/events/`)).length, 6);
});

test('exactly ₹2000 is auto-approved; above ₹2000 requires all co-owners and rejects tenant/broker approval', async () => {
  for (const amount of [100, 199999, 200000]) {
    const flow = fixture(); await approved(flow, amount); assert.equal(flow.issue().status, 'approved');
  }
  const flow = fixture(); await flow.service('admin').quote(flow.input(quote));
  for (const uid of ['tenant', 'broker', 'outsider']) {
    await assert.rejects(flow.service(uid).approve(flow.input({ quoteVersion: 1 })), { code: 'permission-denied' });
  }
  await flow.service('owner').approve(flow.input({ quoteVersion: 1 }));
  assert.equal(flow.issue().status, 'waiting_owner');
  await assert.rejects(flow.service('admin').schedule(flow.input({ operationId: 'd'.repeat(32), startsAtMs: time + 60000, endsAtMs: time + 3600000 })), { code: 'failed-precondition' });
});

test('a replacement quote resets owner approvals; stale approvals, owners and revisions cannot authorise work', async () => {
  const flow = fixture(); await approved(flow);
  await flow.service('admin').quote(flow.input({ ...quote, operationId: 'b'.repeat(32), amountPaise: 300000 }));
  assert.equal(flow.issue().quote.version, 2); assert.deepEqual(flow.issue().ownerApprovals, {});
  await assert.rejects(flow.service('owner').approve(flow.input({ operationId: 'b'.repeat(32), quoteVersion: 1 })), { code: 'aborted' });
  flow.records.get('agreements/home').revision = 3;
  await assert.rejects(flow.service('owner').approve(flow.input({ operationId: 'c'.repeat(32), quoteVersion: 2 })), { code: 'failed-precondition' });
});

test('mutation retries are idempotent and revision conflicts never overwrite another device', async () => {
  const flow = fixture(); const input = flow.input(quote);
  const first = await flow.service('admin').quote(input);
  assert.deepEqual(await flow.service('admin').quote(input), first);
  assert.equal(flow.issue().quote.version, 1);
  await assert.rejects(flow.service('admin').quote({ ...input, amountPaise: 200000 }), { code: 'aborted' });
  await assert.rejects(flow.service('admin').quote({ ...input, operationId: 'b'.repeat(32) }), { code: 'aborted' });
});

test('anonymous, paused, removed members and non-admins cannot mutate or read another repair', async () => {
  const flow = fixture();
  await assert.rejects(flow.service().read({ issueId }), { code: 'unauthenticated' });
  await assert.rejects(flow.service('outsider').read({ issueId }), { code: 'permission-denied' });
  for (const uid of ['owner', 'tenant', 'broker']) {
    await assert.rejects(flow.service(uid).quote(flow.input(quote)), { code: 'permission-denied' });
  }
  flow.records.get('users/admin').paused = true;
  await assert.rejects(flow.service('admin').quote(flow.input(quote)), { code: 'permission-denied' });
  flow.records.get('agreements/home').participantUids = ['owner'];
  await assert.rejects(flow.service('tenant').read({ issueId }), { code: 'permission-denied' });
});

test('invalid money, vendor, dates, proof and over-budget bills fail before creating charges', async () => {
  const flow = fixture();
  for (const change of [{ amountPaise: 0 }, { amountPaise: 1.5 }, { amountPaise: 100000001 },
    { vendorPhone: 'not-a-phone' }, { vendorName: '' }, { description: 'short' }]) {
    await assert.rejects(flow.service('admin').quote(flow.input({ ...quote, ...change })), { code: 'invalid-argument' });
  }
  await scheduled(flow);
  for (const change of [{ amountPaise: 280001 }, { payoutDateISO: '2026-11-06' }, { payoutDateISO: '2026-02-30' }]) {
    await assert.rejects(flow.service('admin').beginCompletion(flow.input({ ...completion, ...change })));
  }
  flow.issue().photos = [];
  await assert.rejects(flow.service('admin').beginCompletion(flow.input(completion)), { code: 'failed-precondition' });
  assert.equal(flow.records.has(`repairCharges/${issueId}`), false);
});

test('expired upload, failed proof and changed approval during upload never close a repair', async () => {
  for (const scenario of ['expired', 'failed', 'changed']) {
    const flow = fixture(); await scheduled(flow);
    const upload = await flow.service('admin').beginCompletion(flow.input(completion));
    if (scenario === 'expired') flow.records.get(`repairCompletionUploads/${upload.uploadId}`).expiresAtMs = time - 1;
    if (scenario === 'failed') flow.files.snapshot = async () => { throw new Error('upload interrupted'); };
    if (scenario === 'changed') flow.files.snapshot = async () => { flow.issue().workflowVersion++; return {}; };
    await assert.rejects(flow.service('admin').complete({ uploadId: upload.uploadId }));
    assert.equal(flow.issue().status, 'assigned'); assert.equal(flow.records.has(`repairCharges/${issueId}`), false);
  }
});

test('completion retries do not duplicate charges or replace the original evidence', async () => {
  const flow = fixture(); await scheduled(flow);
  const input = flow.input(completion);
  const upload = await flow.service('admin').beginCompletion(input);
  assert.deepEqual(await flow.service('admin').beginCompletion(input), upload);
  await flow.service('admin').complete({ uploadId: upload.uploadId });
  await flow.service('admin').complete({ uploadId: upload.uploadId });
  assert.equal(flow.snapshots(), 1);
  await assert.rejects(flow.service('admin').quote(flow.input({ ...quote, operationId: 'f'.repeat(32) })), { code: 'failed-precondition' });
});

test('tenant rejects a repair with a note; another tenant cannot silently erase that concern', async () => {
  const flow = fixture(); await scheduled(flow);
  const upload = await flow.service('admin').beginCompletion(flow.input(completion));
  await flow.service('admin').complete({ uploadId: upload.uploadId });
  await assert.rejects(flow.service('owner').confirm(flow.input({ operationId: 'e'.repeat(32), outcome: 'working' })), { code: 'permission-denied' });
  await assert.rejects(flow.service('tenant').confirm(flow.input({ outcome: 'not_working', note: 'short' })), { code: 'invalid-argument' });
  await flow.service('tenant').confirm(flow.input({ outcome: 'not_working', note: 'The geyser still does not heat water.' }));
  assert.equal(flow.issue().status, 'needs_attention');
  flow.records.set('users/cotenant', { roles: ['tenant'] });
  flow.records.get('agreements/home').participantUids.push('cotenant');
  flow.records.get('agreements/home').agreementCopy.people.push({ uid: 'cotenant', role: 'tenant' });
  flow.issue().participantUids.push('cotenant');
  await flow.service('cotenant').confirm(flow.input({ operationId: 'e'.repeat(32), outcome: 'working' }));
  assert.equal(flow.issue().status, 'needs_attention');
  assert.equal(flow.issue().tenantConfirmations.tenant.outcome, 'not_working');
});

test('private evidence is read only with current membership, and revocation is rechecked after download', async () => {
  const flow = fixture(); flow.issue().completion = { evidence: { bill: { path: 'private-bill', generation: '1' } } };
  await assert.rejects(flow.service('outsider').readFile({ issueId, slot: 'bill' }), { code: 'permission-denied' });
  flow.files.read = async () => { flow.records.get('users/tenant').paused = true; return { base64: 'TEST' }; };
  await assert.rejects(flow.service('tenant').readFile({ issueId, slot: 'bill' }), { code: 'permission-denied' });
});
