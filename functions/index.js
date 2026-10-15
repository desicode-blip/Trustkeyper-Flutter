import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall, onRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { createRentPaymentService, PaymentError } from './rent-payments.js';
import { razorpayTestProvider } from './razorpay-test-provider.js';
import { createAgreementReviewService, ReviewError } from './agreement-review.js';
import { getStorage } from 'firebase-admin/storage';
import { createDocumentRequestService, DocumentRequestError } from './document-requests.js';
import { documentRequestFiles } from './document-request-files.js';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { deliverBrokerUpdate } from './broker-updates.js';
import { createRepairReportService, RepairError } from './repair-reports.js';
import { repairReportFiles } from './repair-report-files.js';
import { createRepairWorkflowService, RepairWorkflowError } from './repair-workflow.js';
import { repairCompletionFiles } from './repair-completion-files.js';
import { createAccountRoleService, AccountRoleError } from './account-roles.js';
import { createManagerCallbackService, ManagerCallbackError } from './manager-callbacks.js';
import { createInspectionService, InspectionError } from './property-inspections.js';
import { inspectionFiles } from './inspection-files.js';
import { createTenancyService, TenancyError } from './tenancy-workflow.js';
import { createMoveOutService, MoveOutError } from './move-out-workflow.js';
import { createAgreementRenewalService, RenewalError } from './agreement-renewals.js';
import { createAgreementApprovalService, ApprovalError } from './agreement-approvals.js';
import { createAgreementCopyService, AgreementCopyError } from './agreement-copies.js';
import { agreementCopyFiles } from './agreement-copy-files.js';
import { createAgreementImportService, AgreementImportError } from './agreement-imports.js';
import { agreementImportFiles } from './agreement-import-files.js';
import { createOwnerPropertyService, OwnerPropertyError } from './owner-properties.js';
import { createOwnerLifecycleService } from './owner-lifecycle.js';
import { ownerContractFiles } from './owner-contract-files.js';
import { ownerPropertyFiles } from './owner-property-files.js';
import { createTenantSetupService, TenantSetupError } from './tenant-setup.js';
import { createAccountProfileService, AccountProfileError } from './account-profile.js';
import { createAccountClosureService, AccountClosureError } from './account-closure.js';

initializeApp();

function accountStore() {
  const database = getFirestore();
  return {
    transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, data) => transaction.set(database.doc(path), data),
      update: (path, data) => transaction.update(database.doc(path), data),
      related: async (collection, field, uid, array) => {
        const query = database.collection(collection).where(field, array ? 'array-contains' : '==', uid).limit(1001);
        const snapshot = await transaction.get(query);
        if (snapshot.size > 1000) throw new AccountClosureError('failed-precondition', 'The team must review this account history before closure.');
        return snapshot.docs.map(document => document.data());
      },
    })),
    pending: async () => (await database.collection('accountClosures').where('status', 'in', ['closing', 'closed', 'restoring'])
      .limit(100).get()).docs.map(document => ({ uid: document.id, ...document.data() })),
  };
}
const accountIdentity = {
  read: uid => getAuth().getUser(uid),
  updateName: (uid, displayName) => getAuth().updateUser(uid, { displayName }),
  disable: uid => getAuth().updateUser(uid, { disabled: true }),
  enable: uid => getAuth().updateUser(uid, { disabled: false }),
  revoke: uid => getAuth().revokeRefreshTokens(uid),
};
async function accountAction(request, type, action) {
  try {
    const create = type === 'profile' ? createAccountProfileService : createAccountClosureService;
    return await create({ auth: request.auth, store: accountStore(), identity: accountIdentity })[action](request.data ?? {});
  } catch (error) {
    if (error instanceof AccountProfileError || error instanceof AccountClosureError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'Your account request could not be confirmed. Please retry.');
  }
}
const accountOptions = { region: 'asia-south1', invoker: 'public', maxInstances: 3, timeoutSeconds: 30 };
export const readAccountProfile = onCall(accountOptions, request => accountAction(request, 'profile', 'read'));
export const saveAccountProfile = onCall(accountOptions, request => accountAction(request, 'profile', 'save'));
export const readAccountClosure = onCall(accountOptions, request => accountAction(request, 'closure', 'read'));
export const closeAccount = onCall(accountOptions, request => accountAction(request, 'closure', 'close'));
export const listAccountClosures = onCall(accountOptions, request => accountAction(request, 'closure', 'list'));
export const finishAccountClosure = onCall(accountOptions, request => accountAction(request, 'closure', 'finish'));
export const restoreClosedAccount = onCall(accountOptions, request => accountAction(request, 'closure', 'restore'));

