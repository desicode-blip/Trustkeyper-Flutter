import { readFile } from 'node:fs/promises';
import { after, before, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';
import { doc, setDoc, updateDoc, getDoc, deleteDoc, runTransaction, serverTimestamp, Timestamp } from 'firebase/firestore';

let environment;
const projectId = 'demo-trustkeyper-rules';
const path = 'users/broker/documents/drafts/test/revisions/1/owner/pan/current';
const pdf = new TextEncoder().encode('%PDF-1.4\nTest fixture\n%%EOF');
before(async () => {
  environment = await initializeTestEnvironment({ projectId,
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8') },
  });
  await environment.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    await setDoc(doc(database, 'users/broker'), { roles: ['broker'], approvalStatus: 'approved' });
    await setDoc(doc(database, 'users/second-broker'), { roles: ['broker'], approvalStatus: 'approved' });
    await setDoc(doc(database, 'users/pending'), { roles: ['broker'], approvalStatus: 'pending' });
    await setDoc(doc(database, 'users/paused'), { roles: ['broker'], approvalStatus: 'approved', paused: true });
    await setDoc(doc(database, 'users/admin'), { roles: ['admin'] });
    await setDoc(doc(database, 'agreements/reviewed'), {
      brokerUid: 'broker', participantUids: ['broker'], status: 'review_requested', revision: 1,
    });
    await setDoc(doc(database, 'agreements/reviewed/reviews/1'), { signable: false });
  });
});
after(async () => { await environment?.cleanup(); });

test('tenancy, key challenges and move-out completion are server owned; website metadata cannot mark a property rented', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'agreements/key-test'), { brokerUid: 'broker', participantUids: ['broker'], revision: 1 });
    await setDoc(doc(context.firestore(), 'tenancies/key-test'), { agreementId: 'key-test', phase: 'preparing', version: 1 });
    await setDoc(doc(context.firestore(), 'moveOuts/key-test'), { agreementId: 'key-test', participantUids: ['broker'], status: 'notice_received' });
    await setDoc(doc(context.firestore(), 'properties/key-test'), { brokerUid: 'broker', participantUids: ['broker'], address: 'Test flat' });
    await setDoc(doc(context.firestore(), 'keyHandoverChallenges/private-key'), { codeHash: 'NOT-A-PUBLIC-OTP', status: 'issued' });
  });
  const broker = environment.authenticatedContext('broker').firestore();
  const admin = environment.authenticatedContext('admin').firestore();
  const stranger = environment.authenticatedContext('second-broker').firestore();
  await assertSucceeds(getDoc(doc(broker, 'tenancies/key-test')));
  await assertFails(getDoc(doc(stranger, 'tenancies/key-test')));
  for (const database of [broker, admin]) {
    await assertFails(updateDoc(doc(database, 'tenancies/key-test'), { phase: 'active' }));
    await assertFails(updateDoc(doc(database, 'moveOuts/key-test'), { status: 'completed', refundStatus: 'paid' }));
    for (const path of ['moveOuts/key-test/destinations/tenant', 'moveOutKeyChallenges/private-key',
      'moveOutKeyLimits/private-limit', 'moveOutOperations/private-operation', 'moveOutRefundRequests/private-refund']) {
      await assertFails(getDoc(doc(database, path)));
      await assertFails(setDoc(doc(database, path), { account: 'PRIVATE-TEST-BANK', code: 'NOT-A-REAL-CODE', status: 'paid' }));
    }
    await assertFails(getDoc(doc(database, 'keyHandoverChallenges/private-key')));
    await assertFails(updateDoc(doc(database, 'properties/key-test'), { occupancyStatus: 'rented', activeAgreementId: 'key-test' }));
  }
  await assertFails(setDoc(doc(broker, 'moveOuts/forged'), { participantUids: ['broker'], createdBy: 'broker' }));
  await assertSucceeds(updateDoc(doc(broker, 'properties/key-test'), { address: 'Corrected test address' }));
});

