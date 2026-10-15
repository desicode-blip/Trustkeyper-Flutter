import { readFile } from 'node:fs/promises';
import { after, before, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';

let environment;
const updateId = 'a'.repeat(64);
const path = `users/broker/updates/${updateId}`;
before(async () => {
  environment = await initializeTestEnvironment({ projectId: 'demo-trustkeyper-rules',
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
  await environment.withSecurityRulesDisabled(async context => {
    for (const [uid, data] of Object.entries({
      broker: { roles: ['broker'], approvalStatus: 'approved' },
      other: { roles: ['broker'], approvalStatus: 'approved' },
      pending: { roles: ['broker'], approvalStatus: 'pending' },
      paused: { roles: ['broker'], approvalStatus: 'approved', paused: true },
      owner: { roles: ['owner'] },
    })) await setDoc(doc(context.firestore(), 'users', uid), data);
    await setDoc(doc(context.firestore(), path), { brokerUid: 'broker', kind: 'documents_received', title: 'TEST upload', readAt: null });
  });
});
after(async () => environment?.cleanup());
test('only owning approved broker reads inbox and changes only server-timestamp read receipt', async () => {
  const broker = environment.authenticatedContext('broker').firestore();
  await assertSucceeds(getDoc(doc(broker, path)));
  await assertSucceeds(updateDoc(doc(broker, path), { readAt: serverTimestamp() }));
  for (const values of [{ title: 'forged' }, { readAt: 123 }, { pushState: 'accepted' }, { readAt: serverTimestamp(), requestId: 'forged' }])
    await assertFails(updateDoc(doc(broker, path), values));
  await assertFails(setDoc(doc(broker, 'users/broker/updates/forged'), { brokerUid: 'broker' }));
  await assertFails(deleteDoc(doc(broker, path)));
  for (const context of [environment.unauthenticatedContext(), ...['other', 'owner', 'pending', 'paused'].map(uid => environment.authenticatedContext(uid))]) {
    await assertFails(getDoc(doc(context.firestore(), path)));
    await assertFails(updateDoc(doc(context.firestore(), path), { readAt: serverTimestamp() }));
  }
});
test('push devices are broker-owned, schema restricted and never listed across accounts', async () => {
  const broker = environment.authenticatedContext('broker').firestore();
  const device = `users/broker/pushDevices/${updateId}`;
  const data = { token: 'TEST_ONLY_VALID_LENGTH_PUSH_TOKEN', platform: 'android', enabled: true, updatedAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(broker, device), data));
  for (const values of [{ ...data, updatedAt: 123 }, { ...data, platform: 'web' }, { ...data, token: '' }, { ...data, brokerUid: 'other' }])
    await assertFails(setDoc(doc(broker, device), values));
  await assertFails(setDoc(doc(broker, 'users/broker/pushDevices/not-a-hash'), data));
  for (const uid of ['other', 'owner', 'pending', 'paused']) {
    const database = environment.authenticatedContext(uid).firestore();
    await assertFails(getDoc(doc(database, device)));
    await assertFails(setDoc(doc(database, device), data));
  }
  await assertSucceeds(deleteDoc(doc(broker, device)));
});
