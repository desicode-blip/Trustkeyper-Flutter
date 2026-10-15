import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { verifiedPhone } from './verified-phone.js';
import { documentSubmittedUpdate } from './broker-updates.js';
import { linkedInProfile } from './linkedin-profile.js';

export class DocumentRequestError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

const kinds = { aadhaar: ['aadhaarFront', 'aadhaarBack'], pan: ['pan'], bank: ['bankProof'],
  linkedin: [], all: ['aadhaarFront', 'aadhaarBack', 'pan', 'bankProof'] };
const days = 7 * 24 * 60 * 60 * 1000;
const digest = value => createHash('sha256').update(value).digest('hex');
const openSlots = record => kinds[record.type].filter(kind =>
  !Object.entries(record.closedPapers ?? {}).some(([paper]) => kinds[paper]?.includes(kind)));
const safe = value => typeof value === 'string' && /^[\w-]{1,128}$/.test(value);
function requireValue(value, message = 'This link is old or unavailable. Ask the broker for a new link.', code = 'failed-precondition') {
  if (!value) throw new DocumentRequestError(code, message);
}
function sameDigest(first, second) {
  return typeof first === 'string' && typeof second === 'string' && /^[a-f0-9]{64}$/.test(first) && /^[a-f0-9]{64}$/.test(second) &&
    timingSafeEqual(Buffer.from(first, 'hex'), Buffer.from(second, 'hex'));
}
function identity(party) { return digest(JSON.stringify([party.id, party.name.trim(), party.phone, party.email ?? ''])); }

function bankInformation(value) {
  requireValue(value && typeof value === 'object' && !Array.isArray(value), 'Enter bank or UPI details.', 'invalid-argument');
  if (value.method === 'upi') {
    const upiId = typeof value.upiId === 'string' ? value.upiId.trim().toLowerCase() : '';
    requireValue(/^[a-z0-9._-]{2,128}@[a-z0-9.-]{2,64}$/.test(upiId), 'Enter a valid UPI ID.', 'invalid-argument');
    return { method: 'upi', upiId, verified: false };
  }
  const name = typeof value.name === 'string' ? value.name.trim() : '';
  const bank = typeof value.bank === 'string' ? value.bank.trim() : '';
  const accountNumber = typeof value.accountNumber === 'string' ? value.accountNumber.trim() : '';
  const ifsc = typeof value.ifsc === 'string' ? value.ifsc.trim().toUpperCase() : '';
  requireValue(value.method === 'bank' && ['savings', 'current'].includes(value.accountType) &&
    name.length >= 2 && name.length <= 120 && bank.length >= 2 && bank.length <= 80 &&
    /^\d{9,18}$/.test(accountNumber) && /^[A-Z]{4}0[A-Z0-9]{6}$/.test(ifsc),
    'Check the account name, bank, account number and IFSC.', 'invalid-argument');
  return { method: 'bank', name, bank, accountNumber, ifsc, accountType: value.accountType, verified: false };
}

