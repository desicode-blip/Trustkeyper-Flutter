import { createHash } from 'node:crypto';
import { verifiedPhone } from './verified-phone.js';

export class AgreementImportError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const requireValue = (condition, message, code = 'failed-precondition') => {
  if (!condition) throw new AgreementImportError(code, message);
};
const safe = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const digest = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const maxBytes = 20 * 1024 * 1024;
const stages = ['received', 'stamp_preparing', 'ready_to_sign', 'signing', 'completed'];

export function validateImportFiles(value) {
  requireValue(Array.isArray(value) && value.length > 0 && value.length <= 40,
    'Add one PDF or one photo for each page.', 'invalid-argument');
  const files = value.map(file => {
    requireValue(file && ['application/pdf', 'image/jpeg', 'image/png'].includes(file.contentType) &&
      Number.isSafeInteger(file.size) && file.size > 0 && file.size <= maxBytes && safe(file.sha256),
    'Choose readable JPG, PNG or PDF pages up to 20 MB in total.', 'invalid-argument');
    return { contentType: file.contentType, size: file.size, sha256: file.sha256 };
  });
  requireValue(files.reduce((total, file) => total + file.size, 0) <= maxBytes &&
    (!files.some(file => file.contentType === 'application/pdf') || files.length === 1),
  'Use a single PDF, or photos only. Keep the total within 20 MB.', 'invalid-argument');
  requireValue(new Set(files.map(file => file.sha256)).size === files.length,
    'The same page was added twice. Remove the duplicate.', 'invalid-argument');
  return files;
}

export function validateImportSigners(value) {
  requireValue(Array.isArray(value) && value.length >= 2 && value.length <= 40,
    'Add everyone who will sign, including an owner and a tenant.', 'invalid-argument');
  const signers = value.map(person => {
    const name = typeof person?.name === 'string' ? person.name.trim() : '';
    const phone = typeof person?.phone === 'string' ? person.phone.replace(/[\s()-]/g, '') : '';
    requireValue(name.length >= 2 && name.length <= 100 && /^\+[1-9]\d{7,14}$/.test(phone) &&
      ['owner', 'tenant', 'witness'].includes(person.role),
    'Give each signer a name, role and complete mobile number.', 'invalid-argument');
    return { name, phone, role: person.role };
  });
  requireValue(signers.some(person => person.role === 'owner') && signers.some(person => person.role === 'tenant') &&
    new Set(signers.map(person => person.phone)).size === signers.length,
  'Add at least one owner and tenant, with a different number for each signer.', 'invalid-argument');
  return signers;
}

