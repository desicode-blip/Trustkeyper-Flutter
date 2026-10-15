import { createHash, randomUUID } from 'node:crypto';
import { verifiedPhone } from './verified-phone.js';
import { approvalDigest, approvalRoundId } from './agreement-approvals.js';
import { reviewSnapshot } from './agreement-review.js';

export class AgreementCopyError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const safe = value => typeof value === 'string' && /^[\w-]{1,128}$/.test(value);
const hash = value => createHash('sha256').update(value).digest('hex');
const requireValue = (value, message, code = 'failed-precondition') => {
  if (!value) throw new AgreementCopyError(code, message);
};

export function createAgreementCopyService({ store, files, auth, now = Date.now, eventId = randomUUID }) {
  async function admin(transaction) {
    requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
    const profile = await transaction.get(`users/${auth.uid}`);
    requireValue(profile?.roles?.includes('admin') && profile.paused !== true,
      'Only the agreement team can publish a copy.', 'permission-denied');
  }
  async function context(transaction, agreementId, revision) {
    const agreement = await transaction.get(`agreements/${agreementId}`);
    requireValue(agreement && agreement.revision === revision && ['reviewed', 'signed_copy_received'].includes(agreement.status),
      'Review this exact agreement version before publishing a copy.');
    const snapshot = reviewSnapshot(agreement);
    const digest = approvalDigest(snapshot);
    requireValue(agreement.reviewDigest === digest && agreement.lastReviewRevision === revision,
      'The reviewed terms changed. Request a new review.');
    const round = await transaction.get(`agreementApprovalRounds/${approvalRoundId(agreementId, revision)}`);
    const people = [...snapshot.owners.map(person => ({ ...person, role: 'owner' })),
      ...snapshot.tenants.map(person => ({ ...person, role: 'tenant' }))];
    requireValue(round?.digest === digest && people.every(person => {
      const reply = round.replies?.[person.id];
      return reply?.status === 'agreed' && reply.revision === revision && reply.digest === digest && safe(reply.actorUid);
    }), 'Every owner and tenant must reply to this exact version.');
    return { agreement, digest, people: people.map(person => ({
      id: person.id, name: person.name, role: person.role, phone: person.phone, uid: round.replies[person.id].actorUid,
    })) };
  }
  function audit(transaction, agreementId, revision, action, metadata) {
    const id = eventId();
    const record = { actorUid: auth.uid, revision, action, createdAtMs: now(), ...metadata };
    transaction.set(`agreements/${agreementId}/events/${id}`, record);
    transaction.set(`adminAuditLogs/${id}`, { ...record, targetPath: `agreements/${agreementId}` });
  }
  function summary(copy) {
    return { agreementId: copy.agreementId, revision: copy.revision, mode: copy.mode,
      name: copy.mode === 'demo' ? 'Demo agreement copy.pdf' : 'Signed agreement.pdf',
      partyCount: copy.people.length, startDateISO: copy.startDateISO ?? null,
      size: copy.file.size, sha256: copy.file.sha256, ready: true };
  }
  return {
    async begin(input) {
      const { agreementId, revision, operationId, mode, sha256, size, templateName } = input;
      requireValue(safe(agreementId) && safe(operationId) && Number.isSafeInteger(revision) && revision > 0 &&
        ['demo', 'externally_signed'].includes(mode) && /^[a-f0-9]{64}$/.test(sha256 ?? '') &&
        Number.isSafeInteger(size) && size > 0 && size <= 20 * 1024 * 1024,
      'Choose a PDF up to 20 MB and the saved version.', 'invalid-argument');
      if (mode === 'externally_signed') {
        requireValue(typeof templateName === 'string' && templateName.trim().length >= 5 && templateName.length <= 160 &&
          !/demo|software.test/i.test(templateName) && input.approvedOriginal === true &&
          input.allPartiesSigned === true && input.matchesReviewedTerms === true,
        'Confirm the approved original, all external signatures and exact reviewed terms. Demo PDFs must use demo mode.', 'invalid-argument');
      }
      const id = hash(JSON.stringify([auth?.uid, agreementId, revision, operationId]));
      const payloadHash = hash(JSON.stringify([mode, sha256, size, templateName?.trim() ?? '',
        input.approvedOriginal === true, input.allPartiesSigned === true, input.matchesReviewedTerms === true]));
      return store.transaction(async transaction => {
        await admin(transaction);
        const current = await context(transaction, agreementId, revision);
        const previous = await transaction.get(`agreementCopyUploads/${id}`);
        if (previous) {
          requireValue(previous.payloadHash === payloadHash, 'Retry the same selected file and confirmations.', 'aborted');
          requireValue(previous.status === 'completed' || previous.expiresAtMs > now(), 'This upload expired. Start again.');
          return { uploadId: id, path: previous.path, completed: previous.status === 'completed' };
        }
        requireValue(!current.agreement.agreementCopy || current.agreement.agreementCopy.mode === 'demo' && mode === 'externally_signed',
          'This version already has a published copy. A completed external copy cannot be overwritten.');
        const path = `agreementCopyUploads/${auth.uid}/${id}/agreement.pdf`;
        transaction.set(`agreementCopyUploads/${id}`, { agreementId, revision, adminUid: auth.uid,
          mode, sha256, size, templateName: templateName?.trim() ?? '', digest: current.digest, payloadHash,
          status: 'uploading', path, createdAtMs: now(), expiresAtMs: now() + 15 * 60000,
          attestation: mode === 'demo' ? null : { approvedOriginal: true, allPartiesSigned: true, matchesReviewedTerms: true } });
        return { uploadId: id, path, completed: false };
      });
    },
    async complete({ uploadId }) {
      requireValue(/^[a-f0-9]{64}$/.test(uploadId ?? ''), 'Invalid upload.', 'invalid-argument');
      async function check(transaction) {
        await admin(transaction);
        const upload = await transaction.get(`agreementCopyUploads/${uploadId}`);
        requireValue(upload?.adminUid === auth.uid, 'This upload is unavailable.', 'permission-denied');
        const current = await context(transaction, upload.agreementId, upload.revision);
        requireValue(current.digest === upload.digest, 'The agreement changed while uploading.');
        if (upload.status === 'completed') {
          requireValue(current.agreement.agreementCopy?.uploadId === uploadId, 'This copy was superseded.');
        } else {
          requireValue(upload.status === 'uploading' && upload.expiresAtMs > now(), 'This upload expired. Start again.');
          requireValue(!current.agreement.agreementCopy || current.agreement.agreementCopy.mode === 'demo' && upload.mode === 'externally_signed',
            'Another copy was published. Reopen the agreement.');
        }
        return { upload, ...current };
      }
      const initial = await store.transaction(check);
      if (initial.upload.status === 'completed') return summary(initial.agreement.agreementCopy);
      const file = await files.snapshot(initial.upload, uploadId);
      requireValue(file.sha256 === initial.upload.sha256 && file.size === initial.upload.size, 'The selected PDF changed. Start again.');
      const saved = await store.transaction(async transaction => {
        const current = await check(transaction);
        if (current.upload.status === 'completed') return summary(current.agreement.agreementCopy);
        const copy = { agreementId: current.upload.agreementId, revision: current.upload.revision,
          uploadId, mode: current.upload.mode, digest: current.digest, file,
          publishedAtMs: now(), receivedBy: auth.uid, source: 'manual_external_portal',
          templateName: current.upload.templateName, attestation: current.upload.attestation,
          startDateISO: current.agreement.startDateISO,
          people: current.people };
        const identities = [...new Set(copy.people.map(person => person.uid))];
        const profiles = copy.mode === 'externally_signed'
          ? await Promise.all(identities.map(uid => transaction.get(`users/${uid}`))) : [];
        transaction.update(`agreements/${copy.agreementId}`, { agreementCopy: copy,
          ...(copy.mode === 'externally_signed' ? { status: 'signed_copy_received',
            participantUids: [...new Set([current.agreement.brokerUid, ...copy.people.map(person => person.uid)])] } : {}),
          updatedAtMs: now() });
        if (copy.mode === 'externally_signed') {
          for (const [index, uid] of identities.entries()) {
            const profile = profiles[index];
            const people = copy.people.filter(person => person.uid === uid);
            const roles = people.map(person => person.role);
            if (profile) {
              transaction.update(`users/${uid}`, { roles: [...new Set([...(profile.roles ?? []), ...roles])], updatedAtMs: now() });
            } else {
              transaction.set(`users/${uid}`, { phone: people[0].phone, displayName: people[0].name,
                email: '', roles: [...new Set(roles)], createdAtMs: now(), updatedAtMs: now() });
            }
          }
        }
        transaction.update(`agreementCopyUploads/${uploadId}`, { status: 'completed', completedAtMs: now() });
        audit(transaction, copy.agreementId, copy.revision, 'agreement.copy_published', {
          uploadId, mode: copy.mode, sha256: file.sha256, digest: current.digest,
        });
        return summary(copy);
      });
      await files.cleanup(initial.upload).catch(() => {});
      return saved;
    },
    async read({ agreementId, revision }) {
      requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
      requireValue(safe(agreementId) && Number.isSafeInteger(revision), 'Open a saved agreement.', 'invalid-argument');
      async function authorized(transaction) {
        const profile = await transaction.get(`users/${auth.uid}`);
        requireValue(profile?.paused !== true, 'This account is paused.', 'permission-denied');
        const agreement = await transaction.get(`agreements/${agreementId}`);
        const copy = agreement?.agreementCopy;
        requireValue(agreement?.revision === revision && copy?.revision === revision,
          'Your agreement copy is not ready yet.', 'not-found');
        const allowed = profile?.roles?.includes('admin') ||
          auth.uid === agreement.brokerUid && profile?.roles?.includes('broker') && profile.approvalStatus === 'approved' ||
          copy.people.some(person => person.uid === auth.uid && verifiedPhone(auth) === person.phone);
        requireValue(allowed, 'This private agreement belongs to its verified participants.', 'permission-denied');
        return copy;
      }
      const copy = await store.transaction(authorized);
      const base64 = await files.read(copy.file);
      const current = await store.transaction(authorized);
      requireValue(current.uploadId === copy.uploadId && current.file.generation === copy.file.generation &&
        current.file.sha256 === copy.file.sha256, 'The agreement copy changed. Reopen it.', 'aborted');
      return { ...summary(copy), base64 };
    },
  };
}
