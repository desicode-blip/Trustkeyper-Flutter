import { createHash } from 'node:crypto';
import { reviewSnapshot } from './agreement-review.js';
import { approvalDigest } from './agreement-approvals.js';

export class RenewalError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

const requireValue = (condition, message, code = 'failed-precondition') => {
  if (!condition) throw new RenewalError(code, message);
};
const safe = value => typeof value === 'string' && /^[\w-]{1,128}$/.test(value);

function monthsAfter(date, months) {
  const first = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + months, 1));
  const last = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0)).getUTCDate();
  first.setUTCDate(Math.min(date.getUTCDate(), last));
  return first;
}

export function createAgreementRenewalService({ auth, store, now = Date.now }) {
  return {
    async create({ sourceAgreementId, revision, digest, operationId }) {
      requireValue(auth?.uid, 'Log in again to renew an agreement.', 'unauthenticated');
      requireValue(safe(sourceAgreementId) && Number.isSafeInteger(revision) && revision > 0 &&
        typeof digest === 'string' && /^[a-f0-9]{64}$/.test(digest) &&
        typeof operationId === 'string' && /^[a-f0-9]{32}$/.test(operationId),
      'Choose a current signed agreement.', 'invalid-argument');
      const sourcePath = `agreements/${sourceAgreementId}`;
      return store.transaction(async transaction => {
        const profile = await transaction.get(`users/${auth.uid}`);
        const source = await transaction.get(sourcePath);
        requireValue(profile?.roles?.includes('broker') && profile.approvalStatus === 'approved' &&
          profile.paused !== true && source?.brokerUid === auth.uid && source.participantUids?.includes(auth.uid),
        'Only this home\'s approved broker can renew it.', 'permission-denied');
        requireValue(source.revision === revision, 'This agreement changed. Choose it again.', 'aborted');
        requireValue(['signed_copy_received', 'active'].includes(source.status), 'Only signed agreements can be renewed.');
        let snapshot;
        try { snapshot = reviewSnapshot(source); }
        catch { throw new RenewalError('failed-precondition', 'The original needs a complete reviewed set of terms.'); }
        const currentDigest = approvalDigest(snapshot);
        const copy = source.agreementCopy;
        requireValue(currentDigest === digest, 'The original terms changed. Choose it again.', 'aborted');
        requireValue(copy?.mode === 'externally_signed' && copy.revision === revision && copy.digest === currentDigest &&
          copy.agreementId === sourceAgreementId && safe(copy.uploadId) && copy.file?.generation &&
          /^[a-f0-9]{64}$/.test(copy.file?.sha256 ?? ''), 'The genuine signed original is not ready.');
        requireValue(safe(source.propertyId), 'Link this agreement to its actual home first.');
        const property = await transaction.get(`properties/${source.propertyId}`);
        requireValue(property?.brokerUid === auth.uid && property.participantUids?.includes(auth.uid),
          'This broker no longer manages the home.', 'permission-denied');
        requireValue(!property.activeAgreementId || property.activeAgreementId === sourceAgreementId,
          'Another agreement is already active for this home.');
        if (source.activeRenewalId) {
          requireValue(safe(source.activeRenewalId), 'The renewal link needs team review.');
          const existing = await transaction.get(`agreements/${source.activeRenewalId}`);
          requireValue(existing?.brokerUid === auth.uid && existing.renewalSourceId === sourceAgreementId &&
            existing.renewalSourceRevision === revision && existing.renewalSourceDigest === digest,
          'The linked renewal needs team review.');
          requireValue(['draft', 'review_requested', 'under_review', 'reviewed'].includes(existing.status),
            'A renewal already exists for this agreement. Open it from Records.');
          return { agreementId: source.activeRenewalId, status: existing.status, resumed: true };
        }
        const agreementId = createHash('sha256').update(JSON.stringify([auth.uid, sourceAgreementId, operationId])).digest('hex');
        const targetPath = `agreements/${agreementId}`;
        requireValue(!await transaction.get(targetPath), 'This renewal already exists. Refresh your records.', 'already-exists');
        const start = new Date(`${snapshot.endDateISO.slice(0, 10)}T00:00:00Z`);
        start.setUTCDate(start.getUTCDate() + 1);
        const duration = Math.max(11, snapshot.lockInMonths, snapshot.noticeMonths);
        const end = monthsAfter(start, duration);
        end.setUTCDate(end.getUTCDate() - 1);
        const fields = ['propertyAddress', 'owners', 'tenants', 'monthlyRentPaise', 'monthlyMaintenancePaise',
          'securityDepositPaise', 'ownerBrokeragePaise', 'tenantBrokeragePaise', 'rentDueDay', 'lockInMonths', 'noticeMonths'];
        const draft = {
          ...Object.fromEntries(fields.map(field => [field, snapshot[field]])),
          schemaVersion: 2, propertyId: source.propertyId,
          ...(source.propertyDetails ? { propertyDetails: source.propertyDetails } : {}),
          startDateISO: start.toISOString().slice(0, -1), endDateISO: end.toISOString().slice(0, -1),
          effectiveDate: start, endDate: end, status: 'draft', revision: 1,
          brokerUid: auth.uid, participantUids: [auth.uid],
          renewalSourceId: sourceAgreementId, renewalSourceRevision: revision, renewalSourceDigest: digest,
          partyNames: [...snapshot.owners, ...snapshot.tenants].map(person => person.name),
          owner: snapshot.owners[0], tenant: snapshot.tenants[0],
          brokerageFeePaise: snapshot.ownerBrokeragePaise + snapshot.tenantBrokeragePaise,
          brokeragePayer: snapshot.ownerBrokeragePaise === 0 ? (snapshot.tenantBrokeragePaise === 0 ? 'none' : 'tenant')
            : snapshot.tenantBrokeragePaise === 0 ? 'owner' : 'split',
          createdAt: store.timestamp(), updatedAt: store.timestamp(),
        };
        reviewSnapshot(draft);
        transaction.set(targetPath, draft);
        transaction.update(sourcePath, { activeRenewalId: agreementId, updatedAt: store.timestamp() });
        const event = { action: 'renewal_draft_created', actorUid: auth.uid, sourceAgreementId,
          sourceRevision: revision, sourceDigest: digest, agreementId, createdAtMs: now(), revision: 1 };
        transaction.set(`${targetPath}/events/renewal-created`, event);
        transaction.set(`adminAuditLogs/renewal-${agreementId}`, { ...event, targetPath });
        return { agreementId, status: 'draft', resumed: false };
      });
    },
  };
}