function tenantSetup(request) {
  const database = getFirestore();
  return createTenantSetupService({ auth: request.auth, store: {
    transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, data) => transaction.set(database.doc(path), data),
      update: (path, data) => transaction.update(database.doc(path), data),
    })),
    pending: async () => (await database.collection('tenantSetups').where('request.status', '==', 'pending')
      .limit(100).get()).docs.map(document => ({ id: document.id, ...document.data() })),
  } });
}
async function executeTenantSetup(request, action) {
  try { return await tenantSetup(request)[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof TenantSetupError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'Your confirmation could not be saved. Please try again.');
  }
}
const tenantSetupOptions = { region: 'asia-south1', invoker: 'public', maxInstances: 3, timeoutSeconds: 30 };
export const readTenantSetup = onCall(tenantSetupOptions, request => executeTenantSetup(request, 'read'));
export const recordTenantSetup = onCall(tenantSetupOptions, request => executeTenantSetup(request, 'record'));
export const listTenantSetupRequests = onCall(tenantSetupOptions, request => executeTenantSetup(request, 'list'));
export const resolveTenantSetupRequest = onCall(tenantSetupOptions, request => executeTenantSetup(request, 'resolve'));

function reviewService(request) {
  const database = getFirestore();
  return createAgreementReviewService({ uid: request.auth?.uid, store: {
    transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, data) => transaction.set(database.doc(path), data),
      update: (path, data) => transaction.update(database.doc(path), {
        ...data, updatedAt: FieldValue.serverTimestamp(),
      }),
    })),
  } });
}

async function executeReview(operation) {
  try {
    return await operation();
  } catch (error) {
    if (error instanceof ReviewError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'Review could not be saved. Reopen the record and try again.');
  }
}

const reviewOptions = { region: 'asia-south1', invoker: 'public', maxInstances: 3, timeoutSeconds: 30 };
export const requestAgreementReview = onCall(reviewOptions, request =>
  executeReview(() => reviewService(request).submit(request.data ?? {})));
export const recordAgreementReview = onCall(reviewOptions, request =>
  executeReview(() => reviewService(request).record(request.data ?? {})));