test('inspection upload grants are uid, expiry and size bound; canonical photos and forged review records are private', async () => {
  const checkId = '7'.repeat(32);
  const image = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), `inspectionUploads/${checkId}`), { uid: 'broker', status: 'uploading', expiresAtMs: Date.now() + 60000 });
    await setDoc(doc(context.firestore(), `properties/photo-flat/photoChecks/${checkId}`), { status: 'submitted', createdBy: 'broker' });
  });
  const path = `inspectionUploads/broker/${checkId}/photo`;
  await assertSucceeds(uploadBytes(ref(environment.authenticatedContext('broker').storage(), path), image, { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(environment.authenticatedContext('other').storage(), path), image, { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(environment.authenticatedContext('broker').storage(), path), image, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(environment.authenticatedContext('broker').storage(), `inspectionPhotos/${checkId}/photo`), image, { contentType: 'image/png' }));
  await assertFails(getBytes(ref(environment.authenticatedContext('admin').storage(), `inspectionPhotos/${checkId}/photo`)));
  const documentPath = `properties/photo-flat/photoChecks/${checkId}`;
  await assertFails(updateDoc(doc(environment.authenticatedContext('admin').firestore(), documentPath), { status: 'approved' }));
  await assertFails(getDoc(doc(environment.authenticatedContext('broker').firestore(), documentPath)));
  await assertSucceeds(getDoc(doc(environment.authenticatedContext('admin').firestore(), documentPath)));
  await assertFails(setDoc(doc(environment.authenticatedContext('broker').firestore(), 'inspectionUploads/fake'), { uid: 'broker' }));
  await environment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), `inspectionUploads/${checkId}`), { expiresAtMs: Date.now() - 1000 });
  });
  await assertFails(uploadBytes(ref(environment.authenticatedContext('broker').storage(), path), image, { contentType: 'image/png' }));
});

test('broker property writes cannot invent or replace participant membership', async () => {
  const database = environment.authenticatedContext('broker').firestore();
  const property = doc(database, 'properties/membership-rules');
  await assertFails(setDoc(property, { brokerUid: 'broker', participantUids: ['broker', 'other'] }));
  await assertSucceeds(setDoc(property, { brokerUid: 'broker', participantUids: ['broker'], address: 'Rules test property' }));
  await assertFails(updateDoc(property, { participantUids: ['broker', 'other'] }));
  await assertSucceeds(updateDoc(property, { address: 'Updated rules test property' }));
});

test('repair completion uploads require a current admin grant; private bills and charge records cannot be forged', async () => {
  const uploadId = 'e'.repeat(64);
  const staging = `repairCompletionUploads/admin/${uploadId}`;
  const canonical = `issues/completion-rules/evidence/${uploadId}/bill`;
  const image = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), `repairCompletionUploads/${uploadId}`), {
      adminUid: 'admin', status: 'uploading', includeBefore: false, expiresAtMs: Date.now() + 60000,
    });
    await uploadBytes(ref(context.storage(), canonical), pdf, { contentType: 'application/pdf' });
    await setDoc(doc(context.firestore(), 'repairCharges/completion-rules'), { amountPaise: 280000 });
  });
  const admin = environment.authenticatedContext('admin');
  await assertSucceeds(uploadBytes(ref(admin.storage(), `${staging}/bill`), pdf, { contentType: 'application/pdf' }));
  await assertSucceeds(uploadBytes(ref(admin.storage(), `${staging}/after`), image, { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(admin.storage(), `${staging}/after`), pdf, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(admin.storage(), `${staging}/before`), image, { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(admin.storage(), `${staging}/bill`), new Uint8Array(10 * 1024 * 1024 + 1), { contentType: 'application/pdf' }));
  for (const context of [admin, environment.authenticatedContext('owner'), environment.unauthenticatedContext()]) {
    await assertFails(getBytes(ref(context.storage(), canonical)));
    await assertFails(uploadBytes(ref(context.storage(), canonical), pdf, { contentType: 'application/pdf' }));
    await assertFails(deleteObject(ref(context.storage(), canonical)));
    for (const collection of ['repairCharges', 'repairOperations', 'repairCompletionUploads']) {
      await assertFails(getDoc(doc(context.firestore(), `${collection}/completion-rules`)));
      await assertFails(setDoc(doc(context.firestore(), `${collection}/completion-rules`), { status: 'completed' }));
    }
  }
  for (const context of [environment.authenticatedContext('owner'), environment.unauthenticatedContext()]) {
    await assertFails(uploadBytes(ref(context.storage(), `${staging}/bill`), pdf, { contentType: 'application/pdf' }));
  }
  await environment.withSecurityRulesDisabled(async context => updateDoc(doc(context.firestore(), `repairCompletionUploads/${uploadId}`), { expiresAtMs: Date.now() - 60000 }));
  await assertFails(uploadBytes(ref(admin.storage(), `${staging}/bill`), pdf, { contentType: 'application/pdf' }));
});

