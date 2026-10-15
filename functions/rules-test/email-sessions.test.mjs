import { readFile } from 'node:fs/promises';
import { after, before, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

let environment;
const phone = '+911111111111';
const proof = { phone_number: phone, firebase: { sign_in_provider: 'custom' }, email: 'email-owner@example.com',
  email_verified: true, trustkeyper_email_otp: true, trustkeyper_verified_phone: phone };
before(async () => {
  environment = await initializeTestEnvironment({ projectId: 'demo-trustkeyper-rules',
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8') },
  });
  await environment.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    await setDoc(doc(database, 'users/email-owner'), { roles: ['owner'], phone });
    await setDoc(doc(database, 'ownerCallbacks/email-owner'), { ownerUid: 'email-owner', status: 'requested' });
    await setDoc(doc(database, 'brokerDocumentRequests/email-session'), {
      phone, type: 'pan', status: 'created', expiresAtMs: Date.now() + 600000,
      currentUploadUid: 'email-owner', currentUploadId: 'attempt', uploadExpiresAtMs: Date.now() + 600000,
    });
    await setDoc(doc(database, 'emailOtpChallenges/private'), { hash: 'never-readable', status: 'sent' });
    await setDoc(doc(database, 'emailOtpRates/private'), { count: 1 });
  });
});
after(async () => environment?.cleanup());

test('linked verified email session reads own callbacks and only its granted document upload', async () => {
  const context = environment.authenticatedContext('email-owner', proof);
  await assertSucceeds(getDoc(doc(context.firestore(), 'ownerCallbacks/email-owner')));
  const file = ref(context.storage(), 'brokerDocumentRequests/email-session/uploads/attempt/pan');
  await assertSucceeds(uploadBytes(file, new TextEncoder().encode('%PDF-1.4\nTest\n%%EOF'), { contentType: 'application/pdf' }));
  await assertSucceeds(getBytes(file));
  await assertFails(uploadBytes(ref(context.storage(), 'brokerDocumentRequests/email-session/uploads/other/pan'), new Uint8Array([1]), { contentType: 'application/pdf' }));
  await assertFails(setDoc(doc(context.firestore(), 'ownerCallbacks/email-owner'), { status: 'completed' }));
});

test('incomplete or mismatched email phone proof cannot read callback or upload identity files', async () => {
  for (const change of [
    { trustkeyper_email_otp: false }, { trustkeyper_verified_phone: '+912222222222' },
    { phone_number: '' }, { email_verified: false }, { email: '' }, { firebase: { sign_in_provider: 'password' } },
  ]) {
    const context = environment.authenticatedContext('email-owner', { ...proof, ...change });
    await assertFails(getDoc(doc(context.firestore(), 'ownerCallbacks/email-owner')));
    await assertFails(getBytes(ref(context.storage(), 'brokerDocumentRequests/email-session/uploads/attempt/pan')));
  }
  const other = environment.authenticatedContext('email-other', proof);
  await assertFails(getDoc(doc(other.firestore(), 'ownerCallbacks/email-owner')));
  await assertFails(getBytes(ref(other.storage(), 'brokerDocumentRequests/email-session/uploads/attempt/pan')));
});

test('challenge hashes, rates and codes are never readable or writable through client credentials', async () => {
  for (const context of [environment.authenticatedContext('email-owner', proof), environment.unauthenticatedContext()]) {
    for (const path of ['emailOtpChallenges/private', 'emailOtpRates/private']) {
      await assertFails(getDoc(doc(context.firestore(), path)));
      await assertFails(setDoc(doc(context.firestore(), path), { status: 'used' }));
    }
  }
});
