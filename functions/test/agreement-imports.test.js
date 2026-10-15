import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PDFDocument } from 'pdf-lib';
import { createAgreementImportService, validateImportFiles, validateImportSigners } from '../agreement-imports.js';
import { validateImportedPages } from '../agreement-import-files.js';

function fixture() {
  let records = new Map([
    ['users/broker', { roles: ['broker'], approvalStatus: 'approved', phone: '+919999999999' }],
    ['users/admin', { roles: ['admin'] }],
    ['users/other', { roles: ['broker'], approvalStatus: 'approved', phone: '+918888888888' }],
    ['users/tenant', { roles: ['tenant'], phone: '+912222222222' }],
  ]);
  const clock = { value: 1000 };
  const state = { snapshots: 0, signedHash: 'b'.repeat(64), fail: false };
  const store = { transaction: async handler => {
    const next = structuredClone(records);
    let wrote = false;
    const result = await handler({
      get: async path => { assert.equal(wrote, false, 'All reads must precede writes'); return next.get(path); },
      set: (path, value) => { wrote = true; next.set(path, structuredClone(value)); },
      update: (path, value) => { wrote = true; next.set(path, { ...next.get(path), ...structuredClone(value) }); },
    });
    records = next; return result;
  }, list: async (collection, uid) => [...records.entries()].filter(([path, value]) =>
    path.startsWith(`${collection}/`) && !path.slice(collection.length + 1).includes('/') && (!uid || value.brokerUid === uid))
    .map(([path, value]) => ({ ...value, id: path.split('/')[1] })) };
  const files = { read: async () => 'PRIVATE-TEST-PDF', cleanup: async () => {}, snapshot: async (grant, uploadId) => {
    if (state.fail) throw new Error('TEST failed snapshot');
    state.snapshots++;
    return { path: `agreementImportFiles/${grant.requestId}/${grant.kind}/${uploadId}.pdf`, generation: '123',
      size: 100, sha256: grant.kind === 'signed' ? state.signedHash : 'a'.repeat(64), pageCount: 2 };
  } };
  const input = { operationId: 'a'.repeat(32), pagesReviewed: true,
    files: [{ sha256: 'a'.repeat(64), size: 100, contentType: 'application/pdf' }],
    signers: [{ name: 'TEST Owner', phone: '+911111111111', role: 'owner' },
      { name: 'TEST Tenant', phone: '+912222222222', role: 'tenant' }] };
  return { input, state, clock, get: path => records.get(path), set: (path, value) => records.set(path, value),
    size: () => records.size, service: (uid, token = { phone_number: records.get(`users/${uid}`)?.phone,
      firebase: { sign_in_provider: 'phone' } }) => createAgreementImportService({ auth: uid ? { uid, token } : null,
        store, files, now: () => clock.value }) };
}

test('sign-only sends immutable reviewed pages once, retains people and private audit', async () => {
  const flow = fixture(); const broker = flow.service('broker');
  const grant = await broker.begin(flow.input);
  assert.equal(flow.get(`agreementImports/${grant.requestId}`).status, 'uploading');
  assert.equal((await broker.list()).requests.length, 0);
  assert.deepEqual(await broker.complete({ uploadId: grant.uploadId }), { requestId: grant.requestId, ready: true });
  const size = flow.size();
  assert.equal((await broker.begin(flow.input)).completed, true);
  await broker.complete({ uploadId: grant.uploadId });
  assert.equal(flow.state.snapshots, 1); assert.equal(flow.size(), size);
  const request = flow.get(`agreementImports/${grant.requestId}`);
  assert.equal(request.status, 'received'); assert.equal(request.pageCount, 2);
  assert.deepEqual(request.signers, flow.input.signers);
  assert.equal(flow.get(`adminAuditLogs/import-${grant.requestId}-2`).action, 'signing_pages_received');
  const visible = (await broker.list()).requests[0];
  assert.equal(visible.sourceFile, undefined); assert.equal(visible.payloadDigest, undefined);
  assert.equal(visible.hasSource, true);
});

test('anonymous, unverified, unrelated, paused and unapproved accounts cannot send or read imports', async () => {
  const flow = fixture(); const grant = await flow.service('broker').begin(flow.input);
  for (const uid of [null, 'tenant', 'missing']) await assert.rejects(flow.service(uid).begin(flow.input));
  await assert.rejects(flow.service('broker', {}).begin(flow.input), { code: 'permission-denied' });
  for (const update of [{ paused: true }, { approvalStatus: 'pending' }]) {
    const previous = flow.get('users/broker'); flow.set('users/broker', { ...previous, ...update });
    await assert.rejects(flow.service('broker').begin(flow.input), { code: 'permission-denied' }); flow.set('users/broker', previous);
  }
  for (const uid of ['other', 'tenant']) {
    await assert.rejects(flow.service(uid).read({ requestId: grant.requestId }));
    await assert.rejects(flow.service(uid).complete({ uploadId: grant.uploadId }), { code: 'permission-denied' });
    assert.equal((await flow.service('other').list()).requests.length, 0);
  }
});

