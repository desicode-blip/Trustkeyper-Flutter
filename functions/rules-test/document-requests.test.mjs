import { readFile } from 'node:fs/promises';
import { after, before, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';
import { doc, setDoc, getDoc, updateDoc } from 'firebase/firestore';

let environment;
const projectId = 'demo-trustkeyper-rules';
const bytes = new TextEncoder().encode('%PDF-1.4 TEST ONLY');
const data = { brokerUid: 'broker', phone: '+911111111111', type: 'aadhaar', status: 'seen', recipientUid: 'owner',
  currentUploadUid: 'owner', currentUploadId: 'attempt', uploadExpiresAtMs: Date.now() + 600000, expiresAtMs: Date.now() + 86400000,
  submission: { uploadId: 'received' } };
const proof = { phone_number: data.phone, firebase: { sign_in_provider: 'phone' } };
before(async () => {
  environment = await initializeTestEnvironment({ projectId,
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8') },
  });
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'users/broker'), { roles: ['broker'], approvalStatus: 'approved' });
    await setDoc(doc(context.firestore(), 'users/admin'), { roles: ['admin'] });
    await setDoc(doc(context.firestore(), 'brokerDocumentRequests/test'), data);
    await setDoc(doc(context.firestore(), 'documentRequestSecrets/test'), { token: 'private' });
    await uploadBytes(ref(context.storage(), 'brokerDocumentRequests/test/submissions/received/aadhaarFront'), bytes, { contentType: 'application/pdf' });
  });
});
after(async () => environment?.cleanup());
test('only approved requesting broker reads metadata; nobody reads secret capabilities or writes requests', async () => {
  const broker = environment.authenticatedContext('broker');
  await assertSucceeds(getDoc(doc(broker.firestore(), 'brokerDocumentRequests/test')));
  for (const context of [broker, environment.authenticatedContext('admin'), environment.authenticatedContext('owner', proof), environment.authenticatedContext('other'), environment.unauthenticatedContext()]) {
    await assertFails(getDoc(doc(context.firestore(), 'documentRequestSecrets/test')));
    await assertFails(setDoc(doc(context.firestore(), 'brokerDocumentRequests/forged'), data));
    await assertFails(updateDoc(doc(context.firestore(), 'brokerDocumentRequests/test'), { status: 'added' }));
    if (context !== broker) await assertFails(getDoc(doc(context.firestore(), 'brokerDocumentRequests/test')));
  }
});
test('bundle grants all required pages but typed bank cannot upload a proof or extra slot', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'brokerDocumentRequests/bundle'), { ...data, type: 'all', uploadSlots: ['aadhaarFront', 'aadhaarBack', 'pan'] });
  });
  const owner = environment.authenticatedContext('owner', proof);
  for (const kind of ['aadhaarFront', 'aadhaarBack', 'pan']) {
    await assertSucceeds(uploadBytes(ref(owner.storage(), `brokerDocumentRequests/bundle/uploads/attempt/${kind}`), bytes, { contentType: 'application/pdf' }));
  }
  for (const kind of ['bankProof', 'unexpected']) {
    await assertFails(uploadBytes(ref(owner.storage(), `brokerDocumentRequests/bundle/uploads/attempt/${kind}`), bytes, { contentType: 'application/pdf' }));
  }
  await assertFails(uploadBytes(ref(environment.authenticatedContext('other', proof).storage(), 'brokerDocumentRequests/bundle/uploads/attempt/pan'), bytes, { contentType: 'application/pdf' }));
});
test('verified recipient without profile uploads only granted pages and attempt; others cannot read/write', async () => {
  const owner = environment.authenticatedContext('owner', proof);
  const file = ref(owner.storage(), 'brokerDocumentRequests/test/uploads/attempt/aadhaarFront');
  await assertSucceeds(uploadBytes(file, bytes, { contentType: 'application/pdf' }));
  await assertSucceeds(getBytes(file));
  await assertFails(uploadBytes(ref(owner.storage(), 'brokerDocumentRequests/test/uploads/attempt/pan'), bytes, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(owner.storage(), 'brokerDocumentRequests/test/uploads/other/aadhaarFront'), bytes, { contentType: 'application/pdf' }));
  for (const context of [environment.unauthenticatedContext(), environment.authenticatedContext('other', proof),
    environment.authenticatedContext('owner', { ...proof, phone_number: '+912222222222' }), environment.authenticatedContext('owner')]) {
    await assertFails(uploadBytes(ref(context.storage(), file.fullPath), bytes, { contentType: 'application/pdf' }));
    await assertFails(getBytes(ref(context.storage(), file.fullPath)));
  }
  await assertFails(uploadBytes(file, bytes, { contentType: 'text/html' }));
  await assertFails(uploadBytes(file, new Uint8Array(0), { contentType: 'application/pdf' }));
  await assertSucceeds(deleteObject(file));
});
test('received snapshots are readable only to requesting broker and verified recipient, and never client writable', async () => {
  for (const context of [environment.authenticatedContext('broker'), environment.authenticatedContext('owner', proof)]) {
    const file = ref(context.storage(), 'brokerDocumentRequests/test/submissions/received/aadhaarFront');
    await assertSucceeds(getBytes(file));
    await assertFails(uploadBytes(file, bytes, { contentType: 'application/pdf' }));
    await assertFails(deleteObject(file));
  }
  await assertFails(getBytes(ref(environment.authenticatedContext('other', proof).storage(), 'brokerDocumentRequests/test/submissions/received/aadhaarFront')));
});
test('finalizing freezes uploads, expired grants and revoked requests prevent recipient file access', async () => {
  const owner = environment.authenticatedContext('owner', proof);
  for (const change of [{ status: 'finalizing' }, { uploadExpiresAtMs: 1 }, { status: 'revoked' }, { expiresAtMs: 1 }]) {
    await environment.withSecurityRulesDisabled(context => setDoc(doc(context.firestore(), 'brokerDocumentRequests/test'), { ...data, ...change }));
    await assertFails(uploadBytes(ref(owner.storage(), 'brokerDocumentRequests/test/uploads/attempt/aadhaarBack'), bytes, { contentType: 'application/pdf' }));
  }
  await assertFails(getBytes(ref(owner.storage(), 'brokerDocumentRequests/test/submissions/received/aadhaarFront')));
  await assertSucceeds(getBytes(ref(environment.authenticatedContext('broker').storage(), 'brokerDocumentRequests/test/submissions/received/aadhaarFront')));
});
