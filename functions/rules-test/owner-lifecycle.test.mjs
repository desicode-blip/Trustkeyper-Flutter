import assert from 'node:assert/strict';
import { before, after, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { deflateSync } from 'node:zlib';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { getDoc, doc, setDoc } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { createOwnerLifecycleService } from '../owner-lifecycle.js';
import { ownerContractFiles } from '../owner-contract-files.js';
import { ownerPropertyFiles } from '../owner-property-files.js';
import { createOwnerPropertyService } from '../owner-properties.js';

const projectId = 'demo-trustkeyper-rules';
const propertyId = '8'.repeat(64);
let environment; let app; let database; let bucket;
const clock = { value: Date.now() };
before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  environment = await initializeTestEnvironment({ projectId,
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8') } });
  app = initializeApp({ projectId, storageBucket: `${projectId}.appspot.com` }, 'owner-lifecycle-test');
  database = getFirestore(app); bucket = getStorage(app).bucket();
  await database.doc('users/lifecycle-owner').set({ roles: ['owner'], phone: '+911111111111' });
  await database.doc('users/lifecycle-admin').set({ roles: ['admin'] });
  await database.doc('users/lifecycle-other').set({ roles: ['owner'], phone: '+912222222222' });
  await database.doc(`ownerProperties/${propertyId}`).set({ ownerUid: 'lifecycle-owner', revision: 8, nextStep: 4,
    status: 'fee_offered', plan: 'full_service', photos: [], details: { name: 'PRIVATE TEST nickname', address: 'PRIVATE TEST door', rooms: '2 BHK',
      features: ['Lift'], pets: 'Ask me', rentPaise: 1000000, depositPaise: 2000000, maintenancePaise: 0, availableFrom: '2026-11-01', furnishing: 'Semi', whoCanStay: 'Anyone' },
    feeOffer: { version: 8, feeBps: 800, effectiveFrom: '2026-11-01', status: 'offered' } });
  await database.doc(`properties/${propertyId}`).set({ ownerUid: 'lifecycle-owner' });
});
after(async () => { if (environment) await environment.cleanup(); if (app) await deleteApp(app); });
function service(uid = 'lifecycle-owner') {
  return createOwnerLifecycleService({ auth: uid ? { uid, token: { phone_number: uid === 'lifecycle-owner' ? '+911111111111' : '+912222222222',
    auth_time: Math.floor(clock.value / 1000), firebase: { sign_in_provider: 'phone' } } } : null, now: () => clock.value,
    files: ownerContractFiles(bucket), photos: ownerPropertyFiles(bucket), store: {
      transaction: handler => database.runTransaction(transaction => handler({
        get: async path => (await transaction.get(database.doc(path))).data(),
        set: (path, data) => transaction.set(database.doc(path), data),
        update: (path, data) => transaction.update(database.doc(path), data),
      })),
    } });
}
async function pdf(text) {
  const { PDFDocument } = await import('pdf-lib'); const document = await PDFDocument.create();
  document.addPage().drawText(`EMULATOR ONLY - NOT A LEGAL CONTRACT - ${text}`);
  return Buffer.from(await document.save());
}
test('actual Storage grants reject non-admin, cross-account, wrong type and size; contract copies remain private, versioned and token-free', async () => {
  const owner = environment.authenticatedContext('lifecycle-owner', { phone_number: '+911111111111', firebase: { sign_in_provider: 'phone' } });
  const admin = environment.authenticatedContext('lifecycle-admin');
  const other = environment.authenticatedContext('lifecycle-other');
  const bytes = await pdf('UNSIGNED TERMS');
  const spec = { size: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex'), contentType: 'application/pdf' };
  const input = { id: propertyId, revision: 8, operationId: '3'.repeat(32), kind: 'source', spec, reference: 'EMULATOR ONLY checked test terms', originalChecked: true };
  await assert.rejects(service('lifecycle-owner').beginContract(input), { code: 'permission-denied' });
  const grant = await service('lifecycle-admin').beginContract(input);
  const storage = admin.storage(`gs://${projectId}.appspot.com`);
  await assertFails(uploadBytes(ref(owner.storage(`gs://${projectId}.appspot.com`), grant.path), bytes, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(other.storage(`gs://${projectId}.appspot.com`), grant.path), bytes, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(storage, grant.path), bytes, { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(storage, grant.path), bytes.subarray(0, 10), { contentType: 'application/pdf' }));
  await assertSucceeds(uploadBytes(ref(storage, grant.path), bytes, { contentType: 'application/pdf' }));
  await assertFails(getDoc(doc(admin.firestore(), `ownerContractUploads/${grant.uploadId}`)));
  await assertFails(setDoc(doc(admin.firestore(), 'ownerContractChallenges/fake'), { consent: true }));
  const result = await service('lifecycle-admin').completeContract({ uploadId: grant.uploadId });
  assert.equal(result.contract.sourceFile.sha256, spec.sha256); assert.equal(result.contract.sourceFile.path, undefined);
  const property = (await database.doc(`ownerProperties/${propertyId}`).get()).data();
  const [metadata] = await bucket.file(property.contract.sourceFile.path).getMetadata();
  assert.equal(Boolean(metadata.metadata?.firebaseStorageDownloadTokens), false);
  await assertFails(getBytes(ref(storage, property.contract.sourceFile.path)));
  await assertFails(getBytes(ref(owner.storage(`gs://${projectId}.appspot.com`), property.contract.sourceFile.path)));
  assert.equal((await service().readContract({ id: propertyId })).base64, bytes.toString('base64'));
  await assert.rejects(service('lifecycle-other').readContract({ id: propertyId }), { code: 'permission-denied' });
  const challenge = await service().change({ id: propertyId, revision: result.revision, action: 'begin_consent', operationId: '4'.repeat(32) });
  clock.value += 2000;
  const consent = await service().change({ id: propertyId, revision: result.revision, action: 'confirm_consent', challengeId: challenge.challengeId, readTerms: true, acceptTerms: true });
  assert.equal(consent.status, 'contract_accepted');
  const signedBytes = await pdf('TEST SIGNATURE FIXTURE ONLY');
  const signed = await service('lifecycle-admin').beginContract({ ...input, revision: consent.revision, operationId: '5'.repeat(32), kind: 'signed', signaturesChecked: true,
    spec: { ...spec, size: signedBytes.length, sha256: createHash('sha256').update(signedBytes).digest('hex') } });
  await assertSucceeds(uploadBytes(ref(storage, signed.path), signedBytes, { contentType: 'application/pdf' }));
  const complete = await service('lifecycle-admin').completeContract({ uploadId: signed.uploadId });
  assert.equal(complete.status, 'plan_active');
  assert.equal((await service().readContract({ id: propertyId, signed: true })).base64, signedBytes.toString('base64'));
  assert.equal((await database.doc(`properties/${propertyId}`).get()).data().activeAgreementId, undefined);
});

test('corrupted uploaded PDF never becomes terms or a signed contract', async () => {
  const previous = (await database.doc(`ownerProperties/${propertyId}`).get()).data();
  const badId = '9'.repeat(64);
  await database.doc(`ownerProperties/${badId}`).set({ ...previous, revision: 8, status: 'fee_offered', contract: null });
  const bytes = Buffer.from('%PDF-1.7 invalid fake body %%EOF');
  const grant = await service('lifecycle-admin').beginContract({ id: badId, revision: 8, operationId: '6'.repeat(32), kind: 'source',
    spec: { size: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex'), contentType: 'application/pdf' }, reference: 'EMULATOR invalid fixture', originalChecked: true });
  await bucket.file(grant.path).save(bytes, { contentType: 'application/pdf' });
  await assert.rejects(service('lifecycle-admin').completeContract({ uploadId: grant.uploadId }), { code: 'invalid-argument' });
  assert.equal((await database.doc(`ownerProperties/${badId}`).get()).data().contract, null);
});

test('actual team-photo grants, explicit owner publication, verified interest and paused private receipts work together', async () => {
  const header = Buffer.alloc(13); header.writeUInt32BE(300, 0); header.writeUInt32BE(300, 4); header[8] = 8; header[9] = 2;
  function chunk(type, body) {
    const data = Buffer.concat([Buffer.from(type), body]); let checksum = 0xffffffff;
    for (const value of data) { checksum ^= value; for (let bit = 0; bit < 8; bit++) checksum = checksum >>> 1 ^ ((checksum & 1) ? 0xedb88320 : 0); }
    const length = Buffer.alloc(4); length.writeUInt32BE(body.length); const crc = Buffer.alloc(4); crc.writeUInt32BE((checksum ^ 0xffffffff) >>> 0);
    return Buffer.concat([length, data, crc]);
  }
  const bytes = Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', header), chunk('IDAT', deflateSync(Buffer.alloc(300 * 901))), chunk('IEND', Buffer.alloc(0))]);
  const props = uid => createOwnerPropertyService({ auth: { uid, token: { phone_number: '+911111111111', firebase: { sign_in_provider: 'phone' } } },
    files: ownerPropertyFiles(bucket), now: () => clock.value, store: { transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(), set: (path, data) => transaction.set(database.doc(path), data),
      update: (path, data) => transaction.update(database.doc(path), data),
    })) } });
  let property = (await database.doc(`ownerProperties/${propertyId}`).get()).data();
  const request = { id: propertyId, revision: property.revision, operationId: '7'.repeat(32), admin: true,
    specs: [{ size: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex'), contentType: 'image/png' }] };
  await assert.rejects(props('lifecycle-owner').beginPhotos(request), { code: 'permission-denied' });
  const grant = await props('lifecycle-admin').beginPhotos(request);
  const admin = environment.authenticatedContext('lifecycle-admin'); const other = environment.authenticatedContext('lifecycle-other');
  const storage = admin.storage(`gs://${projectId}.appspot.com`);
  await assertFails(uploadBytes(ref(other.storage(`gs://${projectId}.appspot.com`), grant.paths[0]), bytes, { contentType: 'image/png' }));
  await assertSucceeds(uploadBytes(ref(storage, grant.paths[0]), bytes, { contentType: 'image/png' }));
  await assert.rejects(props('lifecycle-admin').completePhotos({ uploadId: grant.uploadId }), { code: 'permission-denied' });
  property = await props('lifecycle-admin').completePhotos({ uploadId: grant.uploadId, admin: true });
  assert.deepEqual(await props('lifecycle-admin').completePhotos({ uploadId: grant.uploadId, admin: true }), property);
  property = await service().change({ id: propertyId, revision: property.revision, action: 'publish_listing', title: 'EMULATOR public home',
    locality: 'TEST Hyderabad', publicDetailsApproved: true, publicPhotosApproved: true });
  const publicData = await service(null).readPublic({ id: propertyId });
  assert.equal(JSON.stringify(publicData).includes('PRIVATE TEST'), false);
  assert.equal((await service(null).readPublic({ id: propertyId, photoIndex: 0 })).base64, bytes.toString('base64'));
  const inquiry = await service('lifecycle-other').enquire({ id: propertyId, action: 'interest', name: 'EMULATOR consenting tenant', household: 2,
    work: 'TEST workplace', moveIn: '2026-11-01' });
  property = (await database.doc(`ownerProperties/${propertyId}`).get()).data();
  property = await service('lifecycle-admin').change({ id: propertyId, revision: property.revision, action: 'check_tenant', candidateId: inquiry.candidateId,
    identityChecked: true, reference: 'EMULATOR ONLY fixture review' });
  property = await service().change({ id: propertyId, revision: property.revision, action: 'choose_tenant', candidateId: inquiry.candidateId });
  assert.equal(property.status, 'tenant_chosen');
  assert.equal((await service('lifecycle-other').enquire({ id: propertyId, action: 'status' })).status, 'chosen');
  await assert.rejects(service(null).readPublic({ id: propertyId }), { code: 'not-found' });
  const agreementId = 'EMULATOR-lifecycle-linked-agreement';
  const agreement = { propertyId, owners: [{ phone: '+911111111111' }], tenants: [{ phone: '+912222222222' }] };
  await database.doc(`agreements/${agreementId}`).set(agreement);
  const owner = environment.authenticatedContext('lifecycle-owner', { phone_number: '+911111111111', firebase: { sign_in_provider: 'phone' } });
  await assertFails(getDoc(doc(owner.firestore(), 'agreements', agreementId)));
  const link = { id: propertyId, revision: property.revision, action: 'link_agreement', candidateId: inquiry.candidateId, agreementId };
  await assert.rejects(service('lifecycle-admin').change(link), { code: 'failed-precondition' });
  await database.doc(`agreements/${agreementId}`).set({ ...agreement, participantUids: ['lifecycle-owner', 'lifecycle-other'] });
  property = await service('lifecycle-admin').change(link);
  assert.equal(property.agreementId, agreementId);
  assert.equal((await service('lifecycle-other').enquire({ id: propertyId, action: 'status' })).agreementReady, true);
  await assertSucceeds(getDoc(doc(owner.firestore(), 'agreements', agreementId)));
  await assertSucceeds(getDoc(doc(other.firestore(), 'agreements', agreementId)));
  await assertFails(getDoc(doc(environment.authenticatedContext('lifecycle-stranger').firestore(), 'agreements', agreementId)));
});