test('duplicate or changed pages, missing consent and invalid signer details are rejected', async () => {
  const flow = fixture(); const grant = await flow.service('broker').begin(flow.input);
  await assert.rejects(flow.service('broker').begin({ ...flow.input,
    signers: flow.input.signers.map(person => ({ ...person, name: `${person.name} changed` })) }), { code: 'already-exists' });
  for (const value of [[], [flow.input.files[0], flow.input.files[0]], [{ ...flow.input.files[0], size: 21000000 }],
    [{ ...flow.input.files[0], contentType: 'text/plain' }], [{ ...flow.input.files[0], sha256: 'wrong' }]]) {
    assert.throws(() => validateImportFiles(value), { code: 'invalid-argument' });
  }
  for (const value of [[], [flow.input.signers[0]], flow.input.signers.map(person => ({ ...person, phone: '+911111111111' })),
    flow.input.signers.map(person => ({ ...person, role: 'witness' }))]) {
    assert.throws(() => validateImportSigners(value), { code: 'invalid-argument' });
  }
  await assert.rejects(flow.service('broker').begin({ ...flow.input, pagesReviewed: false }), { code: 'invalid-argument' });
  flow.clock.value += 3600001;
  await assert.rejects(flow.service('broker').complete({ uploadId: grant.uploadId }));
  await assert.rejects(flow.service('broker').begin(flow.input));
});

test('failed upload keeps an unsigned request and can retry the exact same pages', async () => {
  const flow = fixture(); const broker = flow.service('broker'); const grant = await broker.begin(flow.input);
  flow.state.fail = true;
  await assert.rejects(broker.complete({ uploadId: grant.uploadId }));
  assert.equal(flow.get(`agreementImports/${grant.requestId}`).status, 'uploading');
  flow.state.fail = false; await broker.complete({ uploadId: grant.uploadId });
  assert.equal(flow.get(`agreementImports/${grant.requestId}`).status, 'received');
});

test('only actual sequential admin stages and a different signed original can complete signing', async () => {
  const flow = fixture(); const broker = flow.service('broker'); const admin = flow.service('admin');
  const grant = await broker.begin(flow.input); await broker.complete({ uploadId: grant.uploadId });
  const action = (revision, status) => ({ requestId: grant.requestId, revision, status, reference: 'TEST portal reference', note: 'TEST actual processing' });
  await assert.rejects(broker.record(action(2, 'stamp_preparing')), { code: 'permission-denied' });
  await assert.rejects(admin.record(action(2, 'signing')));
  await admin.record(action(2, 'stamp_preparing'));
  await assert.rejects(admin.record(action(2, 'ready_to_sign')), { code: 'aborted' });
  await admin.record(action(3, 'ready_to_sign')); await admin.record(action(4, 'signing'));
  await assert.rejects(admin.record(action(5, 'completed')));
  const signedInput = { requestId: grant.requestId, revision: 5, operationId: 'b'.repeat(32),
    file: { contentType: 'application/pdf', size: 100, sha256: 'b'.repeat(64) }, originalChecked: true, allPartiesSigned: true };
  await assert.rejects(broker.beginSigned(signedInput), { code: 'permission-denied' });
  await assert.rejects(admin.beginSigned({ ...signedInput, allPartiesSigned: false }), { code: 'invalid-argument' });
  const signedGrant = await admin.beginSigned(signedInput);
  flow.state.signedHash = 'a'.repeat(64);
  await assert.rejects(admin.complete({ uploadId: signedGrant.uploadId }), { code: 'invalid-argument' });
  flow.state.signedHash = 'b'.repeat(64);
  await admin.complete({ uploadId: signedGrant.uploadId });
  const snapshots = flow.state.snapshots;
  assert.equal((await admin.beginSigned(signedInput)).completed, true);
  await admin.complete({ uploadId: signedGrant.uploadId });
  assert.equal(flow.state.snapshots, snapshots);
  assert.equal(flow.get(`agreementImports/${grant.requestId}`).status, 'completed');
  assert.equal((await broker.read({ requestId: grant.requestId, signed: true })).base64, 'PRIVATE-TEST-PDF');
});

test('real PDF parser counts all pages and rejects fake headers, empty, oversized page sets and unreadable images', async () => {
  const document = await PDFDocument.create(); document.addPage(); document.addPage();
  const bytes = Buffer.from(await document.save());
  assert.equal((await validateImportedPages(bytes, 'application/pdf')).pageCount, 2);
  await assert.rejects(validateImportedPages(Buffer.from('%PDF-1.4\nnot a PDF\n%%EOF'), 'application/pdf'));
  const tooMany = await PDFDocument.create(); for (let index = 0; index < 41; index++) tooMany.addPage();
  await assert.rejects(validateImportedPages(Buffer.from(await tooMany.save()), 'application/pdf'));
  await assert.rejects(validateImportedPages(Buffer.from('not a photo'), 'image/jpeg'));
});
