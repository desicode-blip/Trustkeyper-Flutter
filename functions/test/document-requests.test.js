import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { createDocumentRequestService } from '../document-requests.js';
import { documentSubmittedUpdate } from '../broker-updates.js';

const input = { draftId: 'test', revision: 1, partyId: 'owner-1', type: 'aadhaar', operationId: 'first' };
const broker = { uid: 'broker', token: { firebase: { sign_in_provider: 'phone' }, phone_number: '+919999999999' } };
const owner = { uid: 'owner', token: { firebase: { sign_in_provider: 'phone' }, phone_number: '+911111111111' } };

test('sharing persists the chosen channel, broker-only confirmation and resend clock', async () => {
  const flow = fixture();
  const link = await flow.service(broker).create(input);
  for (const channel of ['WhatsApp', 'SMS', 'Email']) {
    flow.advance(1000);
    await flow.service(broker).record({ ...link, action: 'shared', channel });
    const record = flow.get(`brokerDocumentRequests/${link.requestId}`);
    assert.equal(record.channel, channel);
    assert.equal(record.sharedAtMs, 1000 + record.shareCount * 1000);
    assert.equal(record.delivery, 'broker_reported_not_provider_confirmed');
  }
  await assert.rejects(flow.service(owner).record({ ...link, action: 'shared', channel: 'SMS' }),
    { code: 'permission-denied' });
  await assert.rejects(flow.service(broker).record({ ...link, action: 'shared', channel: 'pretend' }),
    { code: 'invalid-argument' });
});

test('broker takeover closes one bundle paper, cancels racing uploads and preserves other requests', async () => {
  const flow = fixture();
  const link = await flow.service(broker).create({ ...input, type: 'all' });
  const before = await flow.service(owner).begin(link);
  await flow.service(broker).record({ ...link, action: 'paper_taken_over', paper: 'pan' });
  await assert.rejects(flow.service(owner).complete({ ...link, uploadId: before.uploadId }));
  const invitation = await flow.service(owner).read(link);
  assert.deepEqual(invitation.slots, ['aadhaarFront', 'aadhaarBack', 'bankProof']);
  const grant = await flow.service(owner).begin(link);
  assert.deepEqual(grant.slots, invitation.slots);
  flow.snapshot(Object.fromEntries(grant.slots.map(kind => [kind, { path: kind }])));
  const received = await flow.service(owner).complete({ ...link, uploadId: grant.uploadId });
  assert.equal(received.status, 'added');
  assert.equal(received.submission.files.pan, undefined);
  assert.equal(flow.notices().length, 1);
});

test('deleting a received bundle paper keeps immutable files and other uploaded papers', async () => {
  const flow = fixture();
  const link = await flow.service(broker).create({ ...input, type: 'all' });
  const grant = await flow.service(owner).begin(link);
  flow.snapshot(Object.fromEntries(grant.slots.map(kind => [kind, { path: kind }])));
  await flow.service(owner).complete({ ...link, uploadId: grant.uploadId });
  const saved = structuredClone(flow.get(`brokerDocumentRequests/${link.requestId}`).submission);
  await flow.service(broker).record({ ...link, action: 'paper_deleted', paper: 'aadhaar' });
  const result = await flow.service(owner).read(link);
  assert.deepEqual(result.slots, ['pan', 'bankProof']);
  assert.equal(result.status, 'added');
  assert.deepEqual(result.submission, saved);
  await assert.rejects(flow.service(owner).begin(link));
  await flow.service(broker).record({ ...link, action: 'paper_deleted', paper: 'pan' });
  await flow.service(broker).record({ ...link, action: 'paper_deleted', paper: 'bank' });
  await assert.rejects(flow.service(owner).read(link));
});

test('takeover cancels a finalizing grant without blocking the remaining bundle papers', async () => {
  const flow = fixture();
  const link = await flow.service(broker).create({ ...input, type: 'all' });
  const oldGrant = await flow.service(owner).begin(link);
  const path = `brokerDocumentRequests/${link.requestId}`;
  flow.set(path, { ...flow.get(path), status: 'finalizing' });
  await flow.service(broker).record({ ...link, action: 'paper_taken_over', paper: 'pan' });
  assert.equal(flow.get(path).status, 'seen');
  const nextGrant = await flow.service(owner).begin(link);
  assert.notEqual(nextGrant.uploadId, oldGrant.uploadId);
  assert.deepEqual(nextGrant.slots, ['aadhaarFront', 'aadhaarBack', 'bankProof']);
  await assert.rejects(flow.service(owner).complete({ ...link, uploadId: oldGrant.uploadId }));
});

