import { test } from 'node:test';
import assert from 'node:assert/strict';
import { documentRequestFiles } from '../document-request-files.js';

function fixture({ contentType = 'application/pdf', body = '%PDF-1.4 TEST', size = 20, existing,
  request = { type: 'pan' } } = {}) {
  let canonical = existing;
  let copies = 0;
  const database = { doc: () => ({ get: async () => ({ data: () => request }) }) };
  const bucket = { file: (name, options) => ({ name,
    getMetadata: async () => {
      if (name.includes('/submissions/')) {
        if (!canonical) throw Object.assign(new Error('missing'), { code: 404 });
        return [canonical];
      }
      return [{ contentType, size, generation: '123', metadata: { displayName: 'TEST.pdf', firebaseStorageDownloadTokens: 'temporary' } }];
    },
    download: async () => { assert.equal(options.generation, '123'); return [Buffer.from(body)]; },
    copy: async (destination, copyOptions) => {
      assert.equal(options.generation, '123'); assert.equal(copyOptions.preconditionOpts.ifGenerationMatch, 0);
      assert.equal(copyOptions.metadata.firebaseStorageDownloadTokens, null);
      assert.equal(copyOptions.contentType, contentType);
      canonical = { contentType: copyOptions.contentType, size, generation: '456', metadata: copyOptions.metadata }; copies++;
    },
  }) };
  return { service: documentRequestFiles(database, bucket), copies: () => copies };
}
test('copies exact source generation into create-only private snapshot and removes download capability atomically', async () => {
  const flow = fixture(); const result = await flow.service.snapshot('request', 'upload');
  assert.equal(result.pan.path, 'brokerDocumentRequests/request/submissions/upload/pan');
  assert.equal(result.pan.generation, '456'); assert.equal(flow.copies(), 1);
  assert.equal(result.pan.contentType, 'application/pdf'); assert.equal(result.pan.name, 'TEST.pdf');
  assert.deepEqual(await flow.service.snapshot('request', 'upload'), result); assert.equal(flow.copies(), 1);
});

test('snapshot follows server-granted bundle slots and typed-bank requests require no file', async () => {
  const flow = fixture({ request: { type: 'all', uploadSlots: ['aadhaarFront', 'aadhaarBack', 'pan'] } });
  const result = await flow.service.snapshot('bundle', 'attempt');
  assert.deepEqual(Object.keys(result), ['aadhaarFront', 'aadhaarBack', 'pan']);
  assert.equal(result.bankProof, undefined);
  const typed = fixture({ request: { type: 'bank', uploadSlots: [] } });
  assert.deepEqual(await typed.service.snapshot('bank', 'attempt'), {});
  assert.equal(typed.copies(), 0);
});

test('received metadata must include supported MIME, bounded size and a display name', async () => {
  const existing = { contentType: 'application/pdf', size: 20, generation: '456', metadata: { sourceGeneration: '123', displayName: 'TEST.pdf' } };
  for (const change of [{ contentType: undefined }, { contentType: 'text/html' }, { size: 0 }, { size: 10 * 1024 * 1024 + 1 },
    { metadata: { sourceGeneration: '123' } }]) {
    await assert.rejects(fixture({ existing: { ...existing, ...change } }).service.snapshot('request', 'upload'), { code: 'internal' });
  }
});
test('invalid file size, MIME and mismatched contents never produce a received snapshot', async () => {
  for (const options of [{ size: 0 }, { size: 10 * 1024 * 1024 + 1 }, { contentType: 'text/html' }, { body: 'not a PDF' },
    { contentType: 'image/png' }, { contentType: 'image/jpeg' }]) {
    const flow = fixture(options); await assert.rejects(flow.service.snapshot('request', 'upload'), { code: 'invalid-argument' });
    assert.equal(flow.copies(), 0);
  }
});
test('received snapshots retaining download tokens or lacking source evidence are rejected', async () => {
  for (const metadata of [{ sourceGeneration: '123', firebaseStorageDownloadTokens: 'unsafe' }, {}]) {
    await assert.rejects(fixture({ existing: { metadata } }).service.snapshot('request', 'upload'), { code: 'internal' });
  }
});
