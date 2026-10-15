import { createHash } from 'node:crypto';

export class RepairError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

function requireValue(condition, message, code = 'failed-precondition') {
  if (!condition) throw new RepairError(code, message);
}

export function createRepairReportService({ auth, store, files, now = Date.now }) {
  function identity(profile) {
    requireValue(auth?.uid && profile && profile.paused !== true,
      'Sign in to an enabled account before sending a report.', 'permission-denied');
  }
  function identifier(value) {
    requireValue(typeof value === 'string' && /^[a-f0-9]{32}$/.test(value),
      'Reopen the report and try again.', 'invalid-argument');
    return value;
  }
  async function context(transaction, reportId) {
    const profile = await transaction.get(`users/${auth?.uid ?? '_anonymous'}`);
    identity(profile);
    const draft = await transaction.get(`repairReportUploads/${reportId}`);
    requireValue(draft && draft.createdBy === auth.uid, 'This report is not yours.', 'permission-denied');
    const agreement = await transaction.get(`agreements/${draft.agreementId}`);
    requireValue(agreement?.participantUids?.includes(auth.uid), 'This home is no longer linked to your account.', 'permission-denied');
    return { draft, agreement };
  }
  async function photoContext(transaction, reportId, index) {
    const profile = await transaction.get(`users/${auth?.uid ?? '_anonymous'}`);
    identity(profile);
    const issue = await transaction.get(`issues/${reportId}`);
    const agreement = issue && await transaction.get(`agreements/${issue.agreementId}`);
    requireValue(profile.roles?.includes('admin') ||
      issue?.participantUids?.includes(auth.uid) && agreement?.participantUids?.includes(auth.uid),
    'This photo is not available to your account.', 'permission-denied');
    const photo = issue?.photos?.[index];
    requireValue(photo?.path === `issues/${reportId}/photos/${index}`,
      'This report photo is unavailable.', 'not-found');
    return photo;
  }
  return {
    async readPhoto(input) {
      const reportId = identifier(input.reportId);
      requireValue(Number.isSafeInteger(input.index) && input.index >= 0 && input.index < 4,
        'Choose a report photo.', 'invalid-argument');
      const photo = await store.transaction(transaction => photoContext(transaction, reportId, input.index));
      const result = await files.read(photo);
      await store.transaction(async transaction => {
        const current = await photoContext(transaction, reportId, input.index);
        requireValue(current.generation === photo.generation, 'This report photo changed. Try again.');
      });
      return result;
    },
    async begin(input) {
      const reportId = identifier(input.reportId);
      requireValue(typeof input.agreementId === 'string' && /^[\w-]{1,150}$/.test(input.agreementId),
        'Choose a linked home.', 'invalid-argument');
      return store.transaction(async transaction => {
        identity(await transaction.get(`users/${auth?.uid ?? '_anonymous'}`));
        const draft = await transaction.get(`repairReportUploads/${reportId}`);
        const agreement = await transaction.get(`agreements/${input.agreementId}`);
        const limitPath = `repairUploadLimits/${auth.uid}`;
        const limit = await transaction.get(limitPath);
        requireValue(agreement?.participantUids?.includes(auth.uid), 'Choose a home linked to your account.', 'permission-denied');
        if (draft) {
          requireValue(draft.createdBy === auth.uid && draft.agreementId === input.agreementId,
            'This report cannot be changed. Reopen the issue form.', 'permission-denied');
          requireValue(draft.status === 'submitted' || draft.expiresAtMs > now(),
            'This upload expired. Reopen the issue form.');
          return { reportId, submitted: draft.status === 'submitted' };
        }
        const windowStart = Math.floor(now() / 3600000) * 3600000;
        const count = limit?.windowStart === windowStart ? limit.count : 0;
        requireValue(count < 20, 'Too many reports. Wait before trying again.', 'resource-exhausted');
        transaction.set(limitPath, { windowStart, count: count + 1 });
        transaction.set(`repairReportUploads/${reportId}`, { agreementId: input.agreementId,
          createdBy: auth.uid, status: 'uploading', createdAtMs: now(), expiresAtMs: now() + 3600000 });
        return { reportId, submitted: false };
      });
    },
    async submit(input) {
      const reportId = identifier(input.reportId);
      requireValue(['Water', 'Electric', 'Appliance', 'Door / lock', 'Other'].includes(input.category) &&
        typeof input.description === 'string' && input.description.trim().length >= 10 && input.description.trim().length <= 2000 &&
        Number.isSafeInteger(input.photoCount) && input.photoCount >= 0 && input.photoCount <= 4,
        'Choose a category, describe the problem and add up to four photos.', 'invalid-argument');
      const description = input.description.trim();
      const payloadHash = createHash('sha256').update(JSON.stringify([input.category, description, input.photoCount])).digest('hex');
      const initial = await store.transaction(async transaction => {
        const current = await context(transaction, reportId);
        const issue = await transaction.get(`issues/${reportId}`);
        if (issue) {
          requireValue(issue.createdBy === auth.uid && issue.payloadHash === payloadHash,
            'This report was already sent with different details.');
          return { submitted: true };
        }
        requireValue(current.draft.status === 'uploading' && current.draft.expiresAtMs > now(),
          'This upload expired. Reopen the issue form.');
        requireValue(!current.draft.payloadHash || current.draft.payloadHash === payloadHash,
          'Retry this report with the same details.');
        if (!current.draft.payloadHash) transaction.update(`repairReportUploads/${reportId}`, { payloadHash });
        return { submitted: false };
      });
      if (initial.submitted) return { reportId, submitted: true };
      const photos = await files.snapshot(auth.uid, reportId, input.photoCount);
      await store.transaction(async transaction => {
        const { draft, agreement } = await context(transaction, reportId);
        const issue = await transaction.get(`issues/${reportId}`);
        if (issue) {
          requireValue(issue.createdBy === auth.uid && issue.payloadHash === payloadHash,
            'This report was already sent with different details.');
          return;
        }
        requireValue(draft.status === 'uploading' && draft.expiresAtMs > now(),
          'This upload expired. Reopen the issue form.');
        requireValue(draft.payloadHash === payloadHash, 'Retry this report with the same details.');
        transaction.set(`issues/${reportId}`, { agreementId: draft.agreementId,
          propertyAddress: agreement.propertyAddress, participantUids: agreement.participantUids,
          createdBy: auth.uid, category: input.category, title: `${input.category} problem`, description,
          photos, payloadHash, status: 'open', createdAtMs: now(), createdAt: store.timestamp(), updatedAt: store.timestamp() });
        transaction.update(`repairReportUploads/${reportId}`, { status: 'submitted', submittedAtMs: now() });
      });
      try { await files.cleanup(auth.uid, reportId); } catch { }
      return { reportId, submitted: true };
    },
  };
}
