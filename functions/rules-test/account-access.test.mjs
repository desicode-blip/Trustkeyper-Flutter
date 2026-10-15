import { readFile } from 'node:fs/promises';
import { after, before, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { ref, uploadBytes } from 'firebase/storage';

let environment;
before(async () => {
  environment = await initializeTestEnvironment({ projectId: 'demo-trustkeyper-rules',
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8') },
  });
  await environment.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    await setDoc(doc(database, 'users/closure-customer'), { roles: ['broker'], approvalStatus: 'approved', paused: true,
      accountClosure: { status: 'closed', operation: 'test' } });
    await setDoc(doc(database, 'users/closure-admin'), { roles: ['admin'] });
    await setDoc(doc(database, 'agreements/closure-history'), { participantUids: ['closure-customer'], brokerUid: 'closure-customer' });
    await setDoc(doc(database, 'payments/closure-history'), { participantUids: ['closure-customer'] });
    await setDoc(doc(database, 'accountClosures/closure-customer'), { uid: 'closure-customer', status: 'closed', note: 'PRIVATE TEST NOTE' });
    await setDoc(doc(database, `inspectionUploads/${'9'.repeat(32)}`), { uid: 'closure-customer', status: 'uploading', expiresAtMs: Date.now() + 60000 });
  });
});
after(async () => environment?.cleanup());

test('closed account stale tokens cannot read shared history, change the profile, unpause or upload', async () => {
  const context = environment.authenticatedContext('closure-customer');
  const database = context.firestore();
  await assertSucceeds(getDoc(doc(database, 'users/closure-customer')));
  await assertFails(updateDoc(doc(database, 'users/closure-customer'), { displayName: 'Bypass' }));
  await assertFails(updateDoc(doc(database, 'users/closure-customer'), { paused: false }));
  await assertFails(updateDoc(doc(database, 'users/closure-customer'), { accountClosure: { status: 'restored' } }));
  await assertFails(getDoc(doc(database, 'agreements/closure-history')));
  await assertFails(getDoc(doc(database, 'payments/closure-history')));
  await assertFails(uploadBytes(ref(context.storage(), `inspectionUploads/closure-customer/${'9'.repeat(32)}/photo`),
    new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]), { contentType: 'image/png' }));
});

test('account closure notes are server-only even for normal admin clients; legal history remains available to active admins', async () => {
  for (const uid of ['closure-customer', 'closure-admin']) {
    const database = environment.authenticatedContext(uid).firestore();
    await assertFails(getDoc(doc(database, 'accountClosures/closure-customer')));
    await assertFails(setDoc(doc(database, 'accountClosures/forged'), { uid, status: 'closed' }));
  }
  await assertSucceeds(getDoc(doc(environment.authenticatedContext('closure-admin').firestore(), 'agreements/closure-history')));
});

test('new phone profile cannot invent server closure metadata', async () => {
  const context = environment.authenticatedContext('closure-new', { phone_number: '+919876543210',
    firebase: { sign_in_provider: 'phone' } });
  const profile = { roles: ['owner'], phone: '+919876543210', email: '', displayName: 'Test' };
  await assertFails(setDoc(doc(context.firestore(), 'users/closure-new'), {
    ...profile, accountClosure: { status: 'closed', operation: 'spoof' },
  }));
  await assertSucceeds(setDoc(doc(context.firestore(), 'users/closure-new'), profile));
  await assertFails(updateDoc(doc(context.firestore(), 'users/closure-new'), { accountClosure: { status: 'closed' } }));
});
