import { createHash, randomInt, timingSafeEqual } from 'node:crypto';

export class MoveOutError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const requireValue = (value, message, code = 'failed-precondition') => {
  if (!value) throw new MoveOutError(code, message);
};
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const safe = value => typeof value === 'string' && /^[\w-]{1,100}$/.test(value);
const indianDay = time => new Date(time + 330 * 60000).toISOString().slice(0, 10);
const dateTime = value => Date.parse(`${value}T00:00:00Z`);
const validDate = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
  Number.isFinite(dateTime(value)) && new Date(dateTime(value)).toISOString().slice(0, 10) === value;
const money = value => Number.isSafeInteger(value) && value >= 0 && value <= 10000000000;
const note = value => typeof value === 'string' && value.trim().length >= 10 && value.length <= 1000;
const keyKinds = ['mainDoor', 'bedrooms', 'letterBox', 'parkingCard'];

export function splitMoveOutCost(amount, people) {
  requireValue(money(amount) && people.length > 0 && people.every(person => money(person.depositPaise)), 'Check the deposit and deduction amounts.');
  const total = people.reduce((sum, person) => sum + person.depositPaise, 0);
  requireValue(total > 0 || amount === 0, 'A deposit is required before splitting deductions.');
  const rows = people.map(person => {
    const product = BigInt(amount) * BigInt(person.depositPaise);
    return { personId: person.personId, amountPaise: total ? Number(product / BigInt(total)) : 0,
      remainder: total ? product % BigInt(total) : 0n };
  });
  let remaining = amount - rows.reduce((sum, row) => sum + row.amountPaise, 0);
  for (const row of [...rows].sort((first, second) => first.remainder === second.remainder
    ? first.personId.localeCompare(second.personId) : first.remainder > second.remainder ? -1 : 1)) {
    if (remaining-- > 0) row.amountPaise++;
  }
  return Object.fromEntries(rows.map(row => [row.personId, row.amountPaise]));
}