test('paper closure rejects wrong brokers, unrelated scopes and changed request versions', async () => {
  const flow = fixture();
  const link = await flow.service(broker).create(input);
  await assert.rejects(flow.service(owner).record({ ...link, action: 'paper_deleted', paper: 'aadhaar' }),
    { code: 'permission-denied' });
  await assert.rejects(flow.service(broker).record({ ...link, action: 'paper_deleted', paper: 'pan' }),
    { code: 'invalid-argument' });
  await flow.service(broker).create({ ...input, operationId: 'new' });
  await assert.rejects(flow.service(broker).record({ requestId: link.requestId, version: link.version, action: 'paper_deleted', paper: 'aadhaar' }),
    { code: 'aborted' });
});

test('document invitations accept blank labels and arbitrary property names', async () => {
  for (const address of ['', 'rjh', '1', '402', 'A', '22/B', 'घर']) {
    const flow = fixture();
    const path = 'users/broker/draftProgress/test';
    const progress = flow.get(path);
    flow.set(path, { ...progress, draft: { ...progress.draft, propertyAddress: address } });
    const link = await flow.service(broker).create(input);
    assert.equal((await flow.service(null).read(link)).address, address);
  }
  const flow = fixture();
  const path = 'users/broker/draftProgress/test';
  const progress = flow.get(path);
  flow.set(path, { ...progress, draft: { ...progress.draft, propertyAddress: '   ' } });
  const link = await flow.service(broker).create(input);
  assert.equal((await flow.service(null).read(link)).address, '');
  assert.equal(flow.notices().length, 0);
});
function fixture() {
  let clock = 1000;
  let sequence = 0;
  let data = new Map([
    ['users/broker', { roles: ['broker'], approvalStatus: 'approved', displayName: 'Test Broker' }],
    ['users/broker/draftProgress/test', { brokerUid: 'broker', draft: { revision: 0, propertyAddress: 'TEST ONLY Property 101',
      owners: [{ id: 'owner-1', name: 'Test Owner', phone: '+911111111111', email: '' }],
      tenants: [{ id: 'tenant-1', name: 'Test Tenant', phone: '+912222222222', email: '' }] } }],
  ]);
  let snapshot = { aadhaarFront: { path: 'front' }, aadhaarBack: { path: 'back' } };
  let failed = false;
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
  return { get: path => data.get(path), set: (path, value) => data.set(path, value),
    notices: () => [...data].filter(([path]) => path.startsWith('users/broker/updates/')).map(([, value]) => value),
    advance: delta => clock += delta, snapshot: value => snapshot = value, fail: value => failed = value,
    service: auth => createDocumentRequestService({ store, auth, now: () => clock, nonce: () => randomBytes(32).toString('base64url'),
      eventId: () => `event-${++sequence}`, files: { snapshot: async () => { if (failed) throw new Error('fixture unavailable'); return snapshot; } } }),
  };
}

test('optional tenant LinkedIn is phone-protected, URL-normalized and sends a broker update', async () => {
  const flow = fixture();
  const tenant = { uid: 'tenant', token: { firebase: { sign_in_provider: 'phone' }, phone_number: '+912222222222' } };
  const created = await flow.service(broker).create({ ...input, partyId: 'tenant-1', type: 'linkedin' });
  await assert.rejects(flow.service(owner).begin({ ...created, linkedInDetails: { url: 'linkedin.com/in/test' } }), { code: 'permission-denied' });
  await assert.rejects(flow.service(broker).create({ ...input, type: 'linkedin' }), { code: 'invalid-argument' });
  await assert.rejects(flow.service(tenant).begin({ ...created, linkedInDetails: { url: 'example.com/in/test' } }), { code: 'invalid-argument' });
  const grant = await flow.service(tenant).begin({ ...created, linkedInDetails: { url: 'linkedin.com/in/test-person/?tracking=remove' } });
  assert.deepEqual(grant.paths, {});
  flow.snapshot({});
  const received = await flow.service(tenant).complete({ ...created, uploadId: grant.uploadId });
  assert.deepEqual(received.submission.linkedInDetails, { url: 'https://www.linkedin.com/in/test-person', skipped: false });
  assert.equal(flow.notices().length, 1);
  assert.equal((await flow.service(null).read(created)).submission, undefined);
  await flow.service(broker).record({ ...created, action: 'paper_deleted', paper: 'linkedin' });
  await assert.rejects(flow.service(tenant).read(created));
});