test('payment credit/order/account state is server-only; participants read but cannot forge receipts', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    await setDoc(doc(database, 'payments/pay_test_rules'), { mode: 'test', status: 'paid', participantUids: ['broker', 'tenant'], amountPaise: 100 });
    for (const collection of ['rentPaymentIntents', 'rentPaymentAccounts', 'razorpayTestOrders', 'razorpayTestEvents']) {
      await setDoc(doc(database, `${collection}/rules-test`), { payerUid: 'tenant', status: 'paid' });
    }
  });
  for (const uid of ['broker', 'tenant', 'admin']) {
    await assertSucceeds(getDoc(doc(environment.authenticatedContext(uid).firestore(), 'payments/pay_test_rules')));
  }
  for (const context of [environment.authenticatedContext('broker'), environment.authenticatedContext('tenant'),
    environment.authenticatedContext('admin'), environment.authenticatedContext('second-broker'), environment.unauthenticatedContext()]) {
    await assertFails(setDoc(doc(context.firestore(), 'payments/pay_forged'), { status: 'paid', participantUids: ['tenant'] }));
    await assertFails(updateDoc(doc(context.firestore(), 'payments/pay_test_rules'), { status: 'paid', amountPaise: 1 }));
    for (const collection of ['rentPaymentIntents', 'rentPaymentAccounts', 'razorpayTestOrders', 'razorpayTestEvents']) {
      await assertFails(getDoc(doc(context.firestore(), `${collection}/rules-test`)));
      await assertFails(setDoc(doc(context.firestore(), `${collection}/rules-test`), { status: 'paid' }));
    }
  }
  await assertFails(getDoc(doc(environment.authenticatedContext('second-broker').firestore(), 'payments/pay_test_rules')));
});

test('final agreement PDFs are callable-only; upload grants are admin, expiry and MIME bound', async () => {
  const uploadId = 'd'.repeat(64);
  const staging = `agreementCopyUploads/admin/${uploadId}/agreement.pdf`;
  const final = `agreementCopies/reviewed/1/${uploadId}.pdf`;
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), `agreementCopyUploads/${uploadId}`), {
      adminUid: 'admin', status: 'uploading', expiresAtMs: Date.now() + 60000,
    });
    await uploadBytes(ref(context.storage(), final), pdf, { contentType: 'application/pdf' });
  });
  const admin = environment.authenticatedContext('admin');
  await assertSucceeds(uploadBytes(ref(admin.storage(), staging), pdf, { contentType: 'application/pdf' }));
  await assertSucceeds(getBytes(ref(admin.storage(), staging)));
  await assertFails(uploadBytes(ref(admin.storage(), staging), pdf, { contentType: 'text/html' }));
  await assertFails(uploadBytes(ref(admin.storage(), staging), new Uint8Array(0), { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(admin.storage(), staging), new Uint8Array(20 * 1024 * 1024 + 1), { contentType: 'application/pdf' }));
  for (const context of [admin, environment.authenticatedContext('broker'), environment.authenticatedContext('owner'), environment.unauthenticatedContext()]) {
    await assertFails(getBytes(ref(context.storage(), final)));
    await assertFails(uploadBytes(ref(context.storage(), final), pdf, { contentType: 'application/pdf' }));
    await assertFails(deleteObject(ref(context.storage(), final)));
    await assertFails(getDoc(doc(context.firestore(), `agreementCopyUploads/${uploadId}`)));
    await assertFails(setDoc(doc(context.firestore(), `agreementCopyUploads/${uploadId}`), { status: 'completed' }));
  }
  for (const context of [environment.authenticatedContext('broker'), environment.unauthenticatedContext()]) {
    await assertFails(getBytes(ref(context.storage(), staging)));
    await assertFails(uploadBytes(ref(context.storage(), staging), pdf, { contentType: 'application/pdf' }));
  }
  for (const values of [{ status: 'completed' }, { status: 'uploading', expiresAtMs: Date.now() - 60000 }]) {
    await environment.withSecurityRulesDisabled(async context => updateDoc(doc(context.firestore(), `agreementCopyUploads/${uploadId}`), values));
    await assertFails(uploadBytes(ref(admin.storage(), staging), pdf, { contentType: 'application/pdf' }));
  }
});

