import { createHash, randomUUID } from 'node:crypto';

export class ReviewError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function requireValue(condition, message, code = 'failed-precondition') {
  if (!condition) throw new ReviewError(code, message);
}

function dateValue(value) {
  requireValue(typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T00:00:00(?:\.0+)?Z?$/.test(value),
    'Save valid agreement dates before requesting review.');
  const date = new Date(`${value.slice(0, 10)}T00:00:00Z`);
  requireValue(Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value.slice(0, 10),
    'Save valid agreement dates before requesting review.');
  return date;
}

function monthsAfter(date, months) {
  const first = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + months, 1));
  const last = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0)).getUTCDate();
  first.setUTCDate(Math.min(date.getUTCDate(), last));
  return first;
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  }
  return value;
}

export function reviewSnapshot(data) {
  requireValue(data?.schemaVersion === 2 && typeof data.propertyAddress === 'string' &&
    data.propertyAddress.length <= 2000,
  'Save a complete current-format draft before requesting review.');
  const partyIds = new Set();
  function parties(values) {
    requireValue(Array.isArray(values) && values.length >= 1 && values.length <= 20,
      'Add all owners and tenants before requesting review.');
    const phones = new Set();
    return values.map(party => {
      requireValue(party && typeof party.id === 'string' && /^[\w-]{1,150}$/.test(party.id) &&
        !partyIds.has(party.id) && typeof party.name === 'string' && party.name.trim().length >= 2 &&
        party.name.length <= 200 && typeof party.phone === 'string' && /^\+91[1-9]\d{9}$/.test(party.phone) &&
        !phones.has(party.phone), 'Check every person and remove duplicate contacts or identifiers.');
      requireValue(typeof party.email === 'string' && party.email.length <= 254 &&
        (party.email === '' || /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(party.email)), 'Check the participant email addresses.');
      partyIds.add(party.id);
      phones.add(party.phone);
      for (const field of ['rentSharePaise', 'depositSharePaise']) {
        requireValue(Number.isSafeInteger(party[field]) && party[field] >= 0 && party[field] <= 10000000000,
          'Save valid integer-paise participant shares.');
      }
      return Object.fromEntries(['id', 'name', 'phone', 'email', 'rentSharePaise', 'depositSharePaise']
        .map(field => [field, party[field]]));
    });
  }
  const owners = parties(data.owners);
  const tenants = parties(data.tenants);
  const amountFields = ['monthlyRentPaise', 'monthlyMaintenancePaise', 'securityDepositPaise',
    'ownerBrokeragePaise', 'tenantBrokeragePaise'];
  for (const field of amountFields) {
    requireValue(Number.isSafeInteger(data[field]) && data[field] >= 0 && data[field] <= 10000000000,
      'Save valid integer-paise rent, deposit and brokerage amounts.');
  }
  requireValue(data.monthlyRentPaise > 0 && data.securityDepositPaise > 0 &&
    data.ownerBrokeragePaise + data.tenantBrokeragePaise <= 10000000000,
  'Check the rent, deposit and brokerage totals.');
  for (const [share, total] of [['rentSharePaise', 'monthlyRentPaise'], ['depositSharePaise', 'securityDepositPaise']]) {
    requireValue(tenants.reduce((sum, party) => sum + party[share], 0) === data[total],
      'Tenant shares must exactly match the agreement totals.');
  }
  const start = dateValue(data.startDateISO);
  const end = dateValue(data.endDateISO);
  requireValue(end > start && [1, 5, 10].includes(data.rentDueDay) &&
    Number.isInteger(data.lockInMonths) && data.lockInMonths >= 0 && data.lockInMonths <= 60 &&
    Number.isInteger(data.noticeMonths) && data.noticeMonths >= 1 && data.noticeMonths <= 12,
  'Check the agreement dates, due day, lock-in and notice.');
  const boundary = new Date(end.getTime() + 86400000);
  requireValue(monthsAfter(start, data.lockInMonths) <= boundary && monthsAfter(start, data.noticeMonths) <= boundary,
    'Lock-in and notice cannot exceed the agreement period.');
  return canonical({
    templateVersion: 'demo-v1', signable: false,
    propertyAddress: data.propertyAddress.trim(), owners, tenants,
    ...Object.fromEntries([...amountFields, 'startDateISO', 'endDateISO', 'rentDueDay', 'lockInMonths', 'noticeMonths']
      .map(field => [field, data[field]])),
  });
}

