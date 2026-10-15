import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRepairReportService } from '../repair-reports.js';
import { repairReportFiles } from '../repair-report-files.js';

const reportId = 'a'.repeat(32);
const input = { reportId, category: 'Water', description: 'The kitchen tap is leaking.', photoCount: 1 };
function fixture(options = {}) {
  const records = new Map(Object.entries({ 'users/tenant': { roles: ['tenant'] },
    'agreements/home': { participantUids: ['tenant', 'owner'], propertyAddress: 'TEST home' }, ...options.records }));
  let snapshots = 0;
  let cleanup = 0;
  const store = { timestamp: () => 'SERVER_TIMESTAMP', transaction: async handler => {
    const writes = [];
    const result = await handler({ get: async path => structuredClone(records.get(path)),
      set: (path, value) => writes.push(() => records.set(path, structuredClone(value))),
      update: (path, value) => writes.push(() => records.set(path, { ...records.get(path), ...structuredClone(value) })),
    });
    writes.forEach(write => write()); return result;
  } };
  const files = { read: async photo => {
    if (options.afterRead) options.afterRead(records);
    return { path: photo.path, base64: 'TEST' };
  }, snapshot: async (uid, identifier, count) => {
    snapshots++; if (options.failSnapshot) throw new Error('upload interrupted');
    return Array.from({ length: count }, (_, index) => ({ path: `issues/${identifier}/photos/${index}` }));
  }, cleanup: async () => { cleanup++; if (options.failCleanup) throw new Error('cleanup delayed'); } };
  const service = createRepairReportService({ auth: options.auth ?? { uid: 'tenant' }, store, files, now: () => options.time ?? 100 });
  return { service, records, snapshots: () => snapshots, cleanup: () => cleanup };
}

test('repair submission is server-bound, timestamped, photo-aware and idempotent', async () => {
  const flow = fixture();
  await flow.service.begin({ reportId, agreementId: 'home' });
  await flow.service.begin({ reportId, agreementId: 'home' });
  assert.equal(flow.records.get('repairUploadLimits/tenant').count, 1);
  await flow.service.submit({ ...input, participantUids: ['stranger'], propertyAddress: 'forged', status: 'approved' });
  const issue = flow.records.get(`issues/${reportId}`);
  assert.deepEqual(issue.participantUids, ['tenant', 'owner']);
  assert.equal(issue.propertyAddress, 'TEST home'); assert.equal(issue.status, 'open');
  assert.equal(issue.createdAt, 'SERVER_TIMESTAMP'); assert.equal(issue.photos.length, 1);
  assert.deepEqual(await flow.service.submit(input), { reportId, submitted: true });
  assert.equal(flow.snapshots(), 1); assert.equal(flow.cleanup(), 1);
  await assert.rejects(flow.service.submit({ ...input, description: 'Changed after submission.' }), { code: 'failed-precondition' });
});

test('invalid inputs, paused, anonymous, missing and unlinked accounts cannot start uploads', async () => {
  for (const options of [{ auth: {} }, { records: { 'users/tenant': undefined } },
    { records: { 'users/tenant': { paused: true } } },
    { records: { 'agreements/home': { participantUids: ['owner'] } } }]) {
    await assert.rejects(fixture(options).service.begin({ reportId, agreementId: 'home' }), { code: 'permission-denied' });
  }
  for (const value of ['', '../home', 'a'.repeat(151)]) {
    await assert.rejects(fixture().service.begin({ reportId, agreementId: value }), { code: 'invalid-argument' });
  }
  await assert.rejects(fixture().service.begin({ reportId: '../other', agreementId: 'home' }), { code: 'invalid-argument' });
});

