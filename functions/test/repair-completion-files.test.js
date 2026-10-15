import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { test } from 'node:test';
import { repairCompletionFiles } from '../repair-completion-files.js';

function fixture() {
  const upload = { issueId: 'repair-test', adminUid: 'admin', uploadId: 'a'.repeat(64), includeBefore: true };
  const objects = new Map();
  for (const slot of ['bill', 'before', 'after']) {
    const bytes = slot === 'bill' ? Buffer.from('%PDF-1.4\nTEST BILL\n%%EOF')
      : Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 0, 0]);
    objects.set(`repairCompletionUploads/admin/${upload.uploadId}/${slot}`, {
      bytes, generation: '123', size: String(bytes.length), contentType: slot === 'bill' ? 'application/pdf' : 'image/png',
      md5Hash: createHash('md5').update(bytes).digest('base64'), metadata: { firebaseStorageDownloadTokens: 'PRIVATE-TEST' },
    });
  }
  const copies = [];
  const bucket = { file: (name, options = {}) => ({ name,
    getMetadata: async () => {
      const value = objects.get(name);
      if (!value) throw Object.assign(new Error('Missing'), { code: 404 });
      if (options.generation) assert.equal(String(options.generation), value.generation);
      return [value];
    },
    download: async range => {
      const value = objects.get(name);
      assert.equal(String(options.generation), value.generation);
      return [value.bytes.subarray(range.start, range.end + 1)];
    },
    copy: async (destination, settings) => {
      assert.equal(settings.preconditionOpts.ifGenerationMatch, 0);
      assert.equal(settings.metadata.firebaseStorageDownloadTokens, null);
      if (objects.has(destination.name)) throw Object.assign(new Error('Exists'), { code: 412 });
      copies.push(destination.name);
      objects.set(destination.name, { ...objects.get(name), generation: '456', contentType: settings.contentType,
        metadata: { sourceGeneration: settings.metadata.sourceGeneration } });
    },
    delete: async () => objects.delete(name),
  }) };
  return { upload, objects, copies, files: repairCompletionFiles(bucket) };
}

test('repair evidence copies fixed generations privately; retries preserve originals and cleanup only staging', async () => {
  const flow = fixture();
  const evidence = await flow.files.snapshot(flow.upload);
  assert.deepEqual(Object.keys(evidence), ['bill', 'before', 'after']);
  assert.deepEqual(await flow.files.snapshot(flow.upload), evidence);
  assert.equal(flow.copies.length, 3);
  assert.equal((await flow.files.read(evidence.bill)).base64, flow.objects.get(evidence.bill.path).bytes.toString('base64'));
  await flow.files.cleanup(flow.upload);
  assert.equal(flow.objects.size, 3);
  for (const value of flow.objects.values()) assert.equal(value.metadata.firebaseStorageDownloadTokens, undefined);
});

test('missing files, bogus MIME, disguised content, oversized or fractional files cannot become repair evidence', async () => {
  for (const reason of ['missing', 'mime', 'header', 'size', 'fraction', 'generation', 'md5']) {
    const flow = fixture();
    const path = `repairCompletionUploads/admin/${flow.upload.uploadId}/bill`;
    const value = flow.objects.get(path);
    if (reason === 'missing') flow.objects.delete(path);
    if (reason === 'mime') value.contentType = 'text/html';
    if (reason === 'header') value.bytes = Buffer.from('NOT A PDF');
    if (reason === 'size') value.size = String(10 * 1024 * 1024 + 1);
    if (reason === 'fraction') value.size = '1.5';
    if (reason === 'generation') value.generation = 'bad';
    if (reason === 'md5') delete value.md5Hash;
    await assert.rejects(flow.files.snapshot(flow.upload));
    assert.equal(flow.copies.length, 0);
  }
});

test('photos reject PDF and private evidence reads reject public tokens, checksum changes or arbitrary paths', async () => {
  const flow = fixture();
  const photo = flow.objects.get(`repairCompletionUploads/admin/${flow.upload.uploadId}/before`);
  photo.contentType = 'application/pdf';
  await assert.rejects(flow.files.snapshot(flow.upload));
  photo.contentType = 'image/png';
  const evidence = await flow.files.snapshot(flow.upload);
  for (const change of [{ path: '../secret' }, { generation: 'invalid' }, { size: 0 }, { size: 1.5 }, { md5Hash: 'wrong' }]) {
    await assert.rejects(flow.files.read({ ...evidence.bill, ...change }));
  }
  const value = flow.objects.get(evidence.bill.path);
  value.metadata.firebaseStorageDownloadTokens = 'NOT-PRIVATE';
  await assert.rejects(flow.files.read(evidence.bill));
  delete value.metadata.firebaseStorageDownloadTokens;
  value.bytes = Buffer.alloc(value.bytes.length);
  await assert.rejects(flow.files.read(evidence.bill));
});
