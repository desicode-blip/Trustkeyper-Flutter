import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { agreementCopyFiles } from '../agreement-copy-files.js';

function fixture() {
  const bytes = Buffer.from('%PDF-1.4\nPRIVATE TEST COPY\n%%EOF');
  const digest = createHash('sha256').update(bytes).digest('hex');
  const id = 'a'.repeat(64);
  const path = `agreementCopies/test/1/${id}.pdf`;
  const sourcePath = `agreementCopyUploads/admin/${id}/agreement.pdf`;
  const objects = new Map([[sourcePath, { bytes, generation: '123', size: String(bytes.length),
    contentType: 'application/pdf', metadata: { firebaseStorageDownloadTokens: 'NEVER-PUBLISH' } }]]);
  const calls = [];
  const bucket = { file: (name, options = {}) => ({ name,
    getMetadata: async () => {
      const object = objects.get(name);
      if (!object) throw Object.assign(new Error('Missing'), { code: 404 });
      if (options.generation) assert.equal(String(options.generation), object.generation);
      return [object];
    },
    download: async range => {
      const object = objects.get(name);
      assert.equal(String(options.generation), object.generation);
      assert.deepEqual(range, { start: 0, end: Number(object.size) - 1 });
      return [object.bytes];
    },
    copy: async (destination, settings) => {
      calls.push(settings);
      assert.equal(settings.preconditionOpts.ifGenerationMatch, 0);
      assert.equal(settings.metadata.firebaseStorageDownloadTokens, null);
      if (objects.has(destination.name)) throw Object.assign(new Error('Exists'), { code: 412 });
      objects.set(destination.name, { ...objects.get(name), generation: '456',
        contentType: settings.contentType, cacheControl: settings.cacheControl, metadata: { sha256: digest } });
    },
    delete: async () => { objects.delete(name); },
  }) };
  return { bytes, digest, id, path, sourcePath, objects, calls, files: agreementCopyFiles(bucket),
    upload: { path: sourcePath, agreementId: 'test', revision: 1, size: bytes.length, sha256: digest } };
}

test('PDF copy is generation-bound, checksum-verified, immutable and strips public download tokens', async () => {
  const flow = fixture();
  const copy = await flow.files.snapshot(flow.upload, flow.id);
  assert.equal(copy.path, flow.path);
  assert.equal(copy.generation, '456');
  assert.equal(await flow.files.read(copy), flow.bytes.toString('base64'));
  assert.deepEqual(await flow.files.snapshot(flow.upload, flow.id), copy);
  assert.equal(flow.calls.length, 1);
  await flow.files.cleanup(flow.upload);
  assert.equal(flow.objects.has(flow.sourcePath), false);
  assert.equal(flow.objects.has(flow.path), true);
});

test('missing, wrong-MIME, non-PDF, wrong-checksum or unbounded files cannot be published', async () => {
  for (const reason of ['missing', 'mime', 'header', 'eof', 'checksum', 'oversize']) {
    const flow = fixture();
    const object = flow.objects.get(flow.sourcePath);
    if (reason === 'missing') flow.objects.delete(flow.sourcePath);
    if (reason === 'mime') object.contentType = 'text/html';
    if (reason === 'header') object.bytes = Buffer.from('xxxxx1.4\nPRIVATE TEST COPY\n%%EOF');
    if (reason === 'eof') object.bytes = Buffer.from('%PDF-1.4\nPRIVATE TEST COPY\nxxxxx');
    if (reason === 'checksum') flow.upload.sha256 = 'b'.repeat(64);
    if (reason === 'oversize') flow.upload.size = 21 * 1024 * 1024;
    await assert.rejects(flow.files.snapshot(flow.upload, flow.id));
    assert.equal(flow.objects.has(flow.path), false);
  }
});

test('reads reject public-token metadata, changed generations/bytes and forged file references', async () => {
  const flow = fixture();
  const copy = await flow.files.snapshot(flow.upload, flow.id);
  for (const patch of [{ path: '../private' }, { generation: 'abc' }, { size: 1.5 }, { size: 0 }, { sha256: 'bad' }]) {
    await assert.rejects(flow.files.read({ ...copy, ...patch }));
  }
  const object = flow.objects.get(flow.path);
  object.metadata.firebaseStorageDownloadTokens = 'NOT-PRIVATE';
  await assert.rejects(flow.files.read(copy));
  delete object.metadata.firebaseStorageDownloadTokens;
  object.bytes = Buffer.alloc(flow.bytes.length);
  await assert.rejects(flow.files.read(copy));
});