function documents(request) {
  const database = getFirestore();
  return createDocumentRequestService({ auth: request.auth,
    files: documentRequestFiles(database, getStorage().bucket('trustkeyper.firebasestorage.app')),
    store: { transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, data) => transaction.set(database.doc(path), data),
      update: (path, data) => transaction.update(database.doc(path), data),
    })) },
  });
}
async function executeDocuments(request, action) {
  try { return await documents(request)[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof DocumentRequestError) throw new HttpsError(error.code, error.message);
    console.error(JSON.stringify({ operation: action,
      code: Number.isSafeInteger(error.code) || typeof error.code === 'string' && /^[\w/-]{1,80}$/.test(error.code) ? error.code : 'internal',
      name: typeof error.name === 'string' && /^[\w-]{1,80}$/.test(error.name) ? error.name : 'redacted',
      locations: [...String(error.stack ?? '').matchAll(/\/workspace\/([\w@./-]+:\d+:\d+)/g)].slice(0, 4).map(match => match[1]),
      reason: typeof error.errors?.[0]?.reason === 'string' && /^[\w-]{1,80}$/.test(error.errors[0].reason) ? error.errors[0].reason : 'redacted' }));
    throw new HttpsError('internal', 'Document request failed. Check your connection and retry.');
  }
}
const documentOptions = { ...reviewOptions, timeoutSeconds: 120, memory: '256MiB' };
export const sendBrokerUpdatePush = onDocumentCreated({
  document: 'users/{brokerUid}/updates/{updateId}', region: 'asia-south1',
  retry: true, maxInstances: 3, timeoutSeconds: 120,
}, async event => {
  const database = getFirestore();
  await deliverBrokerUpdate({ messaging: getMessaging(), store: {
    transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      update: (path, values) => transaction.update(database.doc(path), values),
    })),
    devices: async uid => (await database.collection(`users/${uid}/pushDevices`).orderBy('updatedAt', 'desc').limit(100).get()).docs
      .map(document => ({ ...document.data(), id: document.id, updatedAtMs: document.data().updatedAt?.toMillis() ?? 0 })),
    update: (path, values) => database.doc(path).update(values),
    disableDevice: (uid, id) => database.doc(`users/${uid}/pushDevices/${id}`).update({ enabled: false }),
  } }, event.params.brokerUid, event.params.updateId);
});
async function executeAgreementImport(request, action) {
  const database = getFirestore();
  const service = createAgreementImportService({ auth: request.auth,
    files: agreementImportFiles(getStorage().bucket('trustkeyper.firebasestorage.app')),
    store: {
      list: async (collection, brokerUid, limit) => {
        let query = database.collection(collection);
        if (brokerUid) query = query.where('brokerUid', '==', brokerUid);
        const result = await query.orderBy('createdAtMs', 'desc').limit(limit).get();
        return result.docs.map(document => ({ ...document.data(), id: document.id }));
      },
      transaction: handler => database.runTransaction(transaction => handler({
        get: async path => (await transaction.get(database.doc(path))).data(),
        set: (path, data) => transaction.set(database.doc(path), data),
        update: (path, data) => transaction.update(database.doc(path), data),
      })),
    },
  });
  try { return await service[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof AgreementImportError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'This agreement could not be processed. Keep the selected pages and retry.');
  }
}
const importOptions = { ...documentOptions, cpu: 'gcf_gen1', memory: '512MiB', concurrency: 1 };
export const beginAgreementImport = onCall(importOptions, request => executeAgreementImport(request, 'begin'));
export const completeAgreementImport = onCall(importOptions, request => executeAgreementImport(request, 'complete'));
export const listAgreementImports = onCall(importOptions, request => executeAgreementImport(request, 'list'));
export const readAgreementImport = onCall(importOptions, request => executeAgreementImport(request, 'read'));
export const recordAgreementImport = onCall(importOptions, request => executeAgreementImport(request, 'record'));
export const beginSignedAgreementImport = onCall(importOptions, request => executeAgreementImport(request, 'beginSigned'));
async function executeOwnerProperty(request, action) {
  const database = getFirestore();
  const service = createOwnerPropertyService({ auth: request.auth,
    files: ownerPropertyFiles(getStorage().bucket('trustkeyper.firebasestorage.app')),
    store: {
      list: async (ownerUid, limit) => {
        let query = database.collection('ownerProperties');
        if (ownerUid) query = query.where('ownerUid', '==', ownerUid);
        return (await query.orderBy('updatedAtMs', 'desc').limit(limit).get()).docs.map(document => ({ ...document.data(), id: document.id }));
      },
      transaction: handler => database.runTransaction(transaction => handler({
        get: async path => (await transaction.get(database.doc(path))).data(),
        findAddress: async address => (await transaction.get(database.collection('properties').where('address', '==', address).limit(2)))
          .docs.map(document => ({ ...document.data(), id: document.id })),
        set: (path, data) => transaction.set(database.doc(path), data),
        update: (path, data) => transaction.update(database.doc(path), data),
      })),
    },
  });
  try { return await service[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof OwnerPropertyError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'Your property could not be saved. Keep this form open and retry.');
  }
}
export const listOwnerProperties = onCall(importOptions, request => executeOwnerProperty(request, 'list'));
export const readOwnerProperty = onCall(importOptions, request => executeOwnerProperty(request, 'read'));
export const saveOwnerPropertyStep = onCall(importOptions, request => executeOwnerProperty(request, 'save'));
export const beginOwnerPropertyPhotos = onCall(importOptions, request => executeOwnerProperty(request, 'beginPhotos'));
export const completeOwnerPropertyPhotos = onCall(importOptions, request => executeOwnerProperty(request, 'completePhotos'));
export const readOwnerPropertyPhoto = onCall(importOptions, request => executeOwnerProperty(request, 'readPhoto'));
export const requestOwnerPropertyPlan = onCall(importOptions, request => executeOwnerProperty(request, 'requestPlan'));
export const recordOwnerPropertyCheck = onCall(importOptions, request => executeOwnerProperty(request, 'recordCheck'));
async function executeOwnerLifecycle(request, action) {
  const database = getFirestore();
  const bucket = getStorage().bucket('trustkeyper.firebasestorage.app');
  const service = createOwnerLifecycleService({ auth: request.auth,
    files: ownerContractFiles(bucket), photos: ownerPropertyFiles(bucket), store: {
      transaction: handler => database.runTransaction(transaction => handler({
        get: async path => (await transaction.get(database.doc(path))).data(),
        set: (path, data) => transaction.set(database.doc(path), data),
        update: (path, data) => transaction.update(database.doc(path), data),
      })),
    } });
  try { return await service[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof OwnerPropertyError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'This property action was not confirmed. Refresh and retry.');
  }
}
export const beginOwnerContractUpload = onCall(importOptions, request => executeOwnerLifecycle(request, 'beginContract'));
export const completeOwnerContractUpload = onCall(importOptions, request => executeOwnerLifecycle(request, 'completeContract'));
export const readOwnerContract = onCall(importOptions, request => executeOwnerLifecycle(request, 'readContract'));
export const changeOwnerPropertyLifecycle = onCall(importOptions, request => executeOwnerLifecycle(request, 'change'));
export const readPublicOwnerListing = onCall(importOptions, request => executeOwnerLifecycle(request, 'readPublic'));
export const enquireOwnerListing = onCall(importOptions, request => executeOwnerLifecycle(request, 'enquire'));
async function executeTenancy(request, action) {
  const database = getFirestore();
  const service = createTenancyService({ auth: request.auth, store: {
    transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      list: async (path, limit) => (await transaction.get(database.collection(path).orderBy('createdAt', 'desc').limit(limit))).docs
        .map(document => ({ ...document.data(), id: document.id })),
      set: (path, data) => transaction.set(database.doc(path), data),
      update: (path, data) => transaction.update(database.doc(path), data),
    })),
  } });
  try { return await service[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof TenancyError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'This home could not be updated. Keep the form open and retry.');
  }
}
export const readTenancy = onCall(documentOptions, request => executeTenancy(request, 'read'));
export const recordTenancyAction = onCall(documentOptions, request => executeTenancy(request, 'record'));
export const issueKeyConfirmationCode = onCall(reviewOptions, request => executeTenancy(request, 'issueCode'));
async function executeMoveOut(request, action) {
  const database = getFirestore();
  const store = { transaction: handler => database.runTransaction(transaction => handler({
    get: async path => (await transaction.get(database.doc(path))).data(),
    set: (path, data) => transaction.set(database.doc(path), data),
    update: (path, data) => transaction.update(database.doc(path), data),
  })) };
  const service = createMoveOutService({ auth: request.auth, store,
    tenancy: createTenancyService({ auth: request.auth, store }) });
  try { return await service[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof MoveOutError || error instanceof TenancyError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'Move-out could not be updated. Keep this form open and retry.');
  }
}
export const readMoveOut = onCall(documentOptions, request => executeMoveOut(request, 'read'));
export const recordMoveOutAction = onCall(documentOptions, request => executeMoveOut(request, 'record'));
export const issueKeyReturnCode = onCall({ ...reviewOptions, cpu: 'gcf_gen1', concurrency: 1, memory: '256MiB' },
  request => executeMoveOut(request, 'issueCode'));
