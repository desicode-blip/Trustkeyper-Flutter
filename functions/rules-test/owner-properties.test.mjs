import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { deflateSync } from 'node:zlib';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { createOwnerPropertyService } from '../owner-properties.js';
import { ownerPropertyFiles } from '../owner-property-files.js';

const projectId = 'demo-trustkeyper-rules';
let environment; let app; let database; let bucket;
before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  environment = await initializeTestEnvironment({ projectId,
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8') } });
  app = initializeApp({ projectId, storageBucket: `${projectId}.appspot.com` }, 'owner-property-test');
  database = getFirestore(app); bucket = getStorage(app).bucket();
  await database.doc('users/property-test-owner').set({ roles: ['owner'], phone: '+911111111111' });
  await database.doc('users/property-test-other').set({ roles: ['owner'], phone: '+912222222222' });
});
after(async () => { if (environment) await environment.cleanup(); if (app) await deleteApp(app); });
function pngFixture() {
  function chunk(type, body) {
    const data = Buffer.concat([Buffer.from(type), body]); let crc = 0xffffffff;
    for (const value of data) { crc ^= value; for (let bit = 0; bit < 8; bit++) crc = crc >>> 1 ^ ((crc & 1) ? 0xedb88320 : 0); }
    const length = Buffer.alloc(4); length.writeUInt32BE(body.length); const checksum = Buffer.alloc(4); checksum.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
    return Buffer.concat([length, data, checksum]);
  }
  const header = Buffer.alloc(13); header.writeUInt32BE(300, 0); header.writeUInt32BE(300, 4); header[8] = 8; header[9] = 2;
  return Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', header), chunk('IDAT', deflateSync(Buffer.alloc(300 * 901, 0))), chunk('IEND', Buffer.alloc(0))]);
}
function service(uid = 'property-test-owner') {
  return createOwnerPropertyService({ auth: { uid, token: { phone_number: uid === 'property-test-owner' ? '+911111111111' : '+912222222222', firebase: { sign_in_provider: 'phone' } } },
    files: ownerPropertyFiles(bucket), store: {
      list: async ownerUid => (await database.collection('ownerProperties').where('ownerUid', '==', ownerUid).get()).docs.map(document => ({ ...document.data(), id: document.id })),
      transaction: handler => database.runTransaction(transaction => handler({
        get: async path => (await transaction.get(database.doc(path))).data(),
        findAddress: async address => (await transaction.get(database.collection('properties').where('address', '==', address))).docs.map(document => ({ ...document.data(), id: document.id })),
        set: (path, value) => transaction.set(database.doc(path), value), update: (path, value) => transaction.update(database.doc(path), value),
      })),
    } });
}
test('actual owner draft resumes across sessions; photo grants reject cross-account/type/size and publish only immutable private images', async () => {
  let property;
  const steps = [{ address: 'EMULATOR ONLY Example Road, Test Hyderabad', name: 'TEST home', homeType: 'Apartment' },
    { rooms: '2 BHK', bathrooms: 2, balconies: 0, floor: 1, totalFloors: 4, sizeSqFt: 800, furnishing: 'Empty' },
    { features: ['Lift'], pets: 'Ask me' }, { rentPaise: 1000000, maintenancePaise: 0, depositPaise: 2000000, availableFrom: '2026-10-11', whoCanStay: 'Anyone', negotiable: true }];
  for (const [step, input] of steps.entries()) property = await service().save({ id: property?.id, revision: property?.revision ?? 0, step, input, operationId: String(step + 1).repeat(32) });
  assert.equal((await service().read({ id: property.id })).nextStep, 4);
  await assert.rejects(service('property-test-other').read({ id: property.id }), { code: 'permission-denied' });
  const photo = pngFixture(); const grant = await service().beginPhotos({ id: property.id, revision: property.revision, operationId: 'a'.repeat(32),
    specs: [{ contentType: 'image/png', size: photo.length, sha256: createHash('sha256').update(photo).digest('hex') }] });
  const owner = environment.authenticatedContext('property-test-owner', { phone_number: '+911111111111', firebase: { sign_in_provider: 'phone' } });
  const other = environment.authenticatedContext('property-test-other', { phone_number: '+912222222222', firebase: { sign_in_provider: 'phone' } });
  const storage = owner.storage(`gs://${projectId}.appspot.com`);
  await assertFails(uploadBytes(ref(other.storage(`gs://${projectId}.appspot.com`), grant.paths[0]), photo, { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(storage, grant.paths[0]), photo, { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(ref(storage, grant.paths[0]), photo.subarray(0, 20), { contentType: 'image/png' }));
  await assertSucceeds(uploadBytes(ref(storage, grant.paths[0]), photo, { contentType: 'image/png' }));
  await assertFails(getDoc(doc(owner.firestore(), `ownerProperties/${property.id}`)));
  await assertFails(setDoc(doc(owner.firestore(), `ownerPropertyUploads/${grant.uploadId}`), { status: 'completed' }));
  property = await service().completePhotos({ uploadId: grant.uploadId });
  assert.equal(property.photos.length, 1); assert.equal(property.photos[0].path, undefined);
  assert.deepEqual(Buffer.from((await service().readPhoto({ id: property.id, index: 0 })).base64, 'base64'), photo);
  const privateFile = (await database.doc(`ownerProperties/${property.id}`).get()).data().photos[0];
  const [metadata] = await bucket.file(privateFile.path).getMetadata(); assert.equal(Boolean(metadata.metadata?.firebaseStorageDownloadTokens), false);
  await assertFails(getBytes(ref(storage, privateFile.path)));
  await assertFails(uploadBytes(ref(storage, grant.paths[0]), photo, { contentType: 'image/png' }));
  property = await service().save({ id: property.id, revision: property.revision, step: 4, input: { teamPhotos: false }, operationId: '5'.repeat(32) });
  assert.equal((await database.doc(`properties/${property.id}`).get()).data().ownerUid, 'property-test-owner');
  assert.equal(property.status, 'property_added'); assert.equal(property.data?.activeAgreementId, undefined);
});
