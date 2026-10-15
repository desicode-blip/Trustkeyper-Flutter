import { createHash } from 'node:crypto';

export class RepairWorkflowError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const requireValue = (condition, message, code = 'failed-precondition') => {
  if (!condition) throw new RepairWorkflowError(code, message);
};
const safe = value => typeof value === 'string' && /^[\w-]{1,150}$/.test(value);
const money = value => Number.isSafeInteger(value) && value > 0 && value <= 100000000;
const text = (value, min, max) => typeof value === 'string' && value.trim().length >= min && value.length <= max;
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const summary = (issue, actor) => ({ ...issue, actorRole: actor.role, actorUid: actor.uid,
  canApprove: actor.role === 'owner' && issue.status === 'waiting_owner' && !issue.ownerApprovals?.[actor.uid],
  canConfirm: actor.role === 'tenant' && ['resolved', 'closed', 'needs_attention'].includes(issue.status),
});

export function createRepairWorkflowService({ auth, store, files, now = Date.now }) {
  async function context(transaction, issueId, adminOnly = false) {
    requireValue(auth?.uid, 'Sign in again.', 'unauthenticated');
    requireValue(safe(issueId), 'Choose a repair.', 'invalid-argument');
    const profile = await transaction.get(`users/${auth.uid}`);
    requireValue(profile && profile.paused !== true, 'This account is unavailable.', 'permission-denied');
    const issue = await transaction.get(`issues/${issueId}`);
    requireValue(issue && safe(issue.agreementId), 'This repair has no linked agreement. Contact support.', 'not-found');
    const agreement = await transaction.get(`agreements/${issue.agreementId}`);
    requireValue(agreement, 'This home is unavailable.', 'not-found');
    let role;
    if (profile.roles?.includes('admin')) role = 'admin';
    else {
      requireValue(!adminOnly && issue.participantUids?.includes(auth.uid) && agreement.participantUids?.includes(auth.uid),
        'This repair is not linked to your account.', 'permission-denied');
      const people = agreement.agreementCopy?.mode === 'externally_signed' ? agreement.agreementCopy.people : [];
      const matches = (people ?? []).filter(person => person.uid === auth.uid);
      role = matches.some(person => person.role === 'owner') ? 'owner'
        : matches.some(person => person.role === 'tenant') ? 'tenant'
          : agreement.brokerUid === auth.uid ? 'broker' : 'participant';
    }
    requireValue(!adminOnly || role === 'admin', 'Only the support team can manage repairs.', 'permission-denied');
    return { issue, agreement, actor: { uid: auth.uid, role } };
  }
  function version(issue, input) {
    requireValue(Number.isSafeInteger(input.version) && input.version === (issue.workflowVersion ?? 0),
      'This repair changed on another device. Reopen it before saving.', 'aborted');
  }
  function owners(agreement) {
    requireValue(agreement.agreementCopy?.mode === 'externally_signed' &&
      agreement.agreementCopy.revision === agreement.revision,
    'Publish the current signed agreement before authorising repair costs.');
    const people = agreement.agreementCopy.people?.filter(person => person.role === 'owner');
    requireValue(people?.length > 0 && people.every(person => safe(person.uid) && agreement.participantUids?.includes(person.uid)),
      'Verified owners are missing. Fix the agreement links first.');
    return [...new Set(people.map(person => person.uid))].sort();
  }
  async function mutate(input, action, adminOnly, handler) {
    requireValue(/^[a-f0-9]{32}$/.test(input.operationId ?? ''), 'Reopen this repair and try again.', 'invalid-argument');
    return store.transaction(async transaction => {
      const current = await context(transaction, input.issueId, adminOnly);
      const operation = hash([auth.uid, input.issueId, input.operationId]);
      const fingerprint = hash([action, input]);
      const previous = await transaction.get(`repairOperations/${operation}`);
      if (previous) {
        requireValue(previous.fingerprint === fingerprint, 'Retry the same details or reopen the repair.', 'aborted');
        return previous.result;
      }
      version(current.issue, input);
      const changes = await handler(transaction, current);
      const nextVersion = (current.issue.workflowVersion ?? 0) + 1;
      transaction.update(`issues/${input.issueId}`, { ...changes, workflowVersion: nextVersion,
        updatedAtMs: now(), updatedAt: store.timestamp() });
      const result = { issueId: input.issueId, version: nextVersion, status: changes.status ?? current.issue.status };
      const event = { action, actorUid: auth.uid, actorRole: current.actor.role, createdAtMs: now(),
        previousVersion: current.issue.workflowVersion ?? 0, version: nextVersion, changes };
      transaction.set(`issues/${input.issueId}/events/${operation}`, event);
      transaction.set(`adminAuditLogs/${operation}`, { ...event, targetPath: `issues/${input.issueId}` });
      transaction.set(`repairOperations/${operation}`, { fingerprint, actorUid: auth.uid, result, createdAtMs: now() });
      return result;
    });
  }
  function ready(issue, agreement) {
    const currentOwners = owners(agreement);
    requireValue(JSON.stringify(currentOwners) === JSON.stringify(issue.ownerUids) &&
      issue.agreementRevision === agreement.revision, 'The owners or agreement changed. Get a new quote.');
    requireValue(issue.quote && (!issue.quote.needsApproval || currentOwners.every(uid =>
      issue.ownerApprovals?.[uid]?.quoteVersion === issue.quote.version)), 'Every owner must approve this quote first.');
  }
  return {
    async fromPhoto(input) {
      requireValue(auth?.uid, 'Sign in again.', 'unauthenticated');
      requireValue(/^properties\/[\w-]{1,150}\/photoChecks\/[\w-]{1,150}$/.test(input.photoPath ?? ''),
        'Choose a property photo check.', 'invalid-argument');
      return store.transaction(async transaction => {
        const profile = await transaction.get(`users/${auth.uid}`);
        requireValue(profile?.roles?.includes('admin') && profile.paused !== true,
          'Only the support team can create repairs from inspections.', 'permission-denied');
        const photo = await transaction.get(input.photoPath);
        const propertyId = input.photoPath.split('/')[1];
        const property = await transaction.get(`properties/${propertyId}`);
        const agreementId = photo?.agreementId ?? property?.agreementId;
        requireValue(photo && property && safe(agreementId), 'Link this inspection to its agreement before creating a repair.');
        const agreement = await transaction.get(`agreements/${agreementId}`);
        requireValue(agreement && agreement.propertyId === propertyId && agreement.participantUids?.length > 0,
          'This inspection and agreement do not belong to the same home.');
        const issueId = hash(['inspection-repair', input.photoPath]).slice(0, 32);
        const previous = await transaction.get(`issues/${issueId}`);
        if (previous) {
          requireValue(previous.sourcePhotoPath === input.photoPath && previous.agreementId === agreementId,
            'The inspection repair link changed. Contact support.', 'aborted');
          return { issueId, status: previous.status };
        }
        requireValue(!photo.issueId && ['submitted', 'pending', 'needs_review', 'rejected', 'flagged', 'needs_repair', 'damaged', 'open'].includes(photo.status),
          'This photo check already has a repair or is not awaiting review.');
        const timestamp = store.timestamp();
        transaction.set(`issues/${issueId}`, { agreementId, propertyId, participantUids: agreement.participantUids,
          propertyAddress: agreement.propertyAddress ?? property.propertyAddress ?? '', title: 'Inspection repair',
          description: 'Support flagged a property inspection photo for repair. Review the inspection before quoting.',
          category: 'Other', status: 'open', photos: [], workflowVersion: 0, sourcePhotoPath: input.photoPath,
          createdBy: auth.uid, createdAtMs: now(), createdAt: timestamp, updatedAt: timestamp });
        transaction.update(input.photoPath, { status: 'repair_created', issueId, reviewedAt: timestamp });
        transaction.set(`adminAuditLogs/${hash(['inspection-repair-created', issueId])}`, {
          action: 'photo_check.repair_created', actorUid: auth.uid, targetPath: input.photoPath,
          issueId, agreementId, createdAtMs: now() });
        return { issueId, status: 'open' };
      });
    },
    async read(input) {
      return store.transaction(async transaction => {
        const current = await context(transaction, input.issueId);
        return { issueId: input.issueId, ...summary(current.issue, current.actor) };
      });
    },
    async quote(input) {
      requireValue(money(input.amountPaise) && text(input.vendorName, 2, 120) &&
        text(input.vendorPhone, 10, 16) && /^\+?[\d ]+$/.test(input.vendorPhone) && text(input.description, 10, 2000),
      'Add the vendor, phone, work description and a valid quote.', 'invalid-argument');
      return mutate(input, 'repair.quote', true, async (transaction, { issue, agreement }) => {
        requireValue(['open', 'waiting_owner', 'approved', 'assigned', 'in_progress'].includes(issue.status) && !issue.completion,
          'Completed repairs cannot be requoted. Open a new issue for new work.');
        const ownerUids = owners(agreement);
        const quoteVersion = (issue.quote?.version ?? 0) + 1;
        return { status: input.amountPaise > 200000 ? 'waiting_owner' : 'approved', ownerUids,
          agreementRevision: agreement.revision, estimatePaise: input.amountPaise, ownerApprovals: {}, visit: null,
          quote: { version: quoteVersion, amountPaise: input.amountPaise, needsApproval: input.amountPaise > 200000,
            vendorName: input.vendorName.trim(), vendorPhone: input.vendorPhone.trim(),
            description: input.description.trim(), recordedBy: auth.uid, recordedAtMs: now() } };
      });
    },
    async approve(input) {
      return mutate(input, 'repair.owner_approved', false, async (transaction, { issue, agreement, actor }) => {
        requireValue(actor.role === 'owner' && owners(agreement).includes(actor.uid),
          'Only a verified owner of this home can approve.', 'permission-denied');
        requireValue(issue.status === 'waiting_owner' && issue.quote?.version === input.quoteVersion &&
          issue.agreementRevision === agreement.revision && JSON.stringify(owners(agreement)) === JSON.stringify(issue.ownerUids),
        'The quote or owners changed. Read the latest quote before approving.', 'aborted');
        const approvals = { ...issue.ownerApprovals, [actor.uid]: { quoteVersion: input.quoteVersion, approvedAtMs: now() } };
        return { ownerApprovals: approvals, status: issue.ownerUids.every(uid => approvals[uid]?.quoteVersion === input.quoteVersion)
          ? 'approved' : 'waiting_owner' };
      });
    },
    async schedule(input) {
      requireValue(Number.isSafeInteger(input.startsAtMs) && Number.isSafeInteger(input.endsAtMs) &&
        input.startsAtMs >= now() - 300000 && input.startsAtMs <= now() + 90 * 86400000 &&
        input.endsAtMs > input.startsAtMs && input.endsAtMs - input.startsAtMs <= 8 * 3600000,
      'Choose a future visit of up to eight hours within 90 days.', 'invalid-argument');
      return mutate(input, 'repair.visit_scheduled', true, async (transaction, { issue, agreement }) => {
        requireValue(['approved', 'assigned', 'in_progress'].includes(issue.status), 'Approve the quote before scheduling.');
        ready(issue, agreement);
        return { status: 'assigned', visit: { startsAtMs: input.startsAtMs, endsAtMs: input.endsAtMs,
          vendorName: issue.quote.vendorName, vendorPhone: issue.quote.vendorPhone } };
      });
    },
    async beginCompletion(input) {
      requireValue(/^[a-f0-9]{32}$/.test(input.operationId ?? '') && money(input.amountPaise) &&
        text(input.invoiceNumber, 1, 80) && /^\d{4}-\d{2}-\d{2}$/.test(input.payoutDateISO ?? '') &&
        typeof input.includeBefore === 'boolean' && input.visitDone === true,
      'Choose a bill amount, invoice, payout date and confirm the visit is done.', 'invalid-argument');
      const date = Date.parse(`${input.payoutDateISO}T00:00:00+05:30`);
      requireValue(Number.isFinite(date) && new Date(date + 19800000).toISOString().slice(0, 10) === input.payoutDateISO &&
        date >= now() - 86400000 && date < now() + 180 * 86400000 && input.payoutDateISO.endsWith('-07'),
      'Choose the intended owner payout on the 7th, within six months.', 'invalid-argument');
      const uploadId = hash([auth?.uid, input.issueId, input.operationId]);
      const fingerprint = hash(input);
      return store.transaction(async transaction => {
        const { issue, agreement } = await context(transaction, input.issueId, true);
        const previous = await transaction.get(`repairCompletionUploads/${uploadId}`);
        if (previous) {
          requireValue(previous.fingerprint === fingerprint, 'Retry the same selected bill and details.', 'aborted');
          requireValue(previous.status === 'completed' || previous.expiresAtMs > now(), 'This upload expired. Start again.');
          return { uploadId, completed: previous.status === 'completed', path: `repairCompletionUploads/${auth.uid}/${uploadId}` };
        }
        version(issue, input);
        ready(issue, agreement);
        requireValue(['assigned', 'in_progress'].includes(issue.status) && issue.visit && !issue.completion,
          'Schedule the approved visit before recording completion.');
        requireValue(issue.visit.startsAtMs <= now(), 'The scheduled visit has not started yet. Update the visit first.');
        requireValue(input.amountPaise <= issue.quote.amountPaise, 'The bill exceeds the approved quote. Get a new quote and approval first.');
        requireValue(input.includeBefore || issue.photos?.length > 0, 'Add a before photo as well as the after photo and bill.');
        transaction.set(`repairCompletionUploads/${uploadId}`, { ...input, uploadId, fingerprint, adminUid: auth.uid,
          quoteVersion: issue.quote.version, status: 'uploading', createdAtMs: now(), expiresAtMs: now() + 15 * 60000 });
        return { uploadId, completed: false, path: `repairCompletionUploads/${auth.uid}/${uploadId}` };
      });
    },
    async complete(input) {
      requireValue(/^[a-f0-9]{64}$/.test(input.uploadId ?? ''), 'Choose the completion upload.', 'invalid-argument');
      async function check(transaction) {
        requireValue(auth?.uid, 'Sign in again.', 'unauthenticated');
        const upload = await transaction.get(`repairCompletionUploads/${input.uploadId}`);
        requireValue(upload?.adminUid === auth.uid, 'This upload is unavailable.', 'permission-denied');
        const current = await context(transaction, upload.issueId, true);
        if (upload.status === 'completed') {
          requireValue(current.issue.completion?.uploadId === input.uploadId, 'This completion was superseded.');
          return { upload, ...current };
        }
        requireValue(upload.status === 'uploading' && upload.expiresAtMs > now(), 'This upload expired. Start again.');
        version(current.issue, upload);
        ready(current.issue, current.agreement);
        requireValue(['assigned', 'in_progress'].includes(current.issue.status) && !current.issue.completion &&
          current.issue.quote.version === upload.quoteVersion, 'The repair changed while uploading. Reopen it.', 'aborted');
        return { upload, ...current };
      }
      const initial = await store.transaction(check);
      if (initial.upload.status === 'completed') return { issueId: initial.upload.issueId, status: initial.issue.status };
      const evidence = await files.snapshot(initial.upload);
      const result = await store.transaction(async transaction => {
        const { upload, issue, agreement } = await check(transaction);
        if (upload.status === 'completed') return { issueId: upload.issueId, status: issue.status };
        const eventId = hash([input.uploadId, 'complete']);
        const completion = { uploadId: input.uploadId, amountPaise: upload.amountPaise,
          invoiceNumber: upload.invoiceNumber, payoutDateISO: upload.payoutDateISO, vendorName: issue.quote.vendorName,
          quoteVersion: issue.quote.version, evidence, completedAtMs: now(), recordedBy: auth.uid };
        transaction.update(`issues/${upload.issueId}`, { completion, finalBillPaise: upload.amountPaise,
          status: 'resolved', workflowVersion: (issue.workflowVersion ?? 0) + 1, updatedAt: store.timestamp(), updatedAtMs: now() });
        transaction.set(`repairCharges/${upload.issueId}`, { agreementId: issue.agreementId, issueId: upload.issueId,
          amountPaise: upload.amountPaise, ownerUids: issue.ownerUids, participantUids: agreement.participantUids,
          payoutDateISO: upload.payoutDateISO, status: 'pending_reconciliation', source: 'verified_repair_completion',
          completionUploadId: input.uploadId, createdAtMs: now() });
        const event = { actorUid: auth.uid, action: 'repair.completed', targetPath: `issues/${upload.issueId}`,
          amountPaise: upload.amountPaise, quoteVersion: issue.quote.version, createdAtMs: now() };
        transaction.set(`issues/${upload.issueId}/events/${eventId}`, event);
        transaction.set(`adminAuditLogs/${eventId}`, event);
        transaction.update(`repairCompletionUploads/${input.uploadId}`, { status: 'completed', completedAtMs: now() });
        return { issueId: upload.issueId, status: 'resolved' };
      });
      try { await files.cleanup(initial.upload); } catch { }
      return result;
    },
    async confirm(input) {
      requireValue(['working', 'not_working'].includes(input.outcome) &&
        (input.outcome === 'working' || text(input.note, 10, 1000)), 'Tell us whether the repair is working.', 'invalid-argument');
      return mutate(input, 'repair.tenant_confirmed', false, async (transaction, { issue, actor }) => {
        requireValue(actor.role === 'tenant', 'Only a verified tenant can confirm the repair.', 'permission-denied');
        requireValue(issue.completion && ['resolved', 'closed', 'needs_attention'].includes(issue.status),
          'The team has not uploaded the completed repair yet.');
        const confirmations = { ...issue.tenantConfirmations, [auth.uid]: { outcome: input.outcome,
          note: input.outcome === 'not_working' ? input.note.trim() : '', recordedAtMs: now() } };
        return { tenantConfirmations: confirmations,
          status: Object.values(confirmations).some(reply => reply.outcome === 'not_working') ? 'needs_attention' : 'closed' };
      });
    },
    async readFile(input) {
      requireValue(['bill', 'before', 'after'].includes(input.slot), 'Choose repair evidence.', 'invalid-argument');
      const initial = await store.transaction(async transaction => {
        const { issue } = await context(transaction, input.issueId);
        const file = issue.completion?.evidence?.[input.slot];
        requireValue(file, 'This evidence is unavailable.', 'not-found');
        return file;
      });
      const result = await files.read(initial);
      await store.transaction(async transaction => {
        const { issue } = await context(transaction, input.issueId);
        const current = issue.completion?.evidence?.[input.slot];
        requireValue(current?.generation === initial.generation && current.path === initial.path,
          'This evidence changed. Reopen the repair.', 'aborted');
      });
      return result;
    },
  };
}