export const createAgreementRenewal = onCall(reviewOptions, async request => {
  const database = getFirestore();
  const service = createAgreementRenewalService({ auth: request.auth, store: {
    timestamp: () => FieldValue.serverTimestamp(),
    transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, data) => transaction.set(database.doc(path), data),
      update: (path, data) => transaction.update(database.doc(path), data),
    })),
  } });
  try { return await service.create(request.data ?? {}); }
  catch (error) {
    if (error instanceof RenewalError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'Renewal could not be saved. Keep this page open and retry.');
  }
});
async function executeInspection(request, action) {
  const database = getFirestore();
  const service = createInspectionService({ auth: request.auth,
    files: inspectionFiles(getStorage().bucket('trustkeyper.firebasestorage.app')),
    store: { timestamp: () => FieldValue.serverTimestamp(),
      transaction: handler => database.runTransaction(transaction => handler({
        get: async path => (await transaction.get(database.doc(path))).data(),
        list: async (path, limit) => (await transaction.get(database.collection(path).orderBy('createdAt', 'desc').limit(limit)))
          .docs.map(document => ({ ...document.data(), id: document.id })),
        set: (path, data) => transaction.set(database.doc(path), data),
        update: (path, data) => transaction.update(database.doc(path), data),
      })) },
  });
  try { return await service[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof InspectionError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'Photo check could not be completed. Keep this screen open and retry.');
  }
}
export const listPropertyInspections = onCall(documentOptions, request => executeInspection(request, 'list'));
export const beginPropertyInspection = onCall(documentOptions, request => executeInspection(request, 'begin'));
export const submitPropertyInspection = onCall(documentOptions, request => executeInspection(request, 'submit'));
export const readPropertyInspectionPhoto = onCall(documentOptions, request => executeInspection(request, 'readPhoto'));
export const reviewPropertyInspection = onCall(documentOptions, request => executeInspection(request, 'review'));
export const createDocumentRequest = onCall(documentOptions, request => executeDocuments(request, 'create'));
export const readDocumentRequest = onCall(documentOptions, request => executeDocuments(request, 'read'));
export const recordDocumentRequest = onCall(documentOptions, request => executeDocuments(request, 'record'));
export const beginDocumentUpload = onCall(documentOptions, request => executeDocuments(request, 'begin'));
export const completeDocumentUpload = onCall(documentOptions, request => executeDocuments(request, 'complete'));