test('approval records expose only broker status; secrets, consent and rounds cannot be forged or read by clients', async () => {
  const id = 'approval-rules-test';
  await environment.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    await setDoc(doc(database, `agreementInvitations/${id}`), { brokerUid: 'broker', agreementId: 'test', status: 'agreed' });
    await setDoc(doc(database, `agreementInvitationSecrets/${id}`), { token: 'PRIVATE TEST TOKEN' });
    await setDoc(doc(database, `agreementApprovalRounds/${id}`), { replies: { owner: { status: 'agreed' } } });
    await setDoc(doc(database, `agreementApprovalHeads/${id}`), { revision: 1 });
  });
  await assertSucceeds(getDoc(doc(environment.authenticatedContext('broker').firestore(), `agreementInvitations/${id}`)));
  for (const context of [environment.authenticatedContext('broker'), environment.authenticatedContext('second-broker'),
    environment.authenticatedContext('admin'), environment.authenticatedContext('owner'), environment.unauthenticatedContext()]) {
    if (context !== undefined) {
      for (const collection of ['agreementInvitationSecrets', 'agreementApprovalRounds', 'agreementApprovalHeads']) {
        await assertFails(getDoc(doc(context.firestore(), `${collection}/${id}`)));
        await assertFails(setDoc(doc(context.firestore(), `${collection}/${id}`), { status: 'agreed' }));
      }
      await assertFails(updateDoc(doc(context.firestore(), `agreementInvitations/${id}`), { status: 'agreed' }));
    }
  }
  for (const uid of ['second-broker', 'pending', 'paused', 'owner']) {
    await assertFails(getDoc(doc(environment.authenticatedContext(uid).firestore(), `agreementInvitations/${id}`)));
  }
});