test('upload context belongs to its actor/home and respects expiry and rate limits', async () => {
  for (const change of [{ createdBy: 'owner' }, { agreementId: 'other' }]) {
    const flow = fixture({ records: { [`repairReportUploads/${reportId}`]: { agreementId: 'home', createdBy: 'tenant', status: 'uploading', expiresAtMs: 200, ...change } } });
    await assert.rejects(flow.service.begin({ reportId, agreementId: 'home' }), { code: 'permission-denied' });
  }
  const expired = fixture({ records: { [`repairReportUploads/${reportId}`]: { agreementId: 'home', createdBy: 'tenant', status: 'uploading', expiresAtMs: 99 } } });
  await assert.rejects(expired.service.submit(input), { code: 'failed-precondition' });
  const limited = fixture({ records: { 'repairUploadLimits/tenant': { windowStart: 0, count: 20 } } });
  await assert.rejects(limited.service.begin({ reportId, agreementId: 'home' }), { code: 'resource-exhausted' });
});

test('failed photo snapshot never publishes an issue and freezes retries to the original report', async () => {
  const flow = fixture({ failSnapshot: true }); await flow.service.begin({ reportId, agreementId: 'home' });
  await assert.rejects(flow.service.submit(input)); assert.equal(flow.records.has(`issues/${reportId}`), false);
  await assert.rejects(flow.service.submit({ ...input, photoCount: 0 }), { code: 'failed-precondition' });
  assert.equal(flow.records.get(`repairReportUploads/${reportId}`).status, 'uploading');
});

test('membership is rechecked at submission and malformed category/description/count rejected', async () => {
  const flow = fixture(); await flow.service.begin({ reportId, agreementId: 'home' });
  for (const change of [{ category: 'Unknown' }, { description: 'short' }, { description: 'a'.repeat(2001) },
    { photoCount: -1 }, { photoCount: 5 }, { photoCount: 1.5 }]) {
    await assert.rejects(flow.service.submit({ ...input, ...change }), { code: 'invalid-argument' });
  }
  flow.records.get('agreements/home').participantUids = ['owner'];
  await assert.rejects(flow.service.submit(input), { code: 'permission-denied' }); assert.equal(flow.snapshots(), 0);
});

test('successful no-photo report remains successful if temporary cleanup is delayed', async () => {
  const flow = fixture({ failCleanup: true }); await flow.service.begin({ reportId, agreementId: 'home' });
  await flow.service.submit({ ...input, photoCount: 0 });
  assert.deepEqual(flow.records.get(`issues/${reportId}`).photos, []);
});

test('private photo viewing requires current membership or an enabled admin, not a forged path', async () => {
  const records = { [`issues/${reportId}`]: { agreementId: 'home', participantUids: ['tenant', 'owner'],
    photos: [{ path: `issues/${reportId}/photos/0`, generation: '123' }] } };
  assert.equal((await fixture({ records }).service.readPhoto({ reportId, index: 0 })).base64, 'TEST');
  assert.equal((await fixture({ auth: { uid: 'admin' }, records: { ...records,
    'users/admin': { roles: ['admin'] } } }).service.readPhoto({ reportId, index: 0 })).base64, 'TEST');
  for (const changes of [{ 'users/tenant': { paused: true } }, { 'users/tenant': undefined },
    { 'agreements/home': { participantUids: ['owner'] } },
    { [`issues/${reportId}`]: { ...records[`issues/${reportId}`], participantUids: ['owner'] } }]) {
    await assert.rejects(fixture({ records: { ...records, ...changes } }).service.readPhoto({ reportId, index: 0 }), { code: 'permission-denied' });
  }
  await assert.rejects(fixture({ records }).service.readPhoto({ reportId, index: 1 }), { code: 'not-found' });
  await assert.rejects(fixture({ records }).service.readPhoto({ reportId, index: 4 }), { code: 'invalid-argument' });
});

test('private photo viewing rechecks paused status and membership after downloading', async () => {
  for (const afterRead of [records => records.get('users/tenant').paused = true,
    records => records.get('agreements/home').participantUids = ['owner']]) {
    const flow = fixture({ afterRead, records: { [`issues/${reportId}`]: { agreementId: 'home',
      participantUids: ['tenant'], photos: [{ path: `issues/${reportId}/photos/0`, generation: '123' }] } } });
    await assert.rejects(flow.service.readPhoto({ reportId, index: 0 }), { code: 'permission-denied' });
  }
});