async function executeRepair(request, action) {
  const database = getFirestore();
  const service = createRepairReportService({ auth: request.auth,
    files: repairReportFiles(getStorage().bucket('trustkeyper.firebasestorage.app')),
    store: { timestamp: () => FieldValue.serverTimestamp(),
      transaction: handler => database.runTransaction(transaction => handler({
        get: async path => (await transaction.get(database.doc(path))).data(),
        set: (path, data) => transaction.set(database.doc(path), data),
        update: (path, data) => transaction.update(database.doc(path), data),
      })),
    },
  });
  try { return await service[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof RepairError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', action === 'readPhoto'
      ? 'This private photo could not be opened. Try again.'
      : 'Report could not be saved. Keep this form open and retry.');
  }
}
export const beginRepairReport = onCall(documentOptions, request => executeRepair(request, 'begin'));
export const submitRepairReport = onCall(documentOptions, request => executeRepair(request, 'submit'));
export const readRepairPhoto = onCall({ ...documentOptions, concurrency: 1 }, request => executeRepair(request, 'readPhoto'));

async function executeRepairWorkflow(request, action) {
  const database = getFirestore();
  const service = createRepairWorkflowService({ auth: request.auth,
    files: repairCompletionFiles(getStorage().bucket('trustkeyper.firebasestorage.app')),
    store: { timestamp: () => FieldValue.serverTimestamp(),
      transaction: handler => database.runTransaction(transaction => handler({
        get: async path => (await transaction.get(database.doc(path))).data(),
        set: (path, data) => transaction.set(database.doc(path), data),
        update: (path, data) => transaction.update(database.doc(path), data),
      })),
    },
  });
  try { return await service[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof RepairWorkflowError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'This repair could not be saved. Keep the page open and retry.');
  }
}
export const readRepair = onCall(documentOptions, request => executeRepairWorkflow(request, 'read'));
export const createInspectionRepair = onCall(documentOptions, request => executeRepairWorkflow(request, 'fromPhoto'));
export const recordRepairQuote = onCall(documentOptions, request => executeRepairWorkflow(request, 'quote'));
export const approveRepairQuote = onCall(documentOptions, request => executeRepairWorkflow(request, 'approve'));
export const scheduleRepairVisit = onCall(documentOptions, request => executeRepairWorkflow(request, 'schedule'));
export const beginRepairCompletion = onCall(documentOptions, request => executeRepairWorkflow(request, 'beginCompletion'));
export const completeRepair = onCall({ ...documentOptions, concurrency: 1 }, request => executeRepairWorkflow(request, 'complete'));
export const confirmRepairOutcome = onCall(documentOptions, request => executeRepairWorkflow(request, 'confirm'));
export const readRepairEvidence = onCall({ ...documentOptions, concurrency: 1 }, request => executeRepairWorkflow(request, 'readFile'));