test('repair issue creation is agreement-bound and participants cannot invent approvals', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    await setDoc(doc(database, 'users/issue-tenant'), { roles: ['tenant'] });
    await setDoc(doc(database, 'users/issue-owner'), { roles: ['owner'] });
    await setDoc(doc(database, 'agreements/issue-home'), { participantUids: ['issue-tenant', 'issue-owner'], propertyAddress: 'Rules Test Home' });
  });
  const tenant = environment.authenticatedContext('issue-tenant').firestore();
  const values = { agreementId: 'issue-home', propertyAddress: 'Rules Test Home', participantUids: ['issue-tenant', 'issue-owner'], createdBy: 'issue-tenant', category: 'Water', title: 'Water problem', description: 'The kitchen tap is leaking.', status: 'open', createdAt: serverTimestamp(), updatedAt: serverTimestamp() };
  const reference = doc(tenant, 'issues/valid-repair');
  await assertSucceeds(setDoc(reference, values));
  await assertSucceeds(getDoc(doc(environment.authenticatedContext('issue-owner').firestore(), 'issues/valid-repair')));
  for (const [number, change] of [{ agreementId: 'missing-home' }, { participantUids: ['issue-tenant', 'stranger'] }, { propertyAddress: 'Forged Home' }, { status: 'approved' }, { amountPaise: 200000 }, { category: 'Unknown' }, { description: 'short' }, { createdBy: 'issue-owner' }].entries()) {
    await assertFails(setDoc(doc(tenant, `issues/invalid-repair-${number}`), { ...values, ...change }));
  }
  await assertFails(updateDoc(reference, { status: 'approved', amountPaise: 200000 }));
  await assertFails(setDoc(doc(environment.unauthenticatedContext().firestore(), 'issues/anonymous-repair'), values));
  await assertFails(getDoc(doc(environment.authenticatedContext('other').firestore(), 'issues/valid-repair')));
  await assertFails(updateDoc(doc(environment.authenticatedContext('admin').firestore(), 'issues/valid-repair'), { status: 'in_progress' }));
  await assertFails(setDoc(doc(environment.authenticatedContext('admin').firestore(), 'issues/admin-photo-repair'), { title: 'Broken tap', description: 'Created from photo check fixture', propertyId: 'fixture', propertyAddress: 'Rules Test Home', participantUids: ['issue-tenant', 'issue-owner'], sourcePhotoPath: 'photoChecks/fixture', status: 'open', createdBy: 'admin', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
});

test('private owner can upload, read, replace and delete', async () => {
  const file = ref(environment.authenticatedContext('broker').storage(), path);
  await assertSucceeds(uploadBytes(file, pdf, { contentType: 'application/pdf' }));
  await assertSucceeds(getBytes(file));
  await assertSucceeds(uploadBytes(file, pdf, { contentType: 'application/pdf' }));
  await assertSucceeds(deleteObject(file));
});

test('repair upload staging is actor/grant/expiry-bound and final snapshots require the authenticated callable', async () => {
  const reportId = 'c'.repeat(32);
  const image = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
  await environment.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    await setDoc(doc(database, 'users/photo-tenant'), { roles: ['tenant'] });
    await setDoc(doc(database, 'users/photo-owner'), { roles: ['owner'] });
    await setDoc(doc(database, 'agreements/photo-home'), { participantUids: ['photo-tenant', 'photo-owner'] });
    await setDoc(doc(database, `repairReportUploads/${reportId}`), { agreementId: 'photo-home', createdBy: 'photo-tenant', status: 'uploading', expiresAtMs: Date.now() + 60000 });
  });
  const stagingPath = `repairUploads/photo-tenant/${reportId}/0`;
  const tenant = environment.authenticatedContext('photo-tenant');
  await assertSucceeds(uploadBytes(ref(tenant.storage(), stagingPath), image, { contentType: 'image/png' }));
  await assertSucceeds(getBytes(ref(tenant.storage(), stagingPath)));
  for (const context of [environment.authenticatedContext('photo-owner'), environment.authenticatedContext('other'), environment.unauthenticatedContext()]) {
    await assertFails(getBytes(ref(context.storage(), stagingPath)));
    await assertFails(uploadBytes(ref(context.storage(), stagingPath), image, { contentType: 'image/png' }));
  }
  for (const [index, contentType, bytes] of [['4', 'image/png', image], ['1', 'application/pdf', image], ['1', 'image/png', new Uint8Array(0)]]) {
    await assertFails(uploadBytes(ref(tenant.storage(), `repairUploads/photo-tenant/${reportId}/${index}`), bytes, { contentType }));
  }
  await assertFails(setDoc(doc(tenant.firestore(), `repairReportUploads/${reportId}`), { createdBy: 'photo-tenant' }));
  const canonicalPath = `issues/${reportId}/photos/0`;
  await assertFails(uploadBytes(ref(tenant.storage(), canonicalPath), image, { contentType: 'image/png' }));
  await environment.withSecurityRulesDisabled(async context => {
    await uploadBytes(ref(context.storage(), canonicalPath), image, { contentType: 'image/png' });
    await setDoc(doc(context.firestore(), `issues/${reportId}`), { agreementId: 'photo-home', participantUids: ['photo-tenant', 'photo-owner'] });
    await updateDoc(doc(context.firestore(), `repairReportUploads/${reportId}`), { status: 'submitted' });
  });
  await assertFails(getBytes(ref(tenant.storage(), canonicalPath)));
  await assertFails(getBytes(ref(environment.authenticatedContext('photo-owner').storage(), canonicalPath)));
  await assertFails(getBytes(ref(environment.authenticatedContext('admin').storage(), canonicalPath)));
  await assertFails(getBytes(ref(environment.authenticatedContext('other').storage(), canonicalPath)));
  await assertFails(deleteObject(ref(tenant.storage(), canonicalPath)));
  await assertFails(uploadBytes(ref(tenant.storage(), stagingPath), image, { contentType: 'image/png' }));
  await environment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'agreements/photo-home'), { participantUids: ['photo-owner'] });
  });
  await assertFails(getBytes(ref(tenant.storage(), canonicalPath)));
});