export function createAgreementReviewService({ store, uid, now = Date.now, eventId = randomUUID }) {
  function inputs(agreementId, revision) {
    requireValue(typeof uid === 'string' && uid.length > 0, 'Log in again.', 'unauthenticated');
    requireValue(typeof agreementId === 'string' && /^[\w-]{1,150}$/.test(agreementId) &&
      Number.isSafeInteger(revision) && revision >= 1, 'Choose a saved draft revision.', 'invalid-argument');
    return `agreements/${agreementId}`;
  }
  async function records(transaction, path, revision, role) {
    const profile = await transaction.get(`users/${uid}`);
    const data = await transaction.get(path);
    requireValue(Array.isArray(profile?.roles) && profile.roles.includes(role) && profile.paused !== true &&
      (role !== 'broker' || profile.approvalStatus === 'approved'), 'This account cannot perform that action.', 'permission-denied');
    requireValue(data && (role !== 'broker' || data.brokerUid === uid), 'Agreement unavailable.', 'permission-denied');
    requireValue(data.revision === revision, 'This draft changed. Reopen it before continuing.', 'aborted');
    return data;
  }
  function audit(transaction, path, revision, action, timestamp, id, metadata = {}) {
    const entry = { action, actorUid: uid, revision, createdAtMs: timestamp, ...metadata };
    transaction.set(`${path}/events/${id}`, entry);
    transaction.set(`adminAuditLogs/${id}`, { ...entry, targetPath: path });
  }
  return {
    async submit({ agreementId, revision }) {
      const path = inputs(agreementId, revision);
      const id = eventId();
      const timestamp = now();
      return store.transaction(async transaction => {
        const data = await records(transaction, path, revision, 'broker');
        requireValue(Array.isArray(data.participantUids) && data.participantUids.length === 1 &&
          data.participantUids[0] === uid, 'This private draft already has linked participants.');
        if (data.lastReviewRevision === revision && ['review_requested', 'under_review', 'reviewed'].includes(data.status)) {
          return { agreementId, revision, status: data.status };
        }
        requireValue(data.status === 'draft' && (data.lastReviewRevision ?? 0) < revision,
          'Save a new revision before requesting another review.');
        const snapshot = reviewSnapshot(data);
        const digest = createHash('sha256').update(JSON.stringify(snapshot)).digest('hex');
        const roundId = createHash('sha256').update(JSON.stringify([agreementId, revision])).digest('hex');
        const approval = await transaction.get(`agreementApprovalRounds/${roundId}`);
        const parties = [...snapshot.owners, ...snapshot.tenants];
        requireValue(approval?.revision === revision && approval.digest === digest &&
          parties.every(party => approval.replies?.[party.id]?.status === 'agreed' &&
            approval.replies[party.id].revision === revision && approval.replies[party.id].digest === digest),
        'Every owner and tenant must reply yes to this saved version before team review.');
        transaction.set(`${path}/reviews/${revision}`, {
          snapshot, digest, revision, requestedBy: uid, requestedAtMs: timestamp,
        });
        transaction.update(path, { status: 'review_requested', lastReviewRevision: revision,
          reviewDigest: digest, reviewTemplateVersion: 'demo-v1', reviewSignable: false,
          reviewRequestedAtMs: timestamp, updatedAtMs: timestamp });
        audit(transaction, path, revision, 'agreement.review_requested', timestamp, id, { digest });
        return { agreementId, revision, status: 'review_requested' };
      });
    },
    async record({ agreementId, revision, step, reason }) {
      const path = inputs(agreementId, revision);
      requireValue(['request_received', 'reviewed', 'return_to_broker'].includes(step),
        'Demo agreements cannot be stamped, sent for signature or marked signed.', 'failed-precondition');
      if (step === 'return_to_broker') {
        requireValue(typeof reason === 'string' && reason.trim().length >= 5 && reason.length <= 500,
          'Give the broker a correction reason (5–500 characters).', 'invalid-argument');
      }
      const id = eventId();
      const timestamp = now();
      return store.transaction(async transaction => {
        const data = await records(transaction, path, revision, 'admin');
        requireValue(['review_requested', 'under_review', 'reviewed'].includes(data.status) &&
          data.lastReviewRevision === revision && data.reviewSignable === false,
        'This agreement is not awaiting demo review.');
        const review = await transaction.get(`${path}/reviews/${revision}`);
        requireValue(review?.digest === data.reviewDigest && review.snapshot?.signable === false,
          'The review evidence is missing or mismatched.');
        const status = step === 'return_to_broker' ? 'draft' : step === 'reviewed' ? 'reviewed' : 'under_review';
        if (data.status === status) return { agreementId, revision, status };
        requireValue(step !== 'request_received' || data.status === 'review_requested', 'Review cannot move backwards.');
        requireValue(step !== 'reviewed' || data.status === 'under_review', 'Receive the review request first.');
        transaction.update(path, { status, adminStep: step, reviewUpdatedBy: uid, reviewUpdatedAtMs: timestamp,
          reviewReturnReason: step === 'return_to_broker' ? reason.trim() : '', updatedAtMs: timestamp });
        audit(transaction, path, revision, `agreement.${step}`, timestamp, id,
          step === 'return_to_broker' ? { reason: reason.trim() } : {});
        return { agreementId, revision, status };
      });
    },
  };
}
