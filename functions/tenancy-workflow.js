import { createHash, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';
import { verifiedPhone } from './verified-phone.js';
import { reviewSnapshot } from './agreement-review.js';
import { approvalDigest } from './agreement-approvals.js';
import { rentPeriods } from './rent-payments.js';
import { moveInPlan } from './move-in-plan.js';

export class TenancyError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const requireValue = (value, message, code = 'failed-precondition') => {
  if (!value) throw new TenancyError(code, message);
};
const safe = value => typeof value === 'string' && /^[\w-]{1,100}$/.test(value);
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const indianDay = milliseconds => new Date(milliseconds + 330 * 60000).toISOString().slice(0, 10);
const dayTime = value => Date.parse(`${value}T00:00:00Z`);
function validDate(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    Number.isFinite(dayTime(value)) && new Date(dayTime(value)).toISOString().slice(0, 10) === value;
}
function monthsAfter(value, months) {
  const original = new Date(dayTime(value));
  const next = new Date(Date.UTC(original.getUTCFullYear(), original.getUTCMonth() + months, 1));
  next.setUTCDate(Math.min(original.getUTCDate(), new Date(Date.UTC(next.getUTCFullYear(), next.getUTCMonth() + 1, 0)).getUTCDate()));
  return next.toISOString().slice(0, 10);
}

export function createTenancyService({ auth, store, now = Date.now, code = () => String(randomInt(100000, 1000000)), eventId = randomUUID }) {
  async function context(transaction, input, { rentThroughDate = null } = {}) {
    requireValue(auth?.uid, 'Log in to open this home.', 'unauthenticated');
    requireValue(safe(input.agreementId) && ['broker', 'owner', 'tenant', 'admin'].includes(input.role),
      'Choose a linked home and role.', 'invalid-argument');
    const profile = await transaction.get(`users/${auth.uid}`);
    requireValue(profile && profile.paused !== true && profile.roles?.includes(input.role), 'This role is unavailable.', 'permission-denied');
    const agreement = await transaction.get(`agreements/${input.agreementId}`);
    const copy = agreement?.agreementCopy;
    requireValue(agreement && safe(agreement.propertyId), 'This agreement has no linked property. Ask the team to correct it.');
    const property = await transaction.get(`properties/${agreement.propertyId}`);
    requireValue(property, 'The linked property is unavailable.');
    const broker = input.role === 'broker' && agreement.brokerUid === auth.uid && property.brokerUid === auth.uid && profile.approvalStatus === 'approved';
    const admin = input.role === 'admin';
    const matches = (copy?.people ?? []).filter(person => person.uid === auth.uid && person.role === input.role &&
      person.phone === verifiedPhone(auth));
    requireValue(admin || broker || agreement.participantUids?.includes(auth.uid) && matches.length === 1,
      'This home is not linked to your verified role.', 'permission-denied');
    const snapshot = reviewSnapshot(agreement);
    requireValue(copy?.mode === 'externally_signed' && copy.revision === agreement.revision &&
      copy.digest === approvalDigest(snapshot) && ['signed_copy_received', 'active'].includes(agreement.status),
      'A completed signed original of the current agreement is required. Demo copies cannot start a tenancy.');
    requireValue(['owner', 'tenant'].every(role => snapshot[role === 'owner' ? 'owners' : 'tenants'].every(person =>
      copy.people.filter(link => link.id === person.id && link.role === role && safe(link.uid) && link.phone === person.phone).length === 1)),
      'Every owner and tenant must be linked to their verified account.');
    const state = await transaction.get(`tenancies/${input.agreementId}`) ?? {
      version: 0, revision: agreement.revision, digest: copy.digest, phase: 'preparing', absentItems: {}, meters: null, keys: null,
    };
    requireValue(state.revision === agreement.revision && state.digest === copy.digest, 'The signed agreement changed. Ask the team to reconcile this home.');
    const photoIds = [...new Set(Object.values(state.photoSlots ?? {}))];
    requireValue(photoIds.length <= 250 && photoIds.every(safe), 'The move-in evidence index needs team reconciliation.');
    const photos = (await Promise.all(photoIds.map(async id => {
      const photo = await transaction.get(`properties/${agreement.propertyId}/photoChecks/${id}`);
      return photo ? { ...photo, id } : null;
    }))).filter(Boolean);
    const matching = photos.filter(photo => photo.agreementId === input.agreementId && photo.revision === agreement.revision &&
      photo.createdBy === agreement.brokerUid && photo.actorRole === 'broker' && photo.file && !['flagged', 'rejected'].includes(photo.status));
    const plan = moveInPlan(agreement, state.roomConfiguration);
    const rows = plan.map(room => ({ ...room, items: room.items.map(item => ({ ...item,
      checkId: matching.find(photo => photo.purpose === 'move_in' && photo.itemId === item.id)?.id ?? null,
      absentReason: state.absentItems[item.id] ?? null,
    })) }));
    const photoComplete = Boolean(state.roomConfiguration) && rows.length > 0 && rows.every(room => room.items.every(item => item.checkId || item.optional && item.absentReason));
    const paymentRows = [];
    const rentRows = [];
    const paymentCache = new Map();
    async function readPayment(id) {
      if (!safe(id)) return null;
      if (!paymentCache.has(id)) paymentCache.set(id, transaction.get(`payments/${id}`));
      return paymentCache.get(id);
    }
    for (const person of snapshot.tenants) {
      const accountId = hash(['live', input.agreementId, agreement.revision, person.id]);
      const account = await transaction.get(`rentPaymentAccounts/${accountId}`);
      const payment = await readPayment(account?.firstPaymentId);
      const periods = rentPeriods(snapshot, person.id);
      const month = account?.firstPaymentMonth ?? (indianDay(now()).slice(0, 7) < periods[0].month ? periods[0].month : indianDay(now()).slice(0, 7));
      const period = periods.find(period => period.month === month);
      const linked = copy.people.find(link => link.id === person.id && link.role === 'tenant');
      const paid = account?.depositPaid === true && account.paidMonths?.includes(month) && payment?.mode === 'live' && payment.currency === 'INR' &&
        payment.status === 'paid' && payment.providerVerified === true && payment.captured === true &&
        payment.agreementId === input.agreementId && payment.revision === agreement.revision && payment.payerUid === linked.uid &&
        payment.depositPaise === person.depositSharePaise && payment.lines?.some(line => line.month === month && line.totalPaise === period?.totalPaise) &&
        payment.amountPaise === payment.depositPaise + payment.lines.reduce((total, line) => total + line.totalPaise, 0) &&
        (payment.refundedPaise ?? 0) === 0;
      paymentRows.push({ personId: person.id, uid: linked.uid, name: person.name, month,
        amountPaise: period ? period.totalPaise + person.depositSharePaise : null, paid: Boolean(paid) });
      const rentThrough = validDate(rentThroughDate) && rentThroughDate < indianDay(now())
        ? rentThroughDate : indianDay(now());
      const duePeriods = periods.filter(period => period.from <= rentThrough);
      let unpaid = null;
      for (const duePeriod of duePeriods) {
        const paidId = account?.paymentIdsByMonth?.[duePeriod.month];
        const capture = duePeriod.month === month && paid ? payment : await readPayment(paidId);
        const line = capture?.lines?.find(line => line.month === duePeriod.month);
        const verified = capture?.mode === 'live' && capture.currency === 'INR' && capture.status === 'paid' && capture.providerVerified === true && capture.captured === true &&
          capture.agreementId === input.agreementId && capture.revision === agreement.revision && capture.payerUid === linked.uid &&
          line?.totalPaise === duePeriod.totalPaise && capture.amountPaise === (capture.depositPaise ?? 0) +
            capture.lines.reduce((total, item) => total + item.totalPaise, 0) && (capture.refundedPaise ?? 0) === 0;
        if (!verified) { unpaid = duePeriod; break; }
      }
      const followUpPath = unpaid ? `tenancies/${input.agreementId}/rentFollowUps/${hash([agreement.revision, person.id, unpaid.month])}` : null;
      const followUp = followUpPath ? await transaction.get(followUpPath) : null;
      const dueDate = unpaid ? new Date(Math.max(dayTime(`${unpaid.month}-${String(snapshot.rentDueDay).padStart(2, '0')}`),
        unpaid.from.endsWith('-01') ? 0 : dayTime(unpaid.from) + 5 * 86400000)).toISOString().slice(0, 10) : null;
      const deadline = followUp?.extension?.date ?? dueDate;
      const daysLate = unpaid ? Math.max(0, Math.floor((dayTime(indianDay(now())) - dayTime(deadline)) / 86400000)) : 0;
      rentRows.push({ personId: person.id, uid: linked.uid, name: person.name, phone: person.phone,
        month: unpaid?.month ?? duePeriods.at(-1)?.month ?? null, amountPaise: unpaid?.totalPaise ?? 0,
        status: unpaid ? 'unpaid' : 'paid', dueDate, deadline, daysLate, lateFeePaise: 0,
        manualNoticeReviewRequired: Boolean(unpaid && daysLate >= 30), followUp: followUp ?? null, followUpPath });
    }
    const moneyComplete = paymentRows.length > 0 && paymentRows.every(person => person.paid);
    const meterComplete = state.meters && ['electricity', 'water'].every(kind => {
      const meter = state.meters[kind];
      return meter && matching.some(photo => photo.id === meter.checkId && photo.purpose === 'move_in_meter' && photo.itemId === kind);
    }) && (state.meters.noGas === true || matching.some(photo => photo.id === state.meters.gas?.checkId && photo.purpose === 'move_in_meter' && photo.itemId === 'gas'));
    const gate = moneyComplete && photoComplete && Boolean(meterComplete) && indianDay(now()) >= snapshot.startDateISO.slice(0, 10) &&
      indianDay(now()) <= snapshot.endDateISO.slice(0, 10) && (!property.activeAgreementId || property.activeAgreementId === input.agreementId);
    return { agreement, property, snapshot, copy, state, broker, admin, person: matches[0], rows, matching,
      moneyComplete, photoComplete, meterComplete: Boolean(meterComplete), paymentRows, rentRows, gate, role: input.role, agreementId: input.agreementId };
  }
  function summary(current) {
    const { state } = current;
    return { agreementId: current.agreementId, propertyId: current.agreement.propertyId, address: current.snapshot.propertyAddress,
      role: current.role, revision: current.agreement.revision, version: state.version, phase: state.phase, startDate: current.snapshot.startDateISO.slice(0, 10),
      endDate: current.snapshot.endDateISO.slice(0, 10), today: indianDay(now()), canEdit: current.broker,
      moneyComplete: current.moneyComplete, photoComplete: current.photoComplete, meterComplete: current.meterComplete,
      canHandOver: current.broker && current.gate && state.phase !== 'active', payments: current.paymentRows, rooms: current.rows,
      meters: state.meters, keys: state.keys, challenge: state.challenge ? { id: state.challenge.id,
        personId: state.challenge.personId, name: state.challenge.name, expiresAtMs: state.challenge.expiresAtMs } : null,
      canIssueCode: current.role === 'tenant' && current.gate && state.phase !== 'active' && state.challenge?.personId === current.person.id,
      myPersonId: current.person?.id ?? null, movedInAtMs: state.movedInAtMs ?? null, nextInspectionDate: state.nextInspectionDate ?? null,
      notice: state.notice ?? null, earliestMoveOutDate: monthsAfter(indianDay(now()), current.snapshot.noticeMonths),
      lockInEnds: monthsAfter(current.snapshot.startDateISO.slice(0, 10), current.snapshot.lockInMonths),
      noticeMonths: current.snapshot.noticeMonths,
      roomConfiguration: state.roomConfiguration ?? null,
      rent: current.rentRows.map(({ followUpPath, ...row }) => row),
    };
  }
  function requireBroker(current) { requireValue(current.broker, 'Only the approved linked broker can record this handover.', 'permission-denied'); }
  return {
    context,
    async read(input) { return store.transaction(async transaction => summary(await context(transaction, input))); },
    async record(input) {
      requireValue(/^[a-f0-9]{32}$/.test(input.operationId ?? '') && Number.isSafeInteger(input.version) && input.version >= 0 &&
        ['rooms', 'meters', 'absent', 'keys', 'confirm', 'notice', 'rent_call', 'rent_promise', 'rent_extension'].includes(input.action), 'Choose a saved action and version.', 'invalid-argument');
      const operationPath = `tenancyOperations/${hash([auth?.uid, input.agreementId, input.operationId])}`;
      const fingerprint = hash([input.role, input.action, input.version, input.payload]);
      return store.transaction(async transaction => {
        const current = await context(transaction, input);
        const previous = await transaction.get(operationPath);
        const limitPath = `keyHandoverLimits/${hash([current.agreementId, current.agreement.revision])}`;
        const limit = ['keys', 'confirm'].includes(input.action) ? await transaction.get(limitPath) : null;
        if (previous) {
          requireValue(previous.fingerprint === fingerprint, 'Retry this exact action, not a different form.', 'aborted');
          return summary(current);
        }
        requireValue(current.state.version === input.version, 'This home changed on another device. Refresh before saving.', 'aborted');
        const payload = input.payload ?? {};
        let patch;
        let challengeWrite;
        let wrongCode;
        let followUpWrite;
        if (['rooms', 'meters', 'absent', 'keys', 'confirm'].includes(input.action)) {
          requireBroker(current);
          requireValue(current.state.phase !== 'active', 'The completed handover cannot be edited.');
        }
        if (input.action === 'rooms') {
          requireValue(Number.isInteger(payload.bedrooms) && payload.bedrooms >= 0 && payload.bedrooms <= 9 &&
            Number.isInteger(payload.washrooms) && payload.washrooms >= 1 && payload.washrooms <= 9 && typeof payload.balcony === 'boolean' &&
            payload.confirmedPhysicalLayout === true, 'Confirm the actual bedrooms, washrooms and balcony at this home.', 'invalid-argument');
          requireValue(Object.keys(current.state.photoSlots ?? {}).length === 0, 'The room plan is frozen once move-in evidence is received. Contact support to correct it.');
          patch = { roomConfiguration: { bedrooms: payload.bedrooms, washrooms: payload.washrooms, balcony: payload.balcony },
            roomPlanConfirmedBy: auth.uid, roomPlanConfirmedAtMs: now(), challenge: null };
        }
        if (input.action === 'absent') {
          const item = current.rows.flatMap(room => room.items).find(item => item.id === payload.itemId);
          requireValue(item?.optional && (payload.clear === true || typeof payload.reason === 'string' && payload.reason.trim().length >= 10 && payload.reason.length <= 500),
            'Only an optional item can be marked not present; explain what is absent.', 'invalid-argument');
          const absentItems = { ...current.state.absentItems };
          if (payload.clear === true) delete absentItems[payload.itemId]; else absentItems[payload.itemId] = payload.reason.trim();
          patch = { absentItems, challenge: null };
        }
        if (input.action === 'meters') {
          const meters = { noGas: payload.noGas === true };
          for (const kind of ['electricity', 'water', ...(meters.noGas ? [] : ['gas'])]) {
            const meter = payload[kind];
            requireValue(meter && typeof meter.reading === 'string' && /^\d{1,12}(?:\.\d{1,3})?$/.test(meter.reading) &&
              current.matching.some(photo => photo.id === meter.checkId && photo.purpose === 'move_in_meter' && photo.itemId === kind),
              `Add a new ${kind} meter photo and a valid reading.`, 'invalid-argument');
            meters[kind] = { reading: meter.reading, checkId: meter.checkId };
          }
          patch = { meters, challenge: null };
        }
        if (input.action === 'keys') {
          requireValue((limit?.lockedUntilMs ?? 0) <= now(), 'Key confirmation is locked for 15 minutes after five incorrect codes.');
          requireValue(!current.state.challenge || now() - current.state.challenge.createdAtMs >= 30000,
            'Wait 30 seconds before preparing another key confirmation.', 'resource-exhausted');
          requireValue(current.gate, 'Keys require the current signed original, every tenant’s LIVE captured payment, room records and meters on move-in day. TEST payments do not release keys.');
          const kinds = ['mainDoor', 'bedrooms', 'letterBox', 'parkingCard'];
          requireValue(payload.counts && Object.keys(payload.counts).length === kinds.length && kinds.every(kind =>
            Number.isSafeInteger(payload.counts[kind]) && payload.counts[kind] >= 0 && payload.counts[kind] <= 50) &&
            kinds.reduce((total, kind) => total + payload.counts[kind], 0) > 0, 'Count all keys and access cards.', 'invalid-argument');
          const recipient = current.copy.people.find(person => person.role === 'tenant' && person.id === payload.personId);
          requireValue(recipient, 'Choose the tenant receiving the keys.', 'invalid-argument');
          const id = hash([current.agreementId, current.agreement.revision, input.operationId]);
          patch = { keys: payload.counts, challenge: { id, personId: recipient.id, uid: recipient.uid, name: recipient.name,
            createdAtMs: now(), expiresAtMs: now() + 15 * 60000 } };
          challengeWrite = { path: `keyHandoverChallenges/${id}`, data: { agreementId: current.agreementId,
            uid: recipient.uid, personId: recipient.id, revision: current.agreement.revision, attempts: 0, issuedAtMs: null,
            expiresAtMs: patch.challenge.expiresAtMs, status: 'waiting_tenant', counts: payload.counts } };
        }
        if (input.action === 'confirm') {
          requireValue((limit?.lockedUntilMs ?? 0) <= now(), 'Key confirmation is locked for 15 minutes after five incorrect codes.');
          requireValue(current.gate, 'The signing, payment, photo or meter gate changed. Keys cannot be confirmed.');
          requireValue(/^[a-f0-9]{64}$/.test(payload.challengeId ?? '') && /^\d{6}$/.test(payload.code ?? '') &&
            current.state.challenge?.id === payload.challengeId, 'Ask the selected tenant for their current confirmation code.', 'invalid-argument');
          const challenge = await transaction.get(`keyHandoverChallenges/${payload.challengeId}`);
          requireValue(challenge?.status === 'issued' && challenge.revision === current.agreement.revision &&
            challenge.expiresAtMs > now() && (challenge.lockedUntilMs ?? 0) <= now(), 'This code expired or is locked. The tenant must request a new code.');
          const expected = Buffer.from(challenge.codeHash, 'hex');
          const actual = Buffer.from(hash([payload.challengeId, payload.code]), 'hex');
          if (!timingSafeEqual(expected, actual)) {
            const attempts = challenge.attempts + 1;
            const failures = limit && now() - limit.firstFailureAtMs < 15 * 60000 ? limit.failures + 1 : 1;
            transaction.set(limitPath, { failures, firstFailureAtMs: failures === 1 ? now() : limit.firstFailureAtMs,
              lockedUntilMs: failures >= 5 ? now() + 15 * 60000 : 0 });
            challengeWrite = { path: `keyHandoverChallenges/${payload.challengeId}`, data: { ...challenge, attempts,
              ...(attempts >= 5 ? { status: 'locked', lockedUntilMs: now() + 15 * 60000 } : {}) } };
            wrongCode = true;
          } else {
            requireValue(current.paymentRows.some(person => person.personId === challenge.personId && person.uid === challenge.uid), 'The receiving tenant changed.');
            patch = { phase: 'active', movedInAtMs: now(), movedInBy: auth.uid,
              keyRecipientUid: challenge.uid, keyRecipientId: challenge.personId, challenge: null,
              nextInspectionDate: monthsAfter(indianDay(now()), 3),
              baselinePhotoIds: current.rows.flatMap(room => room.items).map(item => item.checkId).filter(Boolean) };
            challengeWrite = { path: `keyHandoverChallenges/${payload.challengeId}`, data: { ...challenge, status: 'used', usedAtMs: now() } };
          }
        }
        if (input.action === 'notice') {
          requireValue(current.state.phase === 'active' && !current.state.notice, 'A completed move-in is required and only one current notice is allowed.');
          const earliest = monthsAfter(indianDay(now()), current.snapshot.noticeMonths);
          const lockInEnds = monthsAfter(current.snapshot.startDateISO.slice(0, 10), current.snapshot.lockInMonths);
          requireValue(validDate(payload.date) && payload.date >= earliest && payload.date <= monthsAfter(indianDay(now()), 12) &&
            (payload.date >= lockInEnds || payload.lockInAcknowledged === true), 'Choose a date after the notice period and acknowledge any lock-in warning.', 'invalid-argument');
          requireValue(Array.isArray(payload.personIds) && payload.personIds.length > 0 && new Set(payload.personIds).size === payload.personIds.length &&
            payload.personIds.every(id => current.snapshot.tenants.some(person => person.id === id)) &&
            (current.role !== 'tenant' || payload.personIds.includes(current.person.id)), 'Choose the tenants moving out.', 'invalid-argument');
          requireValue(typeof payload.reason === 'string' && payload.reason.length <= 1000 && ['owner', 'tenant'].includes(payload.requestedBy), 'Choose who requested the move-out.', 'invalid-argument');
          requireValue(current.role !== 'tenant' || payload.requestedBy === 'tenant', 'A tenant notice must be from the tenant.', 'permission-denied');
          requireValue(current.role !== 'owner' || payload.requestedBy === 'owner', 'An owner notice must be from the owner.', 'permission-denied');
          const notice = { date: payload.date, personIds: payload.personIds, reason: payload.reason.trim(), requestedBy: payload.requestedBy,
            createdBy: auth.uid, createdAtMs: now(), lockInAcknowledged: payload.date < lockInEnds,
            status: 'notice_received', participantUids: current.agreement.participantUids,
            deliveryStatus: 'in_app_only', refundStatus: 'not_started' };
          patch = { notice };
        }
        if (input.action.startsWith('rent_')) {
          requireValue(current.state.phase === 'active', 'A completed live move-in is required for rent follow-up. TEST payments never create a live tenancy.');
          const rent = current.rentRows.find(row => row.personId === payload.personId && row.month === payload.month && row.status === 'unpaid');
          requireValue(rent, 'That rental period is already paid or changed. Refresh the rent record.', 'aborted');
          requireValue(typeof payload.note === 'string' && payload.note.trim().length >= 10 && payload.note.length <= 1000,
            'Explain the conversation, promise or extension in at least ten characters.', 'invalid-argument');
          const followUp = rent.followUp ?? { version: 0, history: [] };
          const event = { action: input.action, actorUid: auth.uid, actorRole: current.role, note: payload.note.trim(), createdAtMs: now() };
          const updated = { ...followUp, personId: rent.personId, month: rent.month, version: followUp.version + 1,
            history: [...followUp.history, event].slice(-50), updatedAtMs: now() };
          if (input.action === 'rent_call') {
            requireValue(current.broker || current.admin, 'Only the linked broker or team can save a follow-up call.', 'permission-denied');
            requireValue(payload.contacted === true, 'Record the call only after speaking to the tenant.', 'invalid-argument');
            updated.lastCall = event;
          } else {
            requireValue(validDate(payload.date) && payload.date > indianDay(now()) && dayTime(payload.date) <= dayTime(indianDay(now())) + 90 * 86400000,
              'Choose a future date within 90 days.', 'invalid-argument');
            if (input.action === 'rent_promise') {
              requireValue(current.role === 'tenant' && current.person.id === rent.personId, 'Only that tenant can record their payment promise.', 'permission-denied');
              updated.promise = { ...event, date: payload.date, status: 'requested', amountPaise: rent.amountPaise };
            } else {
              requireValue(current.role === 'owner' || current.broker || current.admin, 'Only an owner, linked broker or team can grant more time.', 'permission-denied');
              requireValue(current.role === 'owner' || payload.ownerInformed === true, 'Speak to the owner before granting more time.', 'invalid-argument');
              requireValue(payload.date >= rent.deadline, 'More time must not shorten the original payment deadline.', 'invalid-argument');
              requireValue(!followUp.extension || payload.date >= followUp.extension.date, 'A new extension cannot shorten the existing last date.', 'invalid-argument');
              updated.extension = { ...event, date: payload.date, ownerInformed: true, deliveryStatus: 'in_app_only' };
            }
          }
          followUpWrite = { path: rent.followUpPath, data: updated };
          patch = {};
        }
        if (challengeWrite) transaction.set(challengeWrite.path, challengeWrite.data);
        if (wrongCode) return { codeAccepted: false, message: 'That code is not correct. Ask the tenant for the current code.' };
        if (followUpWrite) transaction.set(followUpWrite.path, followUpWrite.data);
        const saved = { ...current.state, ...patch, version: current.state.version + 1, updatedAtMs: now(),
          agreementId: current.agreementId, propertyId: current.agreement.propertyId, participantUids: current.agreement.participantUids };
        transaction.set(`tenancies/${current.agreementId}`, saved);
        if (patch.phase === 'active') {
          transaction.update(`agreements/${current.agreementId}`, { status: 'active', updatedAtMs: now() });
          transaction.update(`properties/${current.agreement.propertyId}`, { activeAgreementId: current.agreementId,
            occupancyStatus: 'rented', nextInspectionDate: patch.nextInspectionDate, updatedAtMs: now() });
        }
        if (patch.notice) transaction.set(`moveOuts/${current.agreementId}`, { ...patch.notice, agreementId: current.agreementId,
          propertyAddress: current.snapshot.propertyAddress, version: 1 });
        transaction.set(operationPath, { fingerprint, actorUid: auth.uid, action: input.action, createdAtMs: now() });
        transaction.set(`agreements/${current.agreementId}/events/${eventId()}`, { action: `tenancy.${input.action}`, actorUid: auth.uid,
          createdAtMs: now(), revision: current.agreement.revision, version: saved.version });
        return { saved: true, version: saved.version, phase: saved.phase };
      });
    },
    async issueCode(input) {
      requireValue(input.countsConfirmed === true, 'Confirm the displayed key count before sharing a code.', 'invalid-argument');
      return store.transaction(async transaction => {
        const current = await context(transaction, input);
        requireValue(current.role === 'tenant' && current.gate && current.state.phase !== 'active' &&
          current.state.challenge?.personId === current.person.id && current.state.challenge.uid === auth.uid,
          'Only the selected verified tenant can confirm these keys.', 'permission-denied');
        const challenge = await transaction.get(`keyHandoverChallenges/${current.state.challenge.id}`);
        requireValue(challenge && ['waiting_tenant', 'issued', 'locked'].includes(challenge.status) &&
          challenge.expiresAtMs > now() && (challenge.lockedUntilMs ?? 0) <= now(), 'This handover expired or is locked. Ask the broker to prepare it again.');
        requireValue(!challenge.issuedAtMs || now() - challenge.issuedAtMs >= 30000, 'Wait 30 seconds before requesting another code.', 'resource-exhausted');
        const value = code();
        requireValue(/^\d{6}$/.test(value), 'A confirmation code could not be created.', 'internal');
        transaction.update(`keyHandoverChallenges/${current.state.challenge.id}`, { status: 'issued', codeHash: hash([current.state.challenge.id, value]),
          issuedAtMs: now(), expiresAtMs: Math.min(current.state.challenge.expiresAtMs, now() + 5 * 60000), attempts: 0 });
        transaction.set(`agreements/${current.agreementId}/events/${eventId()}`, { action: 'tenancy.key_count_confirmed', actorUid: auth.uid,
          createdAtMs: now(), revision: current.agreement.revision, challengeId: current.state.challenge.id });
        return { code: value, expiresAtMs: Math.min(current.state.challenge.expiresAtMs, now() + 5 * 60000),
          delivery: 'authenticated_tenant_screen', challengeId: current.state.challenge.id };
      });
    },
  };
}