test('private document reads/writes/deletes reject other users and anonymous access', async () => {
  await uploadBytes(ref(environment.authenticatedContext('broker').storage(), path), pdf, { contentType: 'application/pdf' });
  for (const context of [environment.authenticatedContext('other'), environment.unauthenticatedContext()]) {
    const file = ref(context.storage(), path);
    await assertFails(getBytes(file));
    await assertFails(uploadBytes(file, pdf, { contentType: 'application/pdf' }));
    await assertFails(deleteObject(file));
  }
});

test('document MIME and inclusive 10 MB limit are server enforced', async () => {
  const storage = environment.authenticatedContext('broker').storage();
  await assertFails(uploadBytes(ref(storage, `${path}-invalid`), pdf, { contentType: 'text/html' }));
  await assertFails(uploadBytes(ref(storage, `${path}-empty`), new Uint8Array(0), { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(storage, `${path}-svg`), pdf, { contentType: 'image/svg+xml' }));
  await assertSucceeds(uploadBytes(ref(storage, `${path}-boundary`), new Uint8Array(10 * 1024 * 1024), { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(storage, `${path}-oversize`), new Uint8Array(10 * 1024 * 1024 + 1), { contentType: 'application/pdf' }));
});

function privateDraft(uid = 'broker') {
  return { brokerUid: uid, participantUids: [uid], status: 'draft', revision: 1,
    propertyAddress: 'Demo Test Towers 402', createdAt: Timestamp.fromMillis(1000) };
}

test('phone-only signup requires verified token phone, matching profile and no unverified email', async () => {
  const phone = '+919999999999';
  const database = environment.authenticatedContext('phone-new', {
    phone_number: phone, firebase: { sign_in_provider: 'phone' },
  }).firestore();
  const profile = { displayName: 'Demo Test User', phone, email: '', roles: ['broker'] };
  await assertSucceeds(setDoc(doc(database, 'users/phone-new'), profile));
  await assertFails(setDoc(doc(database, 'users/another'), profile));
  for (const [uid, change] of [['wrong-phone', { phone: '+919000000001' }], ['email-false', { email: 'unverified@example.com' }], ['admin-forged', { roles: ['admin'] }]]) {
    const own = environment.authenticatedContext(uid, { phone_number: phone, firebase: { sign_in_provider: 'phone' } }).firestore();
    await assertFails(setDoc(doc(own, `users/${uid}`), { ...profile, ...change }));
  }
  await assertFails(setDoc(doc(environment.authenticatedContext('no-phone').firestore(), 'users/no-phone'), profile));
});

test('only approved non-paused brokers create private drafts, never arbitrary participants or signing states', async () => {
  for (const uid of ['pending', 'paused']) {
    await assertFails(setDoc(doc(environment.authenticatedContext(uid).firestore(), `agreements/${uid}`), privateDraft(uid)));
  }
  const database = environment.authenticatedContext('broker').firestore();
  await assertSucceeds(setDoc(doc(database, 'agreements/private'), privateDraft()));
  await assertFails(setDoc(doc(database, 'agreements/linked'), { ...privateDraft(), participantUids: ['broker', 'other'] }));
  await assertFails(setDoc(doc(database, 'agreements/signed'), { ...privateDraft(), status: 'signed' }));
});

test('revision updates preserve ownership, creation time and server review fields', async () => {
  const database = environment.authenticatedContext('broker').firestore();
  const reference = doc(database, 'agreements/revisions');
  await assertSucceeds(setDoc(reference, privateDraft()));
  await assertSucceeds(updateDoc(reference, { revision: 2, propertyAddress: 'Changed Demo Test Towers 402' }));
  await assertFails(updateDoc(reference, { revision: 4 }));
  await assertFails(updateDoc(reference, { revision: 3, createdAt: Timestamp.fromMillis(2000) }));
  await assertFails(updateDoc(reference, { revision: 3, participantUids: ['broker', 'other'] }));
  await assertFails(updateDoc(reference, { revision: 3, reviewDigest: 'forged' }));
});

test('new draft transactions can read an absent document without exposing another broker draft', async () => {
  const database = environment.authenticatedContext('broker').firestore();
  const reference = doc(database, 'agreements/new-transaction');
  await assertSucceeds(runTransaction(database, async transaction => {
    const previous = await transaction.get(reference);
    if (previous.exists()) throw new Error('Expected a new draft');
    transaction.set(reference, privateDraft());
  }));
  await assertFails(getDoc(doc(environment.authenticatedContext('other').firestore(), 'agreements/new-transaction')));
  await assertFails(getDoc(doc(environment.authenticatedContext('second-broker').firestore(), 'agreements/new-transaction')));
  for (const uid of ['pending', 'paused']) {
    await assertFails(getDoc(doc(environment.authenticatedContext(uid).firestore(), 'agreements/absent')));
  }
});

function progressValues(version = 1) {
  return { schemaVersion: 1, brokerUid: 'broker', version, stage: 'ownerPapers', person: 0,
    draft: { revision: 0, owners: [{ id: 'owner' }], tenants: [{ id: 'tenant' }] },
    inputs: { rent: '' }, createdAt: serverTimestamp(), updatedAt: serverTimestamp() };
}

test('unfinished progress persists privately, rejects stale versions and never grants completion', async () => {
  const database = environment.authenticatedContext('broker').firestore();
  const reference = doc(database, 'users/broker/draftProgress/unfinished');
  await assertSucceeds(setDoc(reference, progressValues()));
  await assertSucceeds(getDoc(reference));
  await assertSucceeds(updateDoc(reference, { version: 2, stage: 'tenantPapers', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(reference, { version: 2, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(reference, { version: 3, person: 1, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(reference, { version: 3, status: 'signed', updatedAt: serverTimestamp() }));
  for (const context of [environment.authenticatedContext('other'), environment.authenticatedContext('second-broker'), environment.authenticatedContext('admin'), environment.unauthenticatedContext()]) {
    const other = doc(context.firestore(), 'users/broker/draftProgress/unfinished');
    await assertFails(getDoc(other));
    await assertFails(updateDoc(other, { version: 3, updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(other));
  }
  for (const uid of ['pending', 'paused']) {
    await assertFails(setDoc(doc(environment.authenticatedContext(uid).firestore(), `users/${uid}/draftProgress/unfinished`), { ...progressValues(), brokerUid: uid }));
  }
  await assertSucceeds(deleteDoc(reference));
});

test('progress cannot resume reviewed agreements or overwrite a newer complete revision', async () => {
  const database = environment.authenticatedContext('broker').firestore();
  await assertFails(setDoc(doc(database, 'users/broker/draftProgress/reviewed'), progressValues()));
  await assertSucceeds(setDoc(doc(database, 'agreements/progress-complete'), privateDraft()));
  const reference = doc(database, 'users/broker/draftProgress/progress-complete');
  await assertFails(setDoc(reference, progressValues()));
  const values = progressValues();
  await assertSucceeds(setDoc(reference, { ...values, draft: { ...values.draft, revision: 1 } }));
});

test('review freezes client edits; even admin cannot mark signed or overwrite immutable evidence', async () => {
  const broker = environment.authenticatedContext('broker').firestore();
  const admin = environment.authenticatedContext('admin').firestore();
  await assertSucceeds(getDoc(doc(broker, 'agreements/reviewed/reviews/1')));
  await assertSucceeds(getDoc(doc(admin, 'agreements/reviewed/reviews/1')));
  await assertFails(getDoc(doc(environment.authenticatedContext('other').firestore(), 'agreements/reviewed/reviews/1')));
  await assertFails(updateDoc(doc(broker, 'agreements/reviewed'), { revision: 2, propertyAddress: 'Changed address' }));
  await assertFails(updateDoc(doc(admin, 'agreements/reviewed'), { status: 'signed' }));
  await assertFails(setDoc(doc(admin, 'agreements/reviewed/reviews/1'), { signable: true }));
  await assertFails(setDoc(doc(broker, 'agreements/reviewed/events/fake'), { action: 'signed' }));
});