export function createAgreementImportService({ auth, store, files, now = Date.now }) {
  async function profile(transaction, admin = false) {
    requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
    const person = await transaction.get(`users/${auth.uid}`);
    requireValue(person && person.paused !== true && (admin ? person.roles?.includes('admin') :
      person.roles?.includes('broker') && person.approvalStatus === 'approved' && verifiedPhone(auth) === person.phone),
    admin ? 'Only the active TrustKeyper team can update signing progress.' : 'An approved, phone-verified broker is required.',
    'permission-denied');
    return person;
  }
  async function access(transaction, requestId, admin = false) {
    requireValue(safe(requestId), 'Choose a saved signing request.', 'invalid-argument');
    const person = await profile(transaction, admin);
    const request = await transaction.get(`agreementImports/${requestId}`);
    requireValue(request && (person.roles.includes('admin') || request.brokerUid === auth.uid),
      'This private agreement is not available to this account.', 'permission-denied');
    return request;
  }
  function event(transaction, requestId, revision, action, detail = {}) {
    const value = { actorUid: auth.uid, action, revision, ...detail, createdAtMs: now() };
    transaction.set(`agreementImports/${requestId}/events/${revision}`, value);
    transaction.set(`adminAuditLogs/import-${requestId}-${revision}`, value);
  }
  return {
    async begin(input) {
      requireValue(typeof input.operationId === 'string' && /^[a-f0-9]{32}$/.test(input.operationId),
        'Keep this form open and retry.', 'invalid-argument');
      const specs = validateImportFiles(input.files);
      const signers = validateImportSigners(input.signers);
      requireValue(input.pagesReviewed === true, 'Review every page before sending.', 'invalid-argument');
      const requestId = digest([auth?.uid, input.operationId]);
      const uploadId = digest([requestId, 'source']);
      const payloadDigest = digest([specs, signers, true]);
      return store.transaction(async transaction => {
        await profile(transaction);
        const existing = await transaction.get(`agreementImports/${requestId}`);
        const grant = await transaction.get(`agreementImportUploads/${uploadId}`);
        if (existing) {
          requireValue(existing.brokerUid === auth.uid && existing.payloadDigest === payloadDigest,
            'This send attempt belongs to different pages or people. Reopen it.', 'already-exists');
          requireValue(existing.status !== 'uploading' || grant?.expiresAtMs > now(),
            'The upload expired. Start a new send attempt.');
          return { requestId, uploadId, completed: existing.status !== 'uploading',
            paths: specs.map((_, index) => `agreementImportUploads/${auth.uid}/${uploadId}/${index}`) };
        }
        const limits = await transaction.get(`agreementImportLimits/${auth.uid}`);
        const count = limits?.windowEndsAtMs > now() ? limits.count : 0;
        requireValue(count < 20, 'Too many agreement requests. Try again in an hour.', 'resource-exhausted');
        transaction.set(`agreementImportLimits/${auth.uid}`, { count: count + 1,
          windowEndsAtMs: limits?.windowEndsAtMs > now() ? limits.windowEndsAtMs : now() + 3600000 });
        transaction.set(`agreementImports/${requestId}`, { brokerUid: auth.uid, purpose: 'sign_only',
          signers, payloadDigest, status: 'uploading', revision: 1, createdAtMs: now(), updatedAtMs: now() });
        transaction.set(`agreementImportUploads/${uploadId}`, { uid: auth.uid, requestId, kind: 'source',
          specs, status: 'uploading', expiresAtMs: now() + 3600000, payloadDigest });
        return { requestId, uploadId, completed: false,
          paths: specs.map((_, index) => `agreementImportUploads/${auth.uid}/${uploadId}/${index}`) };
      });
    },
    async complete({ uploadId }) {
      requireValue(safe(uploadId), 'Choose the current upload.', 'invalid-argument');
      const context = await store.transaction(async transaction => {
        requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
        const grant = await transaction.get(`agreementImportUploads/${uploadId}`);
        requireValue(grant?.uid === auth.uid, 'This upload belongs to another account.', 'permission-denied');
        const request = await access(transaction, grant.requestId, grant.kind === 'signed');
        if (grant.status === 'completed') return { grant, request, completed: true };
        requireValue(grant.status === 'uploading' && grant.expiresAtMs > now(), 'This upload expired. Reopen the request.');
        requireValue(grant.kind === 'source' ? request.status === 'uploading' :
          request.status === 'signing' && request.revision === grant.requestRevision,
        'Signing progress changed. Refresh before uploading.', 'aborted');
        return { grant, request, completed: false };
      });
      if (context.completed) return { requestId: context.grant.requestId, ready: true };
      const file = await files.snapshot(context.grant, uploadId);
      const result = await store.transaction(async transaction => {
        const grant = await transaction.get(`agreementImportUploads/${uploadId}`);
        const request = await access(transaction, context.grant.requestId, context.grant.kind === 'signed');
        requireValue(grant?.uid === auth.uid && grant.payloadDigest === context.grant.payloadDigest,
          'This upload changed. Reopen it.', 'aborted');
        if (grant.status === 'completed') return { requestId: grant.requestId, ready: true };
        requireValue(grant.expiresAtMs > now() && (grant.kind === 'source' ? request.status === 'uploading' :
          request.status === 'signing' && request.revision === grant.requestRevision),
        'Signing progress changed. Refresh before uploading.', 'aborted');
        requireValue(grant.kind !== 'signed' || file.sha256 !== request.sourceFile.sha256,
          'The original uploaded pages are not a completed signed agreement.', 'invalid-argument');
        const revision = request.revision + 1;
        transaction.update(`agreementImports/${grant.requestId}`, { revision,
          status: grant.kind === 'source' ? 'received' : 'completed',
          [grant.kind === 'source' ? 'sourceFile' : 'signedFile']: file,
          ...(grant.kind === 'source' ? { pageCount: file.pageCount } : { completedAtMs: now() }), updatedAtMs: now() });
        transaction.update(`agreementImportUploads/${uploadId}`, { status: 'completed' });
        event(transaction, grant.requestId, revision, grant.kind === 'source' ? 'signing_pages_received' : 'signed_original_published',
          { sha256: file.sha256, pageCount: file.pageCount,
            ...(grant.kind === 'signed' ? { originalChecked: true, allPartiesSigned: true, checkedByUid: grant.uid } : {}) });
        return { requestId: grant.requestId, ready: true };
      });
      await files.cleanup(context.grant, uploadId).catch(() => {});
      return result;
    },
    async list() {
      const person = await store.transaction(transaction => profile(transaction, true).catch(async error => {
        if (error.code !== 'permission-denied') throw error;
        return profile(transaction);
      }));
      const result = await store.list('agreementImports', person.roles.includes('admin') ? null : auth.uid, 100);
      return { requests: result.filter(item => item.status !== 'uploading').map(({ sourceFile, signedFile, payloadDigest, ...item }) =>
        ({ ...item, hasSource: !!sourceFile, hasSigned: !!signedFile })) };
    },
    async read({ requestId, signed = false }) {
      const request = await store.transaction(async transaction => {
        requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
        const person = await transaction.get(`users/${auth.uid}`);
        return access(transaction, requestId, person?.roles?.includes('admin') === true);
      });
      const file = signed ? request.signedFile : request.sourceFile;
      requireValue(file && (!signed || request.status === 'completed'), 'This copy is not ready.', 'not-found');
      return { requestId, signed, ...file, base64: await files.read(file) };
    },
    async record({ requestId, revision, status, reference, note }) {
      requireValue(Number.isSafeInteger(revision) && typeof reference === 'string' && reference.trim().length >= 3 &&
        reference.length <= 200 && typeof note === 'string' && note.length <= 1000,
      'Record the actual processing reference and a short note.', 'invalid-argument');
      return store.transaction(async transaction => {
        const request = await access(transaction, requestId, true);
        requireValue(request.revision === revision, 'Another team member updated this request. Refresh.', 'aborted');
        const current = stages.indexOf(request.status);
        requireValue(current >= 0 && current < 3 && stages[current + 1] === status,
          'Record the next actual stage. A signed original is required to finish.');
        transaction.update(`agreementImports/${requestId}`, { status, revision: revision + 1,
          processingReference: reference.trim(), teamNote: note.trim(), updatedAtMs: now() });
        event(transaction, requestId, revision + 1, status, { reference: reference.trim(), note: note.trim() });
        return { requestId, revision: revision + 1, status };
      });
    },
    async beginSigned({ requestId, revision, operationId, file, allPartiesSigned, originalChecked }) {
      const specs = validateImportFiles([file]);
      requireValue(specs[0].contentType === 'application/pdf' && allPartiesSigned === true && originalChecked === true &&
        typeof operationId === 'string' && /^[a-f0-9]{32}$/.test(operationId),
      'Review the genuine externally signed PDF and confirm all signatures and stamp details.', 'invalid-argument');
      const uploadId = digest([requestId, auth?.uid, operationId, 'signed']);
      const payloadDigest = digest([specs, requestId, revision]);
      return store.transaction(async transaction => {
        const request = await access(transaction, requestId, true);
        const existing = await transaction.get(`agreementImportUploads/${uploadId}`);
        if (existing) {
          requireValue(existing.uid === auth.uid && existing.payloadDigest === payloadDigest,
            'Use the same PDF for this retry.', 'already-exists');
          requireValue(existing.status === 'completed' || existing.expiresAtMs > now(), 'This upload expired.');
          return { uploadId, completed: existing.status === 'completed',
            paths: [`agreementImportUploads/${auth.uid}/${uploadId}/0`] };
        }
        requireValue(request.status === 'signing' && request.revision === revision,
          'Complete actual signing before publishing the original.', 'aborted');
        requireValue(specs[0].sha256 !== request.sourceFile.sha256,
          'Select the completed signed original, not the originally submitted pages.', 'invalid-argument');
        transaction.set(`agreementImportUploads/${uploadId}`, { uid: auth.uid, requestId, kind: 'signed',
          specs, requestRevision: revision, status: 'uploading', expiresAtMs: now() + 3600000, payloadDigest });
        return { uploadId, completed: false, paths: [`agreementImportUploads/${auth.uid}/${uploadId}/0`] };
      });
    },
  };
}