export function createMoveOutService({ auth, store, tenancy, now = Date.now, code = () => String(randomInt(100000, 1000000)) }) {
  async function context(transaction, input) {
    requireValue(auth?.uid, 'Log in to open this move-out.', 'unauthenticated');
    requireValue(safe(input.agreementId), 'Choose a saved agreement.', 'invalid-argument');
    const record = await transaction.get(`moveOuts/${input.agreementId}`);
    const current = await tenancy.context(transaction, input, {
      rentThroughDate: Number.isSafeInteger(record?.handoverCompleteAtMs) ? indianDay(record.handoverCompleteAtMs) : null,
    });
    requireValue(current.state.phase === 'active' && current.state.notice && record &&
      record.date === current.state.notice.date && record.createdAtMs === current.state.notice.createdAtMs &&
      Array.isArray(record.personIds) && record.personIds.length > 0 &&
      JSON.stringify(record.personIds) === JSON.stringify(current.state.notice.personIds) &&
      record.personIds.every(id => current.snapshot.tenants.some(person => person.id === id)),
      'Give notice from this active signed home before starting the move-out.');
    requireValue(record.revision === undefined || record.revision === current.agreement.revision,
      'This move-out belongs to an older signed agreement.');
    const people = [];
    for (const person of current.snapshot.tenants.filter(person => record.personIds.includes(person.id))) {
      const account = await transaction.get(`rentPaymentAccounts/${hash(['live', input.agreementId, current.agreement.revision, person.id])}`);
      const payment = safe(account?.firstPaymentId) ? await transaction.get(`payments/${account.firstPaymentId}`) : null;
      const linked = current.copy.people.find(link => link.id === person.id && link.role === 'tenant');
      const verified = current.paymentRows.find(row => row.personId === person.id)?.paid === true &&
        payment?.mode === 'live' && payment.status === 'paid' && payment.captured === true && payment.providerVerified === true &&
        payment.currency === 'INR' && payment.agreementId === input.agreementId && payment.revision === current.agreement.revision &&
        payment.payerUid === linked.uid && payment.depositPaise === person.depositSharePaise && account?.depositPaid === true &&
        (payment.refundedPaise ?? 0) === 0;
      people.push({ personId: person.id, uid: linked.uid, name: person.name, depositPaise: verified ? person.depositSharePaise : 0,
        depositVerified: Boolean(verified), paymentId: account?.firstPaymentId ?? null });
    }
    const slots = record.photoSlots ?? {};
    requireValue(Object.keys(slots).length <= 250 && Object.values(slots).every(safe), 'The move-out evidence index needs reconciliation.');
    const photos = await Promise.all([...new Set(Object.values(slots))].map(async id => ({
      ...(await transaction.get(`properties/${current.agreement.propertyId}/photoChecks/${id}`)), id,
    })));
    const received = photos.filter(photo => photo.agreementId === input.agreementId && photo.revision === current.agreement.revision &&
      photo.createdBy === current.agreement.brokerUid && photo.actorRole === 'broker' && photo.file && !['flagged', 'rejected'].includes(photo.status));
    const rooms = current.rows.map(room => ({ ...room, items: room.items.map(item => ({ ...item,
      beforeId: current.state.baselinePhotoIds?.includes(item.checkId) ? item.checkId : null,
      afterId: received.find(photo => photo.purpose === 'move_out' && photo.itemId === item.id)?.id ?? null,
      comparison: record.comparisons?.[item.id] ?? null,
    })) }));
    const destination = current.role === 'tenant' ? await transaction.get(`moveOuts/${input.agreementId}/destinations/${current.person.id}`) : null;
    const refundRequests = await Promise.all(people.map(person => transaction.get(`moveOutRefundRequests/${hash([input.agreementId, person.personId])}`)));
    return { ...current, record, people, rooms, received, destination, refundRequests, agreementId: input.agreementId };
  }
  function summary(current) {
    const record = current.record;
    const lines = record.report?.lines ?? [];
    const ownersApproved = Boolean(record.report) && current.copy.people.filter(person => person.role === 'owner')
      .every(person => record.ownerApprovals?.[person.id]?.reportVersion === record.report.version);
    const pendingOwnerReview = Object.values(record.proposals ?? {}).some(proposal => proposal.status === 'pending');
    const shares = current.people.map(person => {
      let deductions = 0;
      let held = 0;
      for (const line of lines) {
        const response = record.responses?.[person.personId]?.[line.id];
        const resolved = record.decisions?.[line.id];
        const amount = resolved ? splitMoveOutCost(resolved.amountPaise, current.people)[person.personId] : line.shares[person.personId];
        if (resolved || response?.status === 'agreed') deductions += amount;
        else held += amount;
      }
      const request = current.refundRequests.find(request => request?.personId === person.personId);
      return { personId: person.personId, name: person.name, depositPaise: person.depositPaise,
        depositVerified: person.depositVerified, deductionsPaise: deductions, heldPaise: held,
        refundableNowPaise: ownersApproved && !pendingOwnerReview ? Math.max(0, person.depositPaise - deductions - held) : 0,
        refundStatus: request?.status ?? 'not_requested', requestedPaise: request?.amountPaise ?? 0 };
    });
    return { agreementId: current.agreementId, propertyId: current.agreement.propertyId, address: current.snapshot.propertyAddress,
      role: current.role, myPersonId: current.person?.id ?? null, version: record.version, revision: current.agreement.revision,
      people: current.people.map(({ uid, paymentId, ...person }) => person),
      rent: current.rentRows.filter(row => record.personIds.includes(row.personId)).map(({ followUpPath, ...row }) => row),
      charges: Object.values(record.charges ?? {}),
      status: record.status, today: indianDay(now()), notice: current.state.notice, booking: record.booking ?? null,
      canEdit: current.broker, rooms: current.rooms, givenKeys: current.state.keys, returnedKeys: record.returnedKeys ?? null,
      keyChallenge: record.keyChallenge ? { id: record.keyChallenge.id, name: record.keyChallenge.name,
        personId: record.keyChallenge.personId, expiresAtMs: record.keyChallenge.expiresAtMs } : null,
      keysConfirmed: Boolean(record.keysConfirmedAtMs), meters: record.meters ?? null, beforeMeters: current.state.meters,
      report: record.report ?? null, responses: record.responses ?? {}, decisions: record.decisions ?? {}, ownersApproved,
      proposals: Object.values(record.proposals ?? {}), pendingOwnerReview,
      ownerApprovals: record.ownerApprovals ?? {}, shares: current.role === 'tenant' ? shares.filter(person => person.personId === current.person.id) : shares,
      destination: current.destination ? { method: current.destination.method, maskedAccount: current.destination.maskedAccount,
        name: current.destination.name, ifsc: current.destination.ifsc, verificationStatus: current.destination.verificationStatus } : null,
      inspectionComplete: current.rooms.every(room => room.items.every(item => item.absentReason && !item.beforeId ||
        item.afterId && item.comparison?.afterId === item.afterId && item.comparison.beforeId === item.beforeId)),
      handoverComplete: Boolean(record.handoverCompleteAtMs), ownerDecisionDueAtMs: record.ownerDecisionDueAtMs ?? null,
      refundTargetAtMs: record.keysConfirmedAtMs ? record.keysConfirmedAtMs + 7 * 86400000 : null,
      deliveryStatus: 'in_app_only', financialReconciliationRequired: true };
  }
  async function photo(current, transaction, id, purpose, itemId, actorUid = current.agreement.brokerUid) {
    requireValue(safe(id), 'Add a reviewed private photo.', 'invalid-argument');
    const result = await transaction.get(`properties/${current.agreement.propertyId}/photoChecks/${id}`);
    requireValue(result?.file && result.agreementId === current.agreementId && result.revision === current.agreement.revision &&
      result.createdBy === actorUid && result.purpose === purpose && result.itemId === itemId &&
      !['flagged', 'rejected'].includes(result.status), 'This photo is not evidence for this home, item and signed revision.', 'invalid-argument');
    return result;
  }
  return {
    async read(input) { return store.transaction(async transaction => summary(await context(transaction, input))); },
    async record(input) {
      requireValue(/^[a-f0-9]{32}$/.test(input.operationId ?? '') && Number.isSafeInteger(input.version) && input.version >= 1 &&
        ['book', 'compare', 'charge', 'meters', 'keys', 'confirm_keys', 'publish', 'respond', 'owner_approve', 'propose', 'review_proposal', 'decide', 'destination', 'refund_request', 'complete'].includes(input.action),
        'Choose a move-out action and saved version.', 'invalid-argument');
      return store.transaction(async transaction => {
        const current = await context(transaction, input);
        const record = current.record;
        const operationPath = `moveOutOperations/${hash([auth.uid, input.agreementId, input.operationId])}`;
        const previous = await transaction.get(operationPath);
        const fingerprint = hash([input.role, input.version, input.action, input.payload]);
        if (previous) {
          requireValue(previous.fingerprint === fingerprint, 'Retry the same move-out action.', 'aborted');
          return previous.codeAccepted === false ? { saved: false, codeAccepted: false, message: 'That key-return code is not correct.' }
            : { saved: true, version: record.version };
        }
        requireValue(record.version === input.version, 'This move-out changed on another device. Reload before saving.', 'aborted');
        const payload = input.payload ?? {};
        const state = summary(current);
        let patch = {};
        const writes = [];
        if (['compare', 'charge', 'meters', 'keys', 'confirm_keys', 'publish', 'complete'].includes(input.action)) {
          requireValue(current.broker, 'Only the approved linked broker can record the physical handover.', 'permission-denied');
          requireValue(indianDay(now()) >= record.date, 'Physical handover is recorded on or after the notice move-out day.');
        }
        if (['compare', 'charge', 'meters', 'keys'].includes(input.action)) requireValue(!record.report && !record.handoverCompleteAtMs,
          'The published evidence is frozen. Ask the team to correct it through review.');
        if (input.action === 'book') {
          requireValue(!record.keysConfirmedAtMs && validDate(payload.date) && payload.date >= record.date && payload.date >= indianDay(now()) &&
            ['09:00–12:00', '12:00–15:00', '15:00–18:00'].includes(payload.slot), 'Choose a check on or after the move-out date.', 'invalid-argument');
          requireValue(current.role !== 'tenant' || record.personIds.includes(current.person.id), 'Only a departing tenant can book this check.', 'permission-denied');
          patch = { booking: { date: payload.date, slot: payload.slot, requestedBy: auth.uid, status: 'requested', createdAtMs: now() } };
        }
        if (input.action === 'compare') {
          const item = current.rooms.flatMap(room => room.items).find(item => item.id === payload.itemId);
          requireValue(item?.beforeId && ['same', 'repair', 'damaged', 'missing'].includes(payload.condition) && money(payload.costPaise) &&
            typeof payload.note === 'string' && payload.note.length <= 1000 &&
            (payload.condition === 'same' ? payload.costPaise === 0 : note(payload.note)), 'Choose a condition and explain any proposed repair cost.', 'invalid-argument');
          await photo(current, transaction, payload.checkId, 'move_out', item.id);
          patch = { comparisons: { ...(record.comparisons ?? {}), [item.id]: { condition: payload.condition, costPaise: payload.costPaise,
            note: payload.note.trim(), beforeId: item.beforeId, afterId: payload.checkId, recordedBy: auth.uid, recordedAtMs: now() } } };
        }
        if (input.action === 'meters') {
          const meters = { noGas: current.state.meters.noGas === true };
          for (const kind of ['electricity', 'water', ...(meters.noGas ? [] : ['gas'])]) {
            const meter = payload[kind];
            requireValue(typeof meter?.reading === 'string' && /^\d{1,12}(?:\.\d{1,3})?$/.test(meter.reading) &&
              Number(meter.reading) >= Number(current.state.meters[kind].reading), `Check the final ${kind} reading against the move-in reading.`, 'invalid-argument');
            await photo(current, transaction, meter.checkId, 'move_out_meter', kind);
            meters[kind] = { reading: meter.reading, checkId: meter.checkId };
          }
          patch = { meters };
        }
      if (input.action === 'charge') {
          requireValue(['key', 'utility'].includes(payload.kind) && money(payload.amountPaise) && payload.amountPaise > 0 &&
            note(payload.note) && typeof payload.title === 'string' && payload.title.trim().length >= 3 && payload.title.length <= 80,
            'Name and explain the proposed key or utility charge.', 'invalid-argument');
          if (payload.kind === 'key') requireValue(record.keysConfirmedAtMs && keyKinds.some(kind =>
            (record.returnedKeys[kind] ?? 0) < (current.state.keys[kind] ?? 0)), 'No missing key is recorded.');
          if (payload.kind === 'utility') await photo(current, transaction, payload.checkId, 'move_out_meter', payload.meter);
          requireValue(!Object.values(record.charges ?? {}).some(charge => charge.kind === payload.kind && charge.meter === (payload.meter ?? null)),
            'This key or utility charge is already recorded. Do not add the same bill twice.');
          const id = hash(['move-out-charge', input.operationId]).slice(0, 32);
          patch = { charges: { ...(record.charges ?? {}), [id]: { id, kind: payload.kind, title: payload.title.trim(),
            room: payload.kind === 'key' ? 'Keys' : 'Utilities', meter: payload.meter ?? null, amountPaise: payload.amountPaise,
            note: payload.note.trim(), afterId: payload.checkId ?? null } } };
        }
        if (input.action === 'keys') {
          requireValue(!record.keyChallenge || now() - record.keyChallenge.createdAtMs >= 30000, 'Wait 30 seconds before preparing another key return.', 'resource-exhausted');
          const limit = await transaction.get(`moveOutKeyLimits/${hash([input.agreementId, record.createdAtMs])}`);
          requireValue((limit?.lockedUntilMs ?? 0) <= now(), 'Key return is locked for 15 minutes after five incorrect codes.');
          requireValue(payload.counts && Object.keys(payload.counts).length === keyKinds.length && keyKinds.every(kind =>
            Number.isSafeInteger(payload.counts[kind]) && payload.counts[kind] >= 0 && payload.counts[kind] <= (current.state.keys[kind] ?? 0)),
            'Count the actual returned keys; they cannot exceed the recorded handover.', 'invalid-argument');
          const person = current.people.find(person => person.personId === payload.personId);
          requireValue(person, 'Choose a departing tenant to confirm returned keys.', 'invalid-argument');
          const id = hash([input.agreementId, record.createdAtMs, input.operationId]);
          patch = { returnedKeys: payload.counts, keyChallenge: { id, personId: person.personId, uid: person.uid, name: person.name,
            createdAtMs: now(), expiresAtMs: now() + 15 * 60000 } };
          writes.push([`moveOutKeyChallenges/${id}`, { agreementId: input.agreementId, revision: current.agreement.revision,
            uid: person.uid, personId: person.personId, status: 'waiting_tenant', attempts: 0, expiresAtMs: patch.keyChallenge.expiresAtMs }]);
        }
        if (input.action === 'confirm_keys') {
          const challenge = await transaction.get(`moveOutKeyChallenges/${record.keyChallenge?.id ?? 'missing'}`);
          const limitPath = `moveOutKeyLimits/${hash([input.agreementId, record.createdAtMs])}`;
          const limit = await transaction.get(limitPath);
          requireValue((limit?.lockedUntilMs ?? 0) <= now(), 'Key return is locked for 15 minutes after five incorrect codes.');
          requireValue(challenge?.status === 'issued' && challenge.expiresAtMs > now() && payload.challengeId === record.keyChallenge?.id &&
            /^\d{6}$/.test(payload.code ?? ''), 'Ask the chosen tenant for the current key-return code.', 'invalid-argument');
          const expected = Buffer.from(challenge.codeHash, 'hex');
          const actual = Buffer.from(hash([record.keyChallenge.id, payload.code]), 'hex');
          if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
            const attempts = (limit?.attempts ?? 0) + 1;
            transaction.set(limitPath, { attempts, lockedUntilMs: attempts >= 5 ? now() + 15 * 60000 : 0 });
            transaction.set(operationPath, { fingerprint, actorUid: auth.uid, codeAccepted: false, createdAtMs: now() });
            return { saved: false, codeAccepted: false, message: 'That key-return code is not correct.' };
          }
          patch = { keysConfirmedAtMs: now(), keyChallenge: null, keyConfirmedBy: challenge.uid,
            ownerDecisionDueAtMs: dateTime(indianDay(now())) + (24 * 60 - 330) * 60000 };
          writes.push([`moveOutKeyChallenges/${record.keyChallenge.id}`, { ...challenge, status: 'used', usedAtMs: now() }]);
        }
        if (input.action === 'publish') {
          requireValue(!record.report && state.inspectionComplete && record.meters && record.keysConfirmedAtMs && current.people.every(person => person.depositVerified),
            'Finish every comparison, meters, confirmed key return and captured-deposit reconciliation before publishing.');
          const lines = [...current.rooms.flatMap(room => room.items.filter(item => (item.comparison?.costPaise ?? 0) > 0).map(item => ({
            id: item.id, title: item.title, room: room.room, amountPaise: item.comparison.costPaise, note: item.comparison.note,
            beforeId: item.beforeId, afterId: item.afterId, shares: splitMoveOutCost(item.comparison.costPaise, current.people),
          }))), ...Object.values(record.charges ?? {}).map(charge => ({ ...charge, shares: splitMoveOutCost(charge.amountPaise, current.people) }))];
          requireValue(lines.reduce((total, line) => total + line.amountPaise, 0) <= current.people.reduce((total, person) => total + person.depositPaise, 0),
            'Proposed deductions exceed captured deposits. The team must reconcile additional amounts separately.');
          patch = { report: { version: record.version + 1, lines, publishedAtMs: now(), publishedBy: auth.uid },
            status: 'awaiting_decisions', ownerApprovals: {}, responses: {}, decisions: {} };
        }
        if (['respond', 'owner_approve', 'propose', 'review_proposal', 'decide', 'destination', 'refund_request', 'complete'].includes(input.action)) {
          requireValue(record.report && payload.reportVersion === record.report.version, 'Open the current published move-out report.', 'aborted');
        }
        if (input.action === 'respond') {
          requireValue(current.role === 'tenant' && record.personIds.includes(current.person.id), 'Only a departing tenant can answer their own deductions.', 'permission-denied');
          requireValue(['agreed', 'disputed'].includes(payload.status), 'Agree or question an item.', 'invalid-argument');
          const line = record.report.lines.find(line => line.id === payload.itemId);
          requireValue(line && !record.decisions?.[line.id], 'Choose an undecided item.', 'invalid-argument');
          const response = { status: payload.status, actorUid: auth.uid, createdAtMs: now() };
          if (payload.status === 'disputed') {
            requireValue(note(payload.reason), 'Explain the questioned item in at least ten characters.', 'invalid-argument');
            if (payload.checkId) await photo(current, transaction, payload.checkId, 'move_out_dispute', line.id, auth.uid);
            Object.assign(response, { reason: payload.reason.trim(), checkId: payload.checkId ?? null, reviewTargetAtMs: now() + 2 * 86400000 });
          }
          requireValue(!record.responses?.[current.person.id]?.[line.id], 'This response is already saved. Ask the team to review changes.');
          patch = { responses: { ...(record.responses ?? {}), [current.person.id]: { ...(record.responses?.[current.person.id] ?? {}), [line.id]: response } } };
        }
        if (input.action === 'owner_approve') {
          requireValue(current.role === 'owner' && payload.reviewedAllItems === true, 'Only a verified owner can approve the reviewed report.', 'permission-denied');
          patch = { ownerApprovals: { ...(record.ownerApprovals ?? {}), [current.person.id]: { reportVersion: record.report.version, actorUid: auth.uid, createdAtMs: now() } } };
        }
        if (input.action === 'propose') {
          requireValue(current.role === 'owner', 'Only a verified owner can propose a missed deduction.', 'permission-denied');
          requireValue(!current.refundRequests.some(Boolean), 'A refund is already queued. The team must reconcile changes separately.');
          const item = current.rooms.flatMap(room => room.items).find(item => item.id === payload.itemId);
          requireValue(item?.beforeId && item.afterId && money(payload.amountPaise) && payload.amountPaise > 0 && note(payload.reason) &&
            !record.report.lines.some(line => line.id === item.id) && !Object.values(record.proposals ?? {}).some(proposal => proposal.itemId === item.id && proposal.status === 'pending'),
            'Choose an inspected item not already deducted and explain the missed cost.', 'invalid-argument');
          const id = hash([auth.uid, input.operationId]).slice(0, 32);
          const room = current.rooms.find(room => room.items.some(value => value.id === item.id));
          patch = { proposals: { ...(record.proposals ?? {}), [id]: { id, itemId: item.id, title: item.title, room: room.room,
            beforeId: item.beforeId, afterId: item.afterId, amountPaise: payload.amountPaise, reason: payload.reason.trim(),
            proposedBy: auth.uid, proposedAtMs: now(), reportVersion: record.report.version, status: 'pending' } } };
        }
        if (input.action === 'review_proposal') {
          requireValue(current.admin, 'Only the team can review a missed-item proposal.', 'permission-denied');
          const proposal = record.proposals?.[payload.proposalId];
          requireValue(proposal?.status === 'pending' && proposal.reportVersion === record.report.version &&
            ['accept', 'reject'].includes(payload.decision) && note(payload.reason), 'Open a current proposal and explain its review.', 'invalid-argument');
          requireValue(!current.refundRequests.some(Boolean), 'A refund is already queued. Reconcile any further change separately.');
          patch.proposals = { ...record.proposals, [proposal.id]: { ...proposal, status: payload.decision === 'accept' ? 'accepted' : 'rejected',
            reviewedBy: auth.uid, reviewedAtMs: now(), reviewReason: payload.reason.trim() } };
          if (payload.decision === 'accept') {
            requireValue(money(payload.amountPaise) && payload.amountPaise > 0 && payload.amountPaise <= proposal.amountPaise,
              'The reviewed cost must be positive and no larger than the owner’s proposal.', 'invalid-argument');
            const lines = [...record.report.lines, { id: proposal.itemId, title: proposal.title, room: proposal.room,
              beforeId: proposal.beforeId, afterId: proposal.afterId, amountPaise: payload.amountPaise, note: payload.reason.trim(),
              shares: splitMoveOutCost(payload.amountPaise, current.people) }];
            requireValue(lines.reduce((sum, line) => sum + line.amountPaise, 0) <= current.people.reduce((sum, person) => sum + person.depositPaise, 0),
              'Reviewed deductions exceed captured deposits. Reconcile excess separately.');
            writes.push([`moveOuts/${input.agreementId}/reports/${record.report.version}`, { ...record.report,
              ownerApprovals: record.ownerApprovals ?? {}, responses: record.responses ?? {}, decisions: record.decisions ?? {} }]);
            for (const pending of Object.values(patch.proposals)) if (pending.status === 'pending') {
              patch.proposals[pending.id] = { ...pending, status: 'superseded' };
            }
            Object.assign(patch, { report: { version: record.version + 1, lines, publishedBy: auth.uid, publishedAtMs: now(), sourceVersion: record.report.version },
              responses: {}, ownerApprovals: {}, decisions: {}, status: 'awaiting_decisions' });
          }
        }
        if (input.action === 'decide') {
          requireValue(current.admin, 'Only the team can decide a disputed deduction.', 'permission-denied');
          const line = record.report.lines.find(line => line.id === payload.itemId);
          requireValue(line && current.people.some(person => record.responses?.[person.personId]?.[line.id]?.status === 'disputed') &&
            !record.decisions?.[line.id] && money(payload.amountPaise) && payload.amountPaise <= line.amountPaise && note(payload.reason),
            'Keep, reduce or remove a disputed item and explain the evidence-based decision.', 'invalid-argument');
          patch = { decisions: { ...(record.decisions ?? {}), [line.id]: { amountPaise: payload.amountPaise,
            reason: payload.reason.trim(), decidedBy: auth.uid, decidedAtMs: now(), reportVersion: record.report.version } } };
        }
        if (input.action === 'destination') {
          requireValue(current.role === 'tenant' && record.personIds.includes(current.person.id) &&
            ['original_payment', 'bank_review'].includes(payload.method), 'Choose your own refund destination.', 'permission-denied');
          requireValue(!current.refundRequests.some(request => request?.personId === current.person.id),
            'This refund destination is locked to the queued request. Ask the team to reconcile any change.');
          const destination = { method: payload.method, createdBy: auth.uid, updatedAtMs: now(), verificationStatus: 'pending_provider' };
          if (payload.method === 'bank_review') {
            requireValue(typeof payload.name === 'string' && payload.name.trim().length >= 2 && payload.name.length <= 100 &&
              /^\d{9,18}$/.test(payload.account ?? '') && /^[A-Z]{4}0[A-Z0-9]{6}$/.test(payload.ifsc ?? '') && payload.inMyName === true,
              'Enter a bank account in your name. The team must verify it before any transfer.', 'invalid-argument');
            Object.assign(destination, { name: payload.name.trim(), account: payload.account, maskedAccount: `•••• ${payload.account.slice(-4)}`, ifsc: payload.ifsc });
          }
          writes.push([`moveOuts/${input.agreementId}/destinations/${current.person.id}`, destination]);
        }
        if (input.action === 'refund_request') {
          requireValue(current.admin && state.ownersApproved && record.handoverCompleteAtMs, 'The team requests a refund after handover and all-owner review.', 'permission-denied');
          requireValue(!state.pendingOwnerReview, 'Review all pending owner proposals before preparing a refund request.');
          const person = current.people.find(person => person.personId === payload.personId);
          const share = state.shares.find(share => share.personId === payload.personId);
          requireValue(person?.depositVerified && share?.refundableNowPaise > 0, 'No verified undisputed amount is currently refundable.');
          requireValue(current.rentRows.filter(row => record.personIds.includes(row.personId)).every(row => row.status === 'paid'),
            'Reconcile all departing tenants’ captured rent before preparing a refund request.');
          const destination = await transaction.get(`moveOuts/${input.agreementId}/destinations/${person.personId}`);
          requireValue(destination, 'The tenant must choose their refund destination first.');
          const refundPath = `moveOutRefundRequests/${hash([input.agreementId, person.personId])}`;
          const existing = await transaction.get(refundPath);
          requireValue(!existing, 'A refund is already requested. Reconcile its provider outcome before requesting another.');
          writes.push([refundPath, { agreementId: input.agreementId, revision: current.agreement.revision, reportVersion: record.report.version,
            personId: person.personId, uid: person.uid, paymentId: person.paymentId, amountPaise: share.refundableNowPaise,
            method: destination.method, status: 'awaiting_provider', createdBy: auth.uid, createdAtMs: now(), targetAtMs: record.keysConfirmedAtMs + 7 * 86400000 }]);
        }
        if (input.action === 'complete') {
          requireValue(state.inspectionComplete && record.keysConfirmedAtMs && record.meters && !record.handoverCompleteAtMs,
            'Complete the recorded photos, final meters and confirmed keys first.');
          requireValue(payload.confirmedPhysicalHandover === true, 'Confirm the home was physically handed back.', 'invalid-argument');
          patch = { handoverCompleteAtMs: now(), handoverCompletedBy: auth.uid, status: 'awaiting_settlement' };
        }
        for (const [path, data] of writes) transaction.set(path, data);
        transaction.update(`moveOuts/${input.agreementId}`, { ...patch, version: record.version + 1, revision: current.agreement.revision,
          updatedAtMs: now(), deliveryStatus: 'in_app_only' });
        transaction.set(operationPath, { fingerprint, actorUid: auth.uid, createdAtMs: now() });
        transaction.set(`agreements/${input.agreementId}/events/${hash(['move_out', auth.uid, input.operationId])}`, {
          action: `move_out.${input.action}`, actorUid: auth.uid, actorRole: current.role, revision: current.agreement.revision,
          createdAtMs: now(), reportVersion: record.report?.version ?? null });
        return { saved: true, version: record.version + 1, moneyTransferred: false };
      });
    },
    async issueCode(input) {
      requireValue(input.countsConfirmed === true, 'Confirm the returned key count first.', 'invalid-argument');
      return store.transaction(async transaction => {
        const current = await context(transaction, input);
        const challenge = current.record.keyChallenge;
        requireValue(current.role === 'tenant' && challenge?.personId === current.person.id && challenge.uid === auth.uid,
          'Only the selected departing tenant can confirm these returned keys.', 'permission-denied');
        const limit = await transaction.get(`moveOutKeyLimits/${hash([input.agreementId, current.record.createdAtMs])}`);
        const saved = await transaction.get(`moveOutKeyChallenges/${challenge.id}`);
        requireValue((limit?.lockedUntilMs ?? 0) <= now() && saved && ['waiting_tenant', 'issued'].includes(saved.status) &&
          saved.expiresAtMs > now(), 'This key return expired or is locked.');
        requireValue(!saved.issuedAtMs || now() - saved.issuedAtMs >= 30000, 'Wait 30 seconds before requesting another code.', 'resource-exhausted');
        const value = code();
        requireValue(/^\d{6}$/.test(value), 'A key-return code could not be created.', 'internal');
        const expiresAtMs = Math.min(challenge.expiresAtMs, now() + 5 * 60000);
        transaction.update(`moveOutKeyChallenges/${challenge.id}`, { status: 'issued', issuedAtMs: now(),
          codeHash: hash([challenge.id, value]), expiresAtMs });
        return { code: value, expiresAtMs, challengeId: challenge.id, delivery: 'authenticated_tenant_screen' };
      });
    },
  };
}
