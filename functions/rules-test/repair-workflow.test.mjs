import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { createRepairWorkflowService } from '../repair-workflow.js';
import { repairCompletionFiles } from '../repair-completion-files.js';

const projectId = 'demo-trustkeyper-rules';
let app;
let database;
let bucket;
const now = Date.parse('2026-10-10T13:00:00+05:30');
const issueId = 'emulator-workflow-repair';
const operation = digit => digit.repeat(32);
before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  app = initializeApp({ projectId, storageBucket: `${projectId}.appspot.com` }, 'repair-workflow-emulator');
  database = getFirestore(app);
  bucket = getStorage(app).bucket();
  for (const [uid, role] of [['workflow-admin', 'admin'], ['workflow-owner', 'owner'], ['workflow-tenant', 'tenant']]) {
    await database.doc(`users/${uid}`).set({ roles: [role] });
  }
  const participants = ['workflow-owner', 'workflow-tenant'];
  await database.doc('agreements/emulator-workflow-home').set({ revision: 1, participantUids: participants,
    agreementCopy: { mode: 'externally_signed', revision: 1, people: [
      { uid: 'workflow-owner', role: 'owner' }, { uid: 'workflow-tenant', role: 'tenant' }], testFixture: true } });
  await database.doc(`issues/${issueId}`).set({ agreementId: 'emulator-workflow-home', status: 'open',
    participantUids: participants, photos: [] });
});
after(async () => { if (app) await deleteApp(app); });
function service(uid) {
  return createRepairWorkflowService({ auth: { uid }, now: () => now, files: repairCompletionFiles(bucket),
    store: { timestamp: () => FieldValue.serverTimestamp(), transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, value) => transaction.set(database.doc(path), value),
      update: (path, value) => transaction.update(database.doc(path), value),
    })) } });
}
async function input(values) {
  const issue = (await database.doc(`issues/${issueId}`).get()).data();
  return { issueId, version: issue.workflowVersion ?? 0, ...values };
}

test('real emulator transactions and private Storage evidence complete quote, owner approval, visit, bill and tenant confirmation', async () => {
  const admin = service('workflow-admin');
  const owner = service('workflow-owner');
  const tenant = service('workflow-tenant');
  await admin.quote(await input({ operationId: operation('a'), amountPaise: 280000, vendorName: 'Test Plumber',
    vendorPhone: '9999999999', description: 'Repair the test geyser heating element.' }));
  assert.equal((await owner.read({ issueId })).canApprove, true);
  await assert.rejects(tenant.approve(await input({ operationId: operation('b'), quoteVersion: 1 })), { code: 'permission-denied' });
  await owner.approve(await input({ operationId: operation('b'), quoteVersion: 1 }));
  await admin.schedule(await input({ operationId: operation('c'), startsAtMs: now, endsAtMs: now + 3600000 }));
  const request = await input({ operationId: operation('d'), amountPaise: 270000, invoiceNumber: 'EMULATOR-TEST-1',
    payoutDateISO: '2026-11-07', includeBefore: true, visitDone: true });
  const upload = await admin.beginCompletion(request);
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
  for (const slot of ['before', 'after', 'bill']) {
    await bucket.file(`${upload.path}/${slot}`).save(slot === 'bill' ? Buffer.from('%PDF-1.4\nEMULATOR TEST BILL\n%%EOF') : png,
      { resumable: false, metadata: { contentType: slot === 'bill' ? 'application/pdf' : 'image/png',
        metadata: { firebaseStorageDownloadTokens: 'TEST-DO-NOT-PUBLISH' } } });
  }
  assert.equal((await admin.complete({ uploadId: upload.uploadId })).status, 'resolved');
  assert.equal((await admin.complete({ uploadId: upload.uploadId })).status, 'resolved');
  const bill = await owner.readFile({ issueId, slot: 'bill' });
  assert.ok(Buffer.from(bill.base64, 'base64').toString().includes('EMULATOR TEST BILL'));
  assert.equal((await tenant.read({ issueId })).canConfirm, true);
  await tenant.confirm(await input({ operationId: operation('e'), outcome: 'working' }));
  assert.equal((await owner.read({ issueId })).status, 'closed');
  const charge = (await database.doc(`repairCharges/${issueId}`).get()).data();
  assert.equal(charge.status, 'pending_reconciliation');
  assert.equal(charge.amountPaise, 270000);
  assert.equal((await database.collection('payouts').get()).size, 0);
  assert.equal((await bucket.file(`${upload.path}/bill`).exists())[0], false);
  await database.doc('users/workflow-owner').update({ paused: true });
  await assert.rejects(owner.readFile({ issueId, slot: 'bill' }), { code: 'permission-denied' });
});