async function executeAccountRole(request, action) {
  const database = getFirestore();
  const service = createAccountRoleService({ auth: request.auth, store: {
    transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, data) => transaction.set(database.doc(path), data),
      update: (path, data) => transaction.update(database.doc(path), data),
    })),
  } });
  try { return await service[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof AccountRoleError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'This role could not be opened. Retry without logging out.');
  }
}
export const readAccountRoles = onCall(reviewOptions, request => executeAccountRole(request, 'read'));
export const selectAccountRole = onCall(reviewOptions, request => executeAccountRole(request, 'select'));
export const addAccountRole = onCall(reviewOptions, request => executeAccountRole(request, 'add'));

async function executeManagerCallback(request, action) {
  const database = getFirestore();
  const service = createManagerCallbackService({ auth: request.auth, phoneForUser: async uid => (await getAuth().getUser(uid)).phoneNumber ?? null, store: {
    transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      list: async (path, limit) => (await transaction.get(database.collection(path).orderBy('updatedAtMs', 'desc').limit(limit))).docs
        .map(document => ({ ...document.data(), id: document.id })),
      set: (path, data) => transaction.set(database.doc(path), data),
    })),
  } });
  try { return await service[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof ManagerCallbackError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'The callback could not be saved. Keep the page open and retry.');
  }
}
export const readManagerCallback = onCall(reviewOptions, request => executeManagerCallback(request, 'read'));
export const listManagerCallbacks = onCall(reviewOptions, request => executeManagerCallback(request, 'list'));
export const recordManagerCallback = onCall(reviewOptions, request => executeManagerCallback(request, 'record'));