test('private photo delivery is generation-bound, byte-checked and never exposes a download URL', async () => {
  const bytes = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const photo = { path: `issues/${reportId}/photos/0`, contentType: 'image/png', size: bytes.length,
    generation: '123', md5Hash: createHash('md5').update(bytes).digest('base64') };
  let metadata = { ...photo, metadata: {} };
  const files = repairReportFiles({ file: (path, options) => {
    assert.equal(path, photo.path); assert.equal(options.generation, photo.generation);
    return { getMetadata: async () => [metadata], download: async () => [bytes] };
  } });
  assert.deepEqual(await files.read(photo), { path: photo.path, contentType: 'image/png', size: bytes.length, base64: bytes.toString('base64') });
  for (const change of [{ generation: '456' }, { md5Hash: 'wrong' }, { size: 10485761 },
    { metadata: { firebaseStorageDownloadTokens: 'unsafe' } }]) {
    metadata = { ...photo, metadata: {}, ...change };
    await assert.rejects(files.read(photo), { code: 'not-found' });
  }
  await assert.rejects(files.read({ ...photo, path: 'users/other/document' }), { code: 'not-found' });
});

test('repair storage upload rules stay within the production two-document access limit', () => {
  const source = readFileSync(new URL('../../storage.rules', import.meta.url), 'utf8');
  const repairRules = source.split('match /repairUploads/')[1].split('match /issues/')[0];
  assert.equal([...repairRules.matchAll(/firestore\.get\(/g)].length, 2);
  assert.equal(repairRules.includes('isAgreementParticipant('), false);
});

function photoFixture({ contentType = 'image/png', size = 20, header = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), existing } = {}) {
  let canonical = existing; let copies = 0;
  const bucket = { file: (name, options) => ({ name,
    getMetadata: async () => {
      if (name.startsWith('issues/')) {
        if (!canonical) throw Object.assign(new Error('missing'), { code: 404 });
        return [canonical];
      }
      return [{ contentType, size, generation: '123', metadata: { firebaseStorageDownloadTokens: 'temporary' } }];
    },
    download: async () => { assert.equal(options.generation, '123'); return [header]; },
    copy: async (destination, settings) => {
      assert.equal(options.generation, '123'); assert.equal(settings.preconditionOpts.ifGenerationMatch, 0);
      assert.equal(settings.metadata.firebaseStorageDownloadTokens, null);
      canonical = { contentType, size, generation: '456', metadata: settings.metadata }; copies++;
    },
  }) };
  return { files: repairReportFiles(bucket), copies: () => copies };
}

test('repair photos freeze source generation into a private create-only snapshot', async () => {
  const flow = photoFixture(); const photos = await flow.files.snapshot('tenant', reportId, 1);
  assert.equal(photos[0].path, `issues/${reportId}/photos/0`); assert.equal(photos[0].generation, '456');
  assert.deepEqual(await flow.files.snapshot('tenant', reportId, 1), photos); assert.equal(flow.copies(), 1);
});

test('invalid or unsafe photo content/metadata cannot become a received snapshot', async () => {
  for (const options of [{ size: 0 }, { size: 10485761 }, { contentType: 'application/pdf' },
    { header: Buffer.from('not a PNG') }, { contentType: 'image/jpeg', header: Buffer.from('not a JPEG') }]) {
    const flow = photoFixture(options); await assert.rejects(flow.files.snapshot('tenant', reportId, 1), { code: 'invalid-argument' });
    assert.equal(flow.copies(), 0);
  }
  for (const metadata of [{}, { sourceGeneration: '123', firebaseStorageDownloadTokens: 'unsafe' }]) {
    await assert.rejects(photoFixture({ existing: { contentType: 'image/png', size: 20, generation: '456', metadata } }).files.snapshot('tenant', reportId, 1), { code: 'internal' });
  }
});
