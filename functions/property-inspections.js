import { createHash } from 'node:crypto';
import { moveInPlan } from './move-in-plan.js';

export class InspectionError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const requireValue = (value, message, code = 'failed-precondition') => {
  if (!value) throw new InspectionError(code, message);
};
const safe = value => typeof value === 'string' && /^[\w-]{1,100}$/.test(value);
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const rooms = ['Living room', 'Kitchen', ...Array.from({ length: 9 }, (_, index) => `Bedroom ${index + 1}`),
  ...Array.from({ length: 9 }, (_, index) => `Washroom ${index + 1}`), 'Balcony / utility', 'Fixtures & fittings'];

export function createInspectionService({ auth, store, files, now = Date.now }) {
  async function context(transaction, propertyId, role, selectedAgreementId) {
    requireValue(auth?.uid, 'Log in to open photo checks.', 'unauthenticated');
    requireValue(safe(propertyId), 'Choose a property.', 'invalid-argument');
    const profile = await transaction.get(`users/${auth.uid}`);
    requireValue(profile && profile.paused !== true, 'This account cannot open photo checks.', 'permission-denied');
    const property = await transaction.get(`properties/${propertyId}`);
    requireValue(property, 'This property is unavailable.', 'not-found');
    const admin = profile.roles?.includes('admin');
    const broker = profile.roles?.includes('broker') && profile.approvalStatus === 'approved' && property.brokerUid === auth.uid;
    const agreementId = selectedAgreementId ?? property.agreementId;
    const agreement = safe(agreementId) ? await transaction.get(`agreements/${agreementId}`) : null;
    requireValue(!selectedAgreementId || agreement?.propertyId === propertyId, 'Choose this property’s linked agreement.', 'permission-denied');
    const copy = agreement?.agreementCopy;
    const partyRoles = agreement?.propertyId === propertyId && agreement.participantUids?.includes(auth.uid) &&
      copy?.mode === 'externally_signed' && copy.revision === agreement.revision
      ? (copy.people ?? []).filter(person => person.uid === auth.uid && ['owner', 'tenant'].includes(person.role)).map(person => person.role) : [];
    const available = [...(broker ? ['broker'] : []), ...partyRoles];
    requireValue(admin || available.length > 0, 'This property is not linked to your account.', 'permission-denied');
    if (role !== undefined) requireValue(available.includes(role), 'Choose your linked property role.', 'permission-denied');
    return { profile, property, agreement, admin, broker, role: role ?? available[0] ?? 'admin',
      agreementId: agreement?.propertyId === propertyId ? agreementId : null };
  }
  function checkPath(propertyId, checkId) {
    requireValue(typeof checkId === 'string' && /^[a-f0-9]{32}$/.test(checkId), 'Choose a photo check.', 'invalid-argument');
    return `properties/${propertyId}/photoChecks/${checkId}`;
  }
  async function uploadContext(transaction, checkId) {
    requireValue(auth?.uid, 'Log in to save this photo.', 'unauthenticated');
    requireValue(/^[a-f0-9]{32}$/.test(checkId ?? ''), 'Choose the photo being uploaded.', 'invalid-argument');
    const upload = await transaction.get(`inspectionUploads/${checkId}`);
    requireValue(upload?.uid === auth.uid, 'This upload belongs to another account.', 'permission-denied');
    const current = await context(transaction, upload.propertyId, upload.role, upload.agreementId);
    const photo = await transaction.get(checkPath(upload.propertyId, checkId));
    return { ...current, upload, photo };
  }
  async function moveOutScope(transaction, current, input) {
    const tenancy = await transaction.get(`tenancies/${current.agreementId}`);
    const moveOut = await transaction.get(`moveOuts/${current.agreementId}`);
    requireValue(tenancy?.phase === 'active' && tenancy.notice && moveOut &&
      moveOut.createdAtMs === tenancy.notice.createdAtMs && current.agreement?.agreementCopy?.mode === 'externally_signed' &&
      tenancy.revision === current.agreement.revision && tenancy.digest === current.agreement.agreementCopy.digest,
      'Give notice from the current active signed home before recording move-out evidence.');
    if (input.purpose === 'move_out_dispute') {
      const person = current.agreement.agreementCopy.people.find(person => person.uid === auth.uid && person.role === 'tenant');
      requireValue(current.role === 'tenant' && person && moveOut.personIds.includes(person.id) &&
        moveOut.report?.lines.some(line => line.id === input.itemId), 'Only a departing tenant can add evidence for a published deduction.', 'permission-denied');
    } else {
      requireValue(current.broker && current.role === 'broker' && !moveOut.report && !moveOut.handoverCompleteAtMs,
        'Only the linked broker can add official evidence before the report is frozen.', 'permission-denied');
      requireValue(new Date(now() + 330 * 60000).toISOString().slice(0, 10) >= moveOut.date,
        'Take official move-out evidence on or after the notice date.');
      if (input.purpose === 'move_out') {
        const room = moveInPlan(current.agreement, tenancy.roomConfiguration).find(room => room.room === input.room);
        requireValue(room?.items.some(item => item.id === input.itemId && item.title === input.title.trim()),
          'Choose the actual item from this home’s frozen room plan.', 'invalid-argument');
      } else {
        requireValue(['electricity', 'water', 'gas'].includes(input.itemId) && input.room === 'Fixtures & fittings',
          'Choose this home’s final electricity, water or gas meter.', 'invalid-argument');
      }
    }
    return moveOut;
  }
  return {
    async list(input) {
      return store.transaction(async transaction => {
        const current = await context(transaction, input.propertyId, input.role, input.agreementId);
        const checks = await transaction.list(`properties/${input.propertyId}/photoChecks`, 100);
        return { propertyId: input.propertyId, address: current.property.address ?? current.property.propertyAddress ?? '',
          actorRole: current.role, canCapture: !current.admin,
          checks: checks.filter(check => current.admin || current.broker || check.agreementId === current.agreementId) };
      });
    },
    async begin(input) {
      requireValue(/^[a-f0-9]{32}$/.test(input.operationId ?? '') && rooms.includes(input.room) &&
        typeof input.title === 'string' && input.title.trim().length >= 2 && input.title.trim().length <= 80 &&
        typeof input.note === 'string' && input.note.length <= 1000 && input.source === 'camera',
      'Choose a room, name the item and take a new camera photo.', 'invalid-argument');
      const checkId = hash([auth?.uid, input.propertyId, input.operationId]).slice(0, 32);
      const purpose = input.purpose ?? 'regular';
      requireValue(['regular', 'move_in', 'move_in_meter', 'move_out', 'move_out_meter', 'move_out_dispute'].includes(purpose), 'Choose a photo record type.', 'invalid-argument');
      const payloadHash = hash([input.propertyId, input.room, input.title.trim(), input.note.trim(), input.role, 'camera', purpose, input.itemId ?? null]);
      return store.transaction(async transaction => {
        const current = await context(transaction, input.propertyId, input.role, input.agreementId);
        requireValue(!current.admin, 'Capture photos using your linked customer role.', 'permission-denied');
        if (purpose.startsWith('move_out')) await moveOutScope(transaction, current, { ...input, purpose });
        if (purpose === 'move_in' || purpose === 'move_in_meter') {
          requireValue(current.broker && current.role === 'broker' && current.agreement?.agreementCopy?.mode === 'externally_signed' &&
            current.agreement.agreementCopy.revision === current.agreement.revision, 'Only the linked broker can take official move-in evidence.', 'permission-denied');
          const tenancy = await transaction.get(`tenancies/${current.agreementId}`);
          requireValue(tenancy?.roomConfiguration && tenancy.revision === current.agreement.revision &&
            tenancy.digest === current.agreement.agreementCopy.digest, 'Confirm the actual room layout of this signed version before taking official move-in photos.');
          if (purpose === 'move_in') {
            const room = moveInPlan(current.agreement, tenancy.roomConfiguration).find(room => room.room === input.room);
            requireValue(room?.items.some(item => item.id === input.itemId && item.title === input.title.trim()),
              'Choose an item from this home’s move-in checklist.', 'invalid-argument');
          } else {
            requireValue(['electricity', 'water', 'gas'].includes(input.itemId) && input.room === 'Fixtures & fittings',
              'Choose the electricity, water or gas meter.', 'invalid-argument');
          }
          requireValue(tenancy?.phase !== 'active', 'The completed move-in record cannot be changed.');
        }
        const previous = await transaction.get(`inspectionUploads/${checkId}`);
        requireValue(!previous || previous.payloadHash === payloadHash && previous.agreementId === current.agreementId &&
          previous.role === current.role, 'Retry with the same agreement, room and item.', 'aborted');
        const upload = previous ?? { uid: auth.uid, propertyId: input.propertyId, agreementId: current.agreementId,
          role: current.role, room: input.room, title: input.title.trim(), note: input.note.trim(), payloadHash,
          actorName: current.profile.displayName?.trim() || 'Property participant', startedAtMs: now(),
          expiresAtMs: now() + 15 * 60 * 1000, status: 'uploading', source: 'camera', purpose,
          itemId: input.itemId ?? null, revision: current.agreement?.revision ?? null };
        requireValue(upload.status === 'submitted' || upload.expiresAtMs > now(), 'This upload expired. Take the photo again.');
        if (!previous) transaction.set(`inspectionUploads/${checkId}`, upload);
        return { checkId, path: `inspectionUploads/${auth.uid}/${checkId}/photo`, submitted: upload.status === 'submitted',
          actorName: upload.actorName, actorRole: upload.role, startedAtMs: upload.startedAtMs, expiresAtMs: upload.expiresAtMs };
      });
    },
    async submit(input) {
      const initial = await store.transaction(transaction => uploadContext(transaction, input.checkId));
      if (initial.photo) return { checkId: input.checkId, submitted: true };
      requireValue(initial.upload.expiresAtMs > now() && initial.upload.status === 'uploading', 'This upload expired. Take the photo again.');
      const file = await files.snapshot(auth.uid, input.checkId);
      await store.transaction(async transaction => {
        const current = await uploadContext(transaction, input.checkId);
        if (current.photo) return;
        requireValue(current.upload.expiresAtMs > now() && current.upload.status === 'uploading' &&
          current.agreementId === current.upload.agreementId && (current.agreement?.revision ?? null) === current.upload.revision,
          'The property or upload changed. Reopen photo checks.', 'aborted');
        const moveOut = current.upload.purpose.startsWith('move_out') ? await moveOutScope(transaction, current, current.upload) : null;
        const tenancy = ['move_in', 'move_in_meter'].includes(current.upload.purpose) ? await transaction.get(`tenancies/${current.agreementId}`) : null;
        requireValue(current.upload.purpose === 'regular' || moveOut || tenancy?.roomConfiguration && tenancy.revision === current.agreement.revision &&
          tenancy.digest === current.agreement.agreementCopy.digest, 'The move-in record is unavailable. Reopen the home.');
        if (tenancy) {
          requireValue(tenancy?.phase !== 'active', 'The completed move-in record cannot be changed.');
          requireValue(tenancy.roomConfiguration && (current.upload.purpose !== 'move_in' ||
            moveInPlan(current.agreement, tenancy.roomConfiguration).find(room => room.room === current.upload.room)?.items.some(item =>
              item.id === current.upload.itemId && item.title === current.upload.title)), 'The room plan changed. Retake this item from the current checklist.', 'aborted');
        }
        transaction.set(checkPath(current.upload.propertyId, input.checkId), {
          title: current.upload.title, room: current.upload.room, note: current.upload.note,
          propertyId: current.upload.propertyId, propertyAddress: current.property.address ?? current.property.propertyAddress ?? '',
          agreementId: current.agreementId, createdBy: auth.uid, actorName: current.upload.actorName,
          purpose: current.upload.purpose, itemId: current.upload.itemId, revision: current.upload.revision,
          actorRole: current.upload.role, captureStartedAtMs: current.upload.startedAtMs, receivedAtMs: now(),
          createdAt: store.timestamp(), source: 'camera', status: 'submitted', version: 1, file,
        });
        transaction.update(`inspectionUploads/${input.checkId}`, { status: 'submitted', submittedAtMs: now() });
        if (tenancy) transaction.update(`tenancies/${current.agreementId}`, {
          photoSlots: { ...(tenancy.photoSlots ?? {}), [`${current.upload.purpose}:${current.upload.itemId}`]: input.checkId },
          version: tenancy.version + 1, challenge: null, updatedAtMs: now(),
        });
        if (moveOut) {
          const patch = { version: moveOut.version + 1, updatedAtMs: now() };
          if (current.upload.purpose !== 'move_out_dispute') {
            patch.photoSlots = { ...(moveOut.photoSlots ?? {}), [`${current.upload.purpose}:${current.upload.itemId}`]: input.checkId };
            if (current.upload.purpose === 'move_out') {
              patch.comparisons = { ...(moveOut.comparisons ?? {}) };
              delete patch.comparisons[current.upload.itemId];
            }
          }
          transaction.update(`moveOuts/${current.agreementId}`, patch);
        }
      });
      try { await files.cleanup(auth.uid, input.checkId); } catch { }
      return { checkId: input.checkId, submitted: true };
    },
    async readPhoto(input) {
      const path = checkPath(input.propertyId, input.checkId);
      async function authorized(transaction) {
        const photo = await transaction.get(path);
        requireValue(photo?.file, 'This photo is unavailable.', 'not-found');
        await context(transaction, input.propertyId, undefined, photo.agreementId);
        return photo;
      }
      const photo = await store.transaction(authorized);
      const result = await files.read(input.checkId, photo.file);
      const refreshed = await store.transaction(authorized);
      requireValue(refreshed.file.generation === photo.file.generation, 'This photo changed. Try again.', 'aborted');
      return result;
    },
    async review(input) {
      const path = checkPath(input.propertyId, input.checkId);
      requireValue(['approved', 'flagged'].includes(input.status) && /^[a-f0-9]{32}$/.test(input.operationId ?? '') &&
        Number.isSafeInteger(input.version) && (input.status !== 'flagged' || typeof input.note === 'string' &&
          input.note.trim().length >= 10 && input.note.length <= 1000), 'Choose a review and explain flagged photos.', 'invalid-argument');
      return store.transaction(async transaction => {
        const current = await context(transaction, input.propertyId);
        requireValue(current.admin, 'Only support can review photo checks.', 'permission-denied');
        const photo = await transaction.get(path);
        requireValue(photo?.file, 'Open the uploaded photo before reviewing it.', 'not-found');
        const auditPath = `adminAuditLogs/${hash(['inspection-review', path, input.operationId])}`;
        const previous = await transaction.get(auditPath);
        const fingerprint = hash([input.status, input.note?.trim() ?? '', input.version]);
        if (previous) {
          requireValue(previous.actorUid === auth.uid && previous.fingerprint === fingerprint, 'Retry the same review.', 'aborted');
          return { status: previous.status, reviewed: true };
        }
        requireValue(photo.version === input.version && !photo.issueId, 'The photo review changed. Refresh it.', 'aborted');
        transaction.update(path, { status: input.status, version: photo.version + 1, reviewedBy: auth.uid,
          reviewedAt: store.timestamp(), reviewNote: input.status === 'flagged' ? input.note.trim() : '' });
        transaction.set(auditPath, { action: 'photo_check.reviewed', actorUid: auth.uid, targetPath: path,
          status: input.status, createdAtMs: now(), fingerprint });
        return { status: input.status, reviewed: true };
      });
    },
  };
}