async function executeApproval(request, action) {
  const database = getFirestore();
  const service = createAgreementApprovalService({ auth: request.auth, store: {
    transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, data) => transaction.set(database.doc(path), data),
      update: (path, data) => transaction.update(database.doc(path), data),
    })),
  } });
  try { return await service[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof ApprovalError || error instanceof ReviewError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'This reply could not be confirmed. Keep the page open and retry.');
  }
}
export const prepareAgreementApproval = onCall(reviewOptions, request => executeApproval(request, 'prepare'));
export const readAgreementApproval = onCall(reviewOptions, request => executeApproval(request, 'read'));
export const replyToAgreementApproval = onCall(reviewOptions, request => executeApproval(request, 'reply'));

async function executeAgreementCopy(request, action) {
  const database = getFirestore();
  const service = createAgreementCopyService({ auth: request.auth,
    files: agreementCopyFiles(getStorage().bucket('trustkeyper.firebasestorage.app')),
    store: { transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, data) => transaction.set(database.doc(path), data),
      update: (path, data) => transaction.update(database.doc(path), data),
    })) },
  });
  try { return await service[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof AgreementCopyError || error instanceof ReviewError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('internal', 'This agreement copy could not be confirmed. Keep the file selected and retry.');
  }
}
const agreementCopyOptions = { ...documentOptions, memory: '512MiB', concurrency: 1 };
export const beginAgreementCopyUpload = onCall(agreementCopyOptions, request => executeAgreementCopy(request, 'begin'));
export const completeAgreementCopyUpload = onCall(agreementCopyOptions, request => executeAgreementCopy(request, 'complete'));
export const readAgreementCopy = onCall(agreementCopyOptions, request => executeAgreementCopy(request, 'read'));

const razorpayTestId = defineSecret('RAZORPAY_TEST_KEY_ID');
const razorpayTestSecret = defineSecret('RAZORPAY_TEST_KEY_SECRET');
const razorpayWebhookSecret = defineSecret('RAZORPAY_TEST_WEBHOOK_SECRET');
function payments(request) {
  const database = getFirestore();
  return createRentPaymentService({ auth: request.auth,
    provider: razorpayTestProvider(razorpayTestId.value(), razorpayTestSecret.value()),
    store: { transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, data) => transaction.set(database.doc(path), data),
      update: (path, data) => transaction.update(database.doc(path), data),
    })) },
  });
}
async function executePayment(request, action) {
  try { return await payments(request)[action](request.data ?? {}); }
  catch (error) {
    if (error instanceof PaymentError) throw new HttpsError(error.code, error.message);
    throw new HttpsError('unavailable', 'Payment status could not be confirmed. Check status before trying another payment.');
  }
}
const paymentOptions = { ...documentOptions, secrets: [razorpayTestId, razorpayTestSecret] };
export const quoteRentPayment = onCall(paymentOptions, request => executePayment(request, 'quote'));
export const beginRentPayment = onCall(paymentOptions, request => executePayment(request, 'begin'));
export const confirmRentPayment = onCall(paymentOptions, request => executePayment(request, 'confirm'));
export const reconcileRentPayment = onCall(paymentOptions, request => executePayment(request, 'reconcile'));
export const razorpayTestWebhook = onRequest({ ...paymentOptions, secrets: [...paymentOptions.secrets, razorpayWebhookSecret] },
  async (request, response) => {
    if (request.method !== 'POST') { response.status(405).send('POST required'); return; }
    try {
      const result = await payments(request).webhook(request.rawBody, request.get('x-razorpay-signature'),
        razorpayWebhookSecret.value(), request.get('x-razorpay-event-id'));
      response.status(200).json(result);
    } catch (error) {
      response.status(error instanceof PaymentError && ['permission-denied', 'invalid-argument'].includes(error.code) ? 400 : 503)
        .json({ error: 'Webhook not confirmed' });
    }
  });
export { requestEmailOtp, verifyEmailOtp, requestProfileEmailOtp, verifyProfileEmailOtp,
  requestAccountEmailOtp, verifyAccountEmailOtp } from './email-functions.js';