test('broker can save or skip LinkedIn but other users cannot impersonate the broker', async () => {
  const flow = fixture();
  const created = await flow.service(broker).create({ ...input, partyId: 'tenant-1', type: 'linkedin' });
  await assert.rejects(flow.service(owner).record({ ...created, action: 'linkedin_added', linkedInDetails: { skipped: true } }), { code: 'permission-denied' });
  await flow.service(broker).record({ ...created, action: 'linkedin_added', linkedInDetails: { skipped: true } });
  assert.deepEqual(flow.get(`brokerDocumentRequests/${created.requestId}`).submission.linkedInDetails, { skipped: true, url: '' });
  const changed = await flow.service(broker).create({ ...input, partyId: 'tenant-1', type: 'linkedin', operationId: 'changed' });
  await assert.rejects(flow.service(broker).record({ ...created, action: 'linkedin_added', linkedInDetails: { skipped: true } }), { code: 'failed-precondition' });
  await flow.service(broker).record({ ...changed, action: 'linkedin_added', linkedInDetails: { url: 'linkedin.com/in/changed' } });
  assert.equal(flow.get(`brokerDocumentRequests/${changed.requestId}`).submission.linkedInDetails.url, 'https://www.linkedin.com/in/changed');
});

test('deleting optional LinkedIn from a bundle preserves every required document scope', async () => {
  const flow = fixture();
  const tenant = { uid: 'tenant', token: { firebase: { sign_in_provider: 'phone' }, phone_number: '+912222222222' } };
  const created = await flow.service(broker).create({ ...input, partyId: 'tenant-1', type: 'all' });
  const grant = await flow.service(tenant).begin({ ...created, linkedInDetails: { url: 'linkedin.com/in/test-only' } });
  flow.snapshot(Object.fromEntries(grant.slots.map(kind => [kind, { path: kind }])));
  await flow.service(tenant).complete({ ...created, uploadId: grant.uploadId });
  await flow.service(broker).record({ ...created, action: 'paper_deleted', paper: 'linkedin' });
  const record = flow.get(`brokerDocumentRequests/${created.requestId}`);
  assert.equal(record.status, 'added');
  assert.equal(record.closedPapers.linkedin.action, 'paper_deleted');
  assert.equal(Object.keys(record.submission.files).length, 4);
  assert.deepEqual((await flow.service(tenant).read(created)).slots, ['aadhaarFront', 'aadhaarBack', 'pan', 'bankProof']);
});
test('bundle link grants all four document pages without recipient app profile', async () => {
  const flow = fixture();
  const created = await flow.service(broker).create({ ...input, type: 'all' });
  assert.equal((await flow.service(null).read(created)).submission, undefined);
  await assert.rejects(flow.service(broker).begin(created), { code: 'permission-denied' });
  const grant = await flow.service(owner).begin(created);
  assert.deepEqual(grant.slots, ['aadhaarFront', 'aadhaarBack', 'pan', 'bankProof']);
  flow.snapshot(Object.fromEntries(grant.slots.map(kind => [kind, { path: kind }])));
  const received = await flow.service(owner).complete({ ...created, uploadId: grant.uploadId });
  assert.equal(received.status, 'added');
  assert.equal(Object.keys(received.submission.files).length, 4);
});
test('typed bank details are server validated, scoped, private and never marked bank verified', async () => {
  const flow = fixture();
  const created = await flow.service(broker).create({ ...input, type: 'all' });
  const bankDetails = { method: 'bank', name: 'Test Owner', bank: 'TEST bank', accountType: 'savings',
    accountNumber: '123456789012', ifsc: 'SBIN0001234', verified: true, untrusted: 'ignored' };
  const grant = await flow.service(owner).begin({ ...created, bankDetails });
  assert.deepEqual(grant.slots, ['aadhaarFront', 'aadhaarBack', 'pan']);
  flow.snapshot(Object.fromEntries(grant.slots.map(kind => [kind, { path: kind }])));
  const received = await flow.service(owner).complete({ ...created, uploadId: grant.uploadId, bankDetails: { method: 'upi', upiId: 'attacker@bank' } });
  assert.equal(received.submission.bankDetails.accountNumber, bankDetails.accountNumber);
  assert.equal(received.submission.bankDetails.verified, false);
  assert.equal(received.submission.bankDetails.untrusted, undefined);
  assert.equal((await flow.service(null).read(created)).submission, undefined);
});
test('invalid bank details and bank details injected into Aadhaar-only link are rejected before grants', async () => {
  const flow = fixture();
  const created = await flow.service(broker).create({ ...input, type: 'bank' });
  for (const bankDetails of [{ method: 'upi', upiId: 'invalid' }, { method: 'bank', accountNumber: '1' }, { method: 'upi', upiId: 'valid@bank', verified: true }]) {
    if (bankDetails.upiId === 'valid@bank') {
      const grant = await flow.service(owner).begin({ ...created, bankDetails });
      assert.deepEqual(grant.slots, []);
      flow.snapshot({});
      const received = await flow.service(owner).complete({ ...created, uploadId: grant.uploadId });
      assert.equal(received.submission.bankDetails.verified, false);
    } else await assert.rejects(flow.service(owner).begin({ ...created, bankDetails }), { code: 'invalid-argument' });
  }
  const aadhaar = await flow.service(broker).create(input);
  await assert.rejects(flow.service(owner).begin({ ...aadhaar, bankDetails: { method: 'upi', upiId: 'valid@bank' } }), { code: 'invalid-argument' });
});
test('scoped private links expose no files before phone proof and never require a recipient profile', async () => {
  const flow = fixture();
  const created = await flow.service(broker).create(input);
  assert.equal(created.token.length, 108);
  assert.equal(flow.get(`brokerDocumentRequests/${created.requestId}`).token, undefined);
  assert.equal(flow.get(`documentRequestSecrets/${created.requestId}`).token, created.token);
  const invitation = await flow.service(null).read(created);
  assert.equal(invitation.verified, false);
  assert.equal(invitation.submission, undefined);
  assert.equal(invitation.status, 'created');
  const seen = await flow.service(owner).read(created);
  assert.equal(seen.verified, true);
  assert.equal(seen.status, 'seen');
  assert.equal(flow.get(`brokerDocumentRequests/${created.requestId}`).recipientUid, 'owner');
});
test('unapproved, paused and cross-broker creation and invalid identifiers are denied', async () => {
  for (const auth of [null, { uid: 'other' }]) await assert.rejects(fixture().service(auth).create(input));
  for (const changes of [{ approvalStatus: 'pending' }, { paused: true }]) {
    const flow = fixture(); flow.set('users/broker', { ...flow.get('users/broker'), ...changes });
    await assert.rejects(flow.service(broker).create(input), { code: 'permission-denied' });
  }
  for (const change of [{ partyId: '../owner' }, { type: 'everything' }, { revision: 0 }, { operationId: '' }])
    await assert.rejects(fixture().service(broker).create({ ...input, ...change }), { code: 'invalid-argument' });
});
test('operation retries and reminders preserve a token; resend rotates and expires the old capability', async () => {
  const flow = fixture();
  const original = await flow.service(broker).create(input);
  assert.equal((await flow.service(broker).create(input)).token, original.token);
  assert.equal((await flow.service(broker).create({ ...input, operationId: 'remind', remind: true })).token, original.token);
  const newer = await flow.service(broker).create({ ...input, operationId: 'resend' });
  assert.notEqual(newer.token, original.token);
  await assert.rejects(flow.service(owner).read(original));
  await assert.rejects(flow.service(broker).record({ requestId: original.requestId, version: original.version, action: 'shared' }), { code: 'aborted' });
  flow.advance(7 * 86400000);
  await assert.rejects(flow.service(owner).read(newer));
  await assert.rejects(flow.service(broker).create({ ...input, remind: true, operationId: 'expired' }));
});
test('anonymous, wrong phone and non-phone credentials cannot obtain upload grants or mark shared', async () => {
  const flow = fixture(); const created = await flow.service(broker).create(input);
  for (const auth of [null, broker, { ...owner, token: { ...owner.token, firebase: { sign_in_provider: 'custom' } } }])
    await assert.rejects(flow.service(auth).begin(created), { code: 'permission-denied' });
  await assert.rejects(flow.service(owner).record({ ...created, action: 'shared' }), { code: 'permission-denied' });
  assert.equal(flow.get(`brokerDocumentRequests/${created.requestId}`).status, 'created');
});
test('finalization requires both pages, fails safely and confirms exactly one immutable submission', async () => {
  const flow = fixture(); const created = await flow.service(broker).create(input);
  const grant = await flow.service(owner).begin(created);
  assert.deepEqual(grant.slots, ['aadhaarFront', 'aadhaarBack']);
  flow.snapshot({ aadhaarFront: { path: 'front' } });
  await assert.rejects(flow.service(owner).complete({ ...created, uploadId: grant.uploadId }), { code: 'invalid-argument' });
  assert.equal(flow.get(`brokerDocumentRequests/${created.requestId}`).status, 'seen');
  const updatePath = record => `users/broker/updates/${documentSubmittedUpdate(created.requestId, record).id}`;
  assert.equal(flow.notices().length, 0);
  flow.fail(true);
  await assert.rejects(flow.service(owner).complete({ ...created, uploadId: grant.uploadId }));
  assert.equal(flow.notices().length, 0);
  flow.fail(false); flow.snapshot({ aadhaarFront: { path: 'front' }, aadhaarBack: { path: 'back' } });
  const result = await flow.service(owner).complete({ ...created, uploadId: grant.uploadId });
  assert.equal(result.status, 'added'); assert.equal(result.submission.verified, false);
  const path = updatePath(flow.get(`brokerDocumentRequests/${created.requestId}`));
  const notice = flow.get(path);
  assert.equal(notice.kind, 'documents_received');
  assert.equal(notice.partyId, 'owner-1');
  assert.equal(notice.role, 'owner');
  assert.equal(notice.requestId, created.requestId);
  assert.equal(notice.title, 'Test Owner added Aadhaar card');
  assert.equal(notice.phone, undefined);
  assert.equal(notice.token, undefined);
  flow.set(path, { ...notice, readAt: 123 });
  assert.equal(result.submission.addedByName, 'Test Owner');
  assert.deepEqual(await flow.service(owner).complete({ ...created, uploadId: grant.uploadId }), result);
  assert.equal(flow.get(path).readAt, 123, 'idempotent completion must not reset an already read notice');
  await assert.rejects(flow.service(owner).begin(created));
  await flow.service(broker).record({ requestId: created.requestId, version: created.version, action: 'unclear', reason: 'Back page is not readable.' });
  assert.equal((await flow.service(owner).read(created)).reason, 'Back page is not readable.');
  assert.notEqual((await flow.service(owner).begin(created)).uploadId, grant.uploadId);
});
test('identity edits, broker pause, removed people, new revisions and closed agreements invalidate links', async () => {
  for (const change of ['phone', 'name', 'remove', 'revision', 'pause', 'closed']) {
    const flow = fixture(); const created = await flow.service(broker).create(input);
    const draft = flow.get('users/broker/draftProgress/test').draft;
    if (change === 'phone') draft.owners[0].phone = '+912222222222';
    if (change === 'name') draft.owners[0].name = 'Other Owner';
    if (change === 'remove') draft.owners = [];
    if (change === 'revision') draft.revision = 1;
    if (change === 'pause') flow.get('users/broker').paused = true;
    if (change === 'closed') flow.set('agreements/test', { ...draft, brokerUid: 'broker', revision: 1, status: 'signed' });
    await assert.rejects(flow.service(owner).read(created));
    await assert.rejects(flow.service(owner).begin(created));
  }
});
test('saving the exact agreement keeps a link usable; an unsaved changed identity invalidates it', async () => {
  const flow = fixture(); const created = await flow.service(broker).create(input);
  const draft = flow.get('users/broker/draftProgress/test').draft;
  flow.set('agreements/test', { ...structuredClone(draft), brokerUid: 'broker', revision: 1, status: 'draft' });
  assert.equal((await flow.service(owner).read(created)).verified, true);
  const pending = flow.get('users/broker/draftProgress/test').draft;
  pending.revision = 1; pending.owners[0].phone = '+912222222222';
  await assert.rejects(flow.service(owner).read(created));
});
test('tenant, PAN and bank links grant only their exact paper; grants time out and revoked links fail', async () => {
  const flow = fixture();
  const tenant = { uid: 'tenant', token: { phone_number: '+912222222222', firebase: { sign_in_provider: 'phone' } } };
  for (const [type, slot] of [['pan', 'pan'], ['bank', 'bankProof']]) {
    const created = await flow.service(broker).create({ ...input, type, partyId: 'tenant-1' });
    const grant = await flow.service(tenant).begin(created);
    assert.deepEqual(grant.slots, [slot]);
    flow.snapshot({ [slot]: { path: slot } }); flow.advance(600001);
    await assert.rejects(flow.service(tenant).complete({ ...created, uploadId: grant.uploadId }));
    await flow.service(broker).record({ requestId: created.requestId, version: created.version, action: 'revoked' });
    await assert.rejects(flow.service(tenant).read(created));
  }
});