export function createDocumentRequestService({ store, files, auth, now = Date.now,
  nonce = () => randomBytes(32).toString('base64url'), eventId = randomUUID }) {
  async function context(transaction, brokerUid, draftId, revision, partyId) {
    const profile = await transaction.get(`users/${brokerUid}`);
    const agreement = await transaction.get(`agreements/${draftId}`);
    const progress = await transaction.get(`users/${brokerUid}/draftProgress/${draftId}`);
    requireValue(profile?.roles?.includes('broker') && profile.approvalStatus === 'approved' && profile.paused !== true,
      'The broker cannot request documents right now.', 'permission-denied');
    requireValue(!agreement || agreement.brokerUid === brokerUid);
    const agreementAvailable = agreement && ['draft', 'review_requested', 'request_received', 'reviewed'].includes(agreement.status);
    let draft;
    if (agreementAvailable && agreement.revision === revision) draft = agreement;
    else if ((!agreement || agreement.status === 'draft' && agreement.revision === revision - 1) &&
      progress?.brokerUid === brokerUid && progress.draft?.revision === revision - 1) draft = progress.draft;
    requireValue(draft && typeof draft.propertyAddress === 'string');
    const owner = draft.owners?.find(party => party.id === partyId);
    const party = owner ?? draft.tenants?.find(person => person.id === partyId);
    requireValue(party && typeof party.name === 'string' && party.name.trim().length >= 2 &&
      typeof party.phone === 'string' && /^\+91\d{10}$/.test(party.phone));
    if (progress && agreement && progress.draft?.revision === agreement.revision) {
      const pending = [...(progress.draft.owners ?? []), ...(progress.draft.tenants ?? [])].find(person => person.id === partyId);
      requireValue(pending && identity(pending) === identity(party));
    }
    return { brokerName: profile.displayName?.trim() || 'Your broker', address: draft.propertyAddress.trim(),
      partyName: party.name.trim(), phone: party.phone, email: party.email ?? '',
      role: owner ? 'owner' : 'tenant', identity: identity(party) };
  }
  function requestId(input) {
    requireValue(auth?.uid && safe(input.draftId) && safe(input.partyId) && Number.isSafeInteger(input.revision) &&
      input.revision >= 1 && Object.hasOwn(kinds, input.type), 'Choose the person and document again.', 'invalid-argument');
    return digest(JSON.stringify([auth.uid, input.draftId, input.revision, input.partyId, input.type]));
  }
  function tokenId(token) {
    requireValue(typeof token === 'string' && /^[a-f0-9]{64}\.[\w-]{43}$/.test(token));
    return token.slice(0, 64);
  }
  async function active(transaction, token) {
    const id = tokenId(token);
    const record = await transaction.get(`brokerDocumentRequests/${id}`);
    requireValue(record && sameDigest(record.tokenHash, digest(token)) && record.expiresAtMs > now() &&
      record.status !== 'revoked' && (openSlots(record).length > 0 || record.type === 'linkedin' && !record.closedPapers?.linkedin));
    const current = await context(transaction, record.brokerUid, record.draftId, record.revision, record.partyId);
    requireValue(current.identity === record.identity);
    return { id, record, current };
  }
  function proof(record) {
    requireValue(auth?.uid && verifiedPhone(auth) === record.phone,
      'Verify the phone number on this request. No app installation is needed.', 'permission-denied');
  }
  function publicResult(id, record, current, verified) {
    return { requestId: id, type: record.type, slots: openSlots(record), status: record.status,
      expiresAtMs: record.expiresAtMs, phoneMasked: `+91 ••••••${record.phone.slice(-4)}`, verified,
      brokerName: current.brokerName, partyName: current.partyName, role: current.role,
      address: current.address, phone: current.phone, version: record.version,
      issuedAtMs: record.issuedAtMs, sharedAtMs: record.sharedAtMs ?? null,
      channel: record.channel ?? null, closedPapers: record.closedPapers ?? {},
      ...(verified ? { reason: record.reason ?? '', submission: record.submission ?? null } : {}) };
  }
  function audit(transaction, id, action, actorUid) {
    transaction.set(`brokerDocumentRequests/${id}/events/${eventId()}`, { action, actorUid, atMs: now() });
  }
  return {
    async create(input) {
      const id = requestId(input);
      requireValue(safe(input.operationId), 'Retry this link request.', 'invalid-argument');
      const token = `${id}.${nonce()}`;
      return store.transaction(async transaction => {
        const current = await context(transaction, auth.uid, input.draftId, input.revision, input.partyId);
        requireValue(input.type !== 'linkedin' || current.role === 'tenant', 'LinkedIn is optional for tenants only.', 'invalid-argument');
        const previous = await transaction.get(`brokerDocumentRequests/${id}`);
        const secret = await transaction.get(`documentRequestSecrets/${id}`);
        if (previous?.lastOperationId === input.operationId) {
          requireValue(secret && sameDigest(previous.tokenHash, digest(secret.token)));
          return { ...publicResult(id, previous, current, true), token: secret.token };
        }
        if (input.remind === true) {
          requireValue(previous && previous.identity === current.identity && previous.expiresAtMs > now() &&
            !['revoked', 'added', 'finalizing'].includes(previous.status) && secret && sameDigest(previous.tokenHash, digest(secret.token)));
          transaction.update(`brokerDocumentRequests/${id}`, { lastOperationId: input.operationId, reminderAtMs: now() });
          audit(transaction, id, 'reminder_prepared', auth.uid);
          return { ...publicResult(id, previous, current, true), token: secret.token };
        }
        const record = { brokerUid: auth.uid, draftId: input.draftId, revision: input.revision,
          partyId: input.partyId, type: input.type, ...current, status: 'created',
          tokenHash: digest(token), expiresAtMs: now() + days, issuedAtMs: now(),
          createdAtMs: previous?.createdAtMs ?? now(), lastOperationId: input.operationId,
          version: (previous?.version ?? 0) + 1, currentUploadId: null, currentUploadUid: null,
          ...(previous?.submission ? { submission: previous.submission } : {}) };
        transaction.set(`brokerDocumentRequests/${id}`, record);
        transaction.set(`documentRequestSecrets/${id}`, { token, expiresAtMs: record.expiresAtMs });
        audit(transaction, id, previous ? 'link_reissued' : 'link_created', auth.uid);
        return { ...publicResult(id, record, current, true), token };
      });
    },
    async read({ token }) {
      return store.transaction(async transaction => {
        const { id, record, current } = await active(transaction, token);
        const verified = Boolean(auth?.uid && verifiedPhone(auth) === record.phone);
        if (verified && ['created', 'shared'].includes(record.status)) {
          record.status = 'seen';
          transaction.update(`brokerDocumentRequests/${id}`, { status: 'seen', seenAtMs: now(), recipientUid: auth.uid });
          audit(transaction, id, 'verified_link_seen', auth.uid);
        }
        return publicResult(id, record, current, verified);
      });
    },
    async record({ token, requestId: idInput, action, reason, version, channel, paper, linkedInDetails }) {
      requireValue(['shared', 'unclear', 'revoked', 'paper_deleted', 'paper_taken_over', 'linkedin_added'].includes(action),
        'Choose a valid document action.', 'invalid-argument');
      requireValue(channel == null || ['WhatsApp', 'SMS', 'Email'].includes(channel),
        'Choose a valid sharing channel.', 'invalid-argument');
      const closing = ['paper_deleted', 'paper_taken_over'].includes(action);
      requireValue(!closing || ['aadhaar', 'pan', 'bank', 'linkedin'].includes(paper),
        'Choose the document to remove.', 'invalid-argument');
      return store.transaction(async transaction => {
        let id, record;
        if (token) ({ id, record } = await active(transaction, token));
        else {
          requireValue(typeof idInput === 'string' && /^[a-f0-9]{64}$/.test(idInput));
          id = idInput;
          record = await transaction.get(`brokerDocumentRequests/${id}`);
          requireValue(record && auth?.uid === record.brokerUid, 'Only the requesting broker can do this.', 'permission-denied');
          const current = await context(transaction, record.brokerUid, record.draftId, record.revision, record.partyId);
          requireValue(current.identity === record.identity && (closing || record.expiresAtMs > now()));
        }
        requireValue(auth?.uid === record.brokerUid, 'Only the requesting broker can do this.', 'permission-denied');
        requireValue(version === record.version, 'The link changed. Reload before continuing.', 'aborted');
        if (action === 'linkedin_added') {
          requireValue(record.type === 'linkedin' && record.role === 'tenant', 'Choose the tenant LinkedIn profile.', 'invalid-argument');
          let profile;
          try { profile = linkedInProfile(linkedInDetails); } catch { throw new DocumentRequestError('invalid-argument', 'This is not a LinkedIn link. It should start with linkedin.com/in/'); }
          transaction.update(`brokerDocumentRequests/${id}`, { status: 'added', currentUploadId: null, currentUploadUid: null,
            submission: { uploadId: eventId(), files: {}, linkedInDetails: profile, addedByUid: auth.uid,
              addedByName: 'you', atMs: now(), verified: false } });
          audit(transaction, id, profile.skipped ? 'linkedin_skipped_by_broker' : 'linkedin_added_by_broker', auth.uid);
          return { status: 'added' };
        }
        if (closing) {
          requireValue(record.type === 'all' || record.type === paper, 'This link does not request that paper.', 'invalid-argument');
          const closedPapers = { ...record.closedPapers, [paper]: { action, atMs: now() } };
          const status = openSlots({ ...record, closedPapers }).length === 0 ? 'revoked' :
            record.status === 'finalizing' ? 'seen' : record.status;
          transaction.update(`brokerDocumentRequests/${id}`, { closedPapers, status,
            currentUploadId: null, currentUploadUid: null, pendingBankDetails: null });
          audit(transaction, id, `${action}:${paper}`, auth.uid);
          return { status };
        }
        requireValue(action !== 'unclear' || typeof reason === 'string' && reason.trim().length >= 5 && reason.length <= 500,
          'Explain which page needs replacing.', 'invalid-argument');
        requireValue(action !== 'unclear' || record.status === 'added');
        const status = action === 'shared' && !['created', 'shared'].includes(record.status) ? record.status : action;
        transaction.update(`brokerDocumentRequests/${id}`, { status,
          ...(action === 'shared' ? { sharedAtMs: now(), shareCount: (record.shareCount ?? 0) + 1, ...(channel ? { channel } : {}),
            delivery: 'broker_reported_not_provider_confirmed' } : {}),
          ...(action === 'unclear' ? { reason: reason.trim(), currentUploadId: null } : {}) });
        audit(transaction, id, action === 'shared' ? 'broker_reported_shared' : action, auth.uid);
        return { status };
      });
    },
    async begin({ token, bankDetails, linkedInDetails }) {
      const uploadId = eventId();
      return store.transaction(async transaction => {
        const { id, record } = await active(transaction, token);
        proof(record);
        requireValue(linkedInDetails == null || record.role === 'tenant' && ['linkedin', 'all'].includes(record.type), 'This link does not request LinkedIn.', 'invalid-argument');
        let profile = null;
        if (record.type === 'linkedin' || linkedInDetails != null) {
          try { profile = linkedInProfile(linkedInDetails); } catch { throw new DocumentRequestError('invalid-argument', 'This is not a LinkedIn link. It should start with linkedin.com/in/'); }
        }
        requireValue(bankDetails == null || openSlots(record).includes('bankProof'), 'This link does not request bank details.', 'invalid-argument');
        const bank = bankDetails == null ? null : bankInformation(bankDetails);
        const uploadSlots = openSlots(record).filter(kind => !bank || kind !== 'bankProof');
        requireValue(record.status !== 'added', 'This paper is already sent. The broker must request a replacement.');
        requireValue(record.status !== 'finalizing' || record.finalizingAtMs + 120000 < now(), 'Your upload is being checked. Try again shortly.');
        transaction.update(`brokerDocumentRequests/${id}`, { status: 'seen', currentUploadId: uploadId,
          currentUploadUid: auth.uid, uploadExpiresAtMs: now() + 600000, recipientUid: auth.uid,
          uploadSlots, pendingBankDetails: bank, pendingLinkedInDetails: profile });
        audit(transaction, id, 'upload_started', auth.uid);
        return { requestId: id, uploadId, slots: uploadSlots,
          paths: Object.fromEntries(uploadSlots.map(kind => [kind, `brokerDocumentRequests/${id}/uploads/${uploadId}/${kind}`])) };
      });
    },
    async complete({ token, uploadId }) {
      requireValue(safe(uploadId), 'Restart the document upload.', 'invalid-argument');
      let ready;
      await store.transaction(async transaction => {
        const { id, record, current } = await active(transaction, token);
        proof(record);
        if (record.status === 'added' && record.submission?.uploadId === uploadId) {
          ready = publicResult(id, record, current, true);
          return;
        }
        requireValue(record.currentUploadId === uploadId && record.currentUploadUid === auth.uid && record.uploadExpiresAtMs > now());
        transaction.update(`brokerDocumentRequests/${id}`, { status: 'finalizing', finalizingAtMs: now() });
      });
      const id = tokenId(token);
      if (ready) {
        await files.cleanup?.(id, uploadId).catch(() => {});
        return ready;
      }
      try {
        const snapshot = await files.snapshot(id, uploadId);
        const result = await store.transaction(async transaction => {
          const { record, current } = await active(transaction, token);
          proof(record);
          if (record.status === 'added' && record.submission?.uploadId === uploadId) return publicResult(id, record, current, true);
          requireValue(record.currentUploadId === uploadId && record.currentUploadUid === auth.uid && record.status === 'finalizing');
          const requiredSlots = record.uploadSlots ?? kinds[record.type];
          requireValue(requiredSlots.every(kind => snapshot[kind]) && Object.keys(snapshot).length === requiredSlots.length,
            'Add every required page before sending.', 'invalid-argument');
          record.status = 'added';
          record.submission = { uploadId, files: snapshot,
            ...(record.pendingBankDetails ? { bankDetails: record.pendingBankDetails } : {}),
            ...(record.pendingLinkedInDetails ? { linkedInDetails: record.pendingLinkedInDetails } : {}),
            addedByUid: auth.uid, addedByName: current.partyName, atMs: now(), verified: false };
          transaction.update(`brokerDocumentRequests/${id}`, { status: record.status, submission: record.submission,
            currentUploadId: null, currentUploadUid: null, pendingBankDetails: null, pendingLinkedInDetails: null, reason: '' });
          const update = documentSubmittedUpdate(id, record);
          transaction.set(`users/${record.brokerUid}/updates/${update.id}`, update.data);
          audit(transaction, id, 'paper_submitted_not_identity_verified', auth.uid);
          return publicResult(id, record, current, true);
        });
        await files.cleanup?.(id, uploadId).catch(() => {});
        return result;
      } catch (error) {
        await store.transaction(async transaction => {
          const record = await transaction.get(`brokerDocumentRequests/${id}`);
          if (record?.currentUploadId === uploadId && record.status === 'finalizing') {
            transaction.update(`brokerDocumentRequests/${id}`, { status: 'seen' });
          }
        });
        throw error;
      }
    },
  };
}
