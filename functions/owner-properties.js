import { createHash } from 'node:crypto';
import { verifiedPhone } from './verified-phone.js';
import { validateImportFiles } from './agreement-imports.js';

export class OwnerPropertyError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const requireValue = (condition, message, code = 'failed-precondition') => {
  if (!condition) throw new OwnerPropertyError(code, message);
};
const safe = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
export const ownerFeatures = ['AC', 'Geyser', 'Fridge', 'Washing machine', 'Cupboard', 'Chimney', 'Sofa', 'Bed',
  'Lift', 'Car parking', 'Power backup', 'Security', 'Gym', 'Pool', 'Garden', 'Gas line'];
const fields = [['address', 'name', 'homeType'], ['rooms', 'bathrooms', 'balconies', 'floor', 'totalFloors', 'sizeSqFt', 'furnishing'],
  ['features', 'pets'], ['rentPaise', 'maintenancePaise', 'depositPaise', 'availableFrom', 'whoCanStay', 'negotiable'], ['teamPhotos']];
const text = (value, minimum, maximum) => typeof value === 'string' && value.trim().length >= minimum && value.trim().length <= maximum;
const integer = (value, minimum, maximum) => Number.isSafeInteger(value) && value >= minimum && value <= maximum;
const date = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
  Number.isFinite(Date.parse(`${value}T00:00:00Z`)) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;

export function validateOwnerPropertyStep(step, input) {
  requireValue(integer(step, 0, 4) && input && !Array.isArray(input) && Object.keys(input).every(key => fields[step].includes(key)),
    'Save only the details for this step.', 'invalid-argument');
  let valid = false;
  if (step === 0) valid = text(input.address, 0, 500) && text(input.name, 0, 100) &&
    ['Apartment', 'House', 'Villa', 'Studio', 'Other'].includes(input.homeType);
  if (step === 1) valid = ['1 RK', '1 BHK', '2 BHK', '3 BHK', '4 BHK', '4+ BHK'].includes(input.rooms) &&
    integer(input.bathrooms, 0, 30) && integer(input.balconies, 0, 30) && integer(input.floor, 0, 200) &&
    integer(input.totalFloors, input.floor, 200) && integer(input.sizeSqFt, 1, 100000) && ['Empty', 'Semi', 'Full'].includes(input.furnishing);
  if (step === 2) valid = Array.isArray(input.features) && input.features.length <= ownerFeatures.length &&
    new Set(input.features).size === input.features.length && input.features.every(value => ownerFeatures.includes(value)) &&
    ['Yes', 'No', 'Ask me'].includes(input.pets);
  if (step === 3) valid = integer(input.rentPaise, 1, 1000000000) && integer(input.maintenancePaise, 0, 1000000000) &&
    integer(input.depositPaise, 0, 1000000000) && date(input.availableFrom) &&
    ['Family', 'Men only', 'Women only', 'Anyone'].includes(input.whoCanStay) && typeof input.negotiable === 'boolean';
  if (step === 4) valid = typeof input.teamPhotos === 'boolean';
  requireValue(valid, 'Complete the required property details with valid amounts, counts and dates.', 'invalid-argument');
  return Object.fromEntries(Object.entries(input).map(([key, value]) => [key, typeof value === 'string' ? value.trim() : value]));
}

export function createOwnerPropertyService({ auth, store, files, now = Date.now }) {
  async function identity(transaction, admin = false) {
    requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
    const profile = await transaction.get(`users/${auth.uid}`);
    requireValue(profile?.paused !== true && (admin ? profile?.roles?.includes('admin') :
      profile?.roles?.includes('owner') && verifiedPhone(auth) === profile.phone),
    'An active, verified owner account is required.', 'permission-denied');
    return profile;
  }
  async function home(transaction, id, admin = false) {
    requireValue(safe(id), 'Open a saved property.', 'invalid-argument');
    await identity(transaction, admin);
    const value = await transaction.get(`ownerProperties/${id}`);
    requireValue(value && (admin || value.ownerUid === auth.uid), 'This property is private to its owner.', 'permission-denied');
    return value;
  }
  function audit(transaction, id, revision, action, detail = {}) {
    transaction.set(`adminAuditLogs/owner-property-${id}-${revision}`, { actorUid: auth.uid,
      propertyId: id, revision, action, ...detail, createdAtMs: now() });
  }
  function view(id, value) {
    const { photos, ...data } = value;
    const contract = value.contract;
    const fileView = file => file ? { size: file.size, sha256: file.sha256, pageCount: file.pageCount } : null;
    return { id, ...data, photos: (photos ?? []).map(({ path, generation, ...file }) => file),
      ...(contract ? { contract: { ...contract, sourceFile: fileView(contract.sourceFile), signedFile: fileView(contract.signedFile) } } : {}) };
  }
  return {
    async list({ admin = false } = {}) {
      await store.transaction(transaction => identity(transaction, admin));
      const values = await store.list(admin ? null : auth.uid, 100);
      return { properties: values.map(({ id, ...value }) => view(id, value)) };
    },
    async save({ id, operationId, revision, step, input }) {
      const value = validateOwnerPropertyStep(step, input);
      requireValue(integer(revision, 0, Number.MAX_SAFE_INTEGER) && (id == null || safe(id)) &&
        typeof operationId === 'string' && /^[a-f0-9]{32}$/.test(operationId), 'Reopen your saved property.', 'invalid-argument');
      const propertyId = id ?? hash([auth?.uid, operationId]);
      const payloadDigest = hash([step, value]);
      return store.transaction(async transaction => {
        await identity(transaction);
        const current = await transaction.get(`ownerProperties/${propertyId}`);
        const property = await transaction.get(`properties/${propertyId}`);
        const limit = await transaction.get(`ownerPropertyLimits/${auth.uid}`);
        requireValue(!current || current.ownerUid === auth.uid, 'This property belongs to another account.', 'permission-denied');
        requireValue(!property || property.ownerUid === auth.uid ||
          (Array.isArray(property.participantUids) && property.participantUids.includes(auth.uid)),
          'This property belongs to another account.', 'permission-denied');
        if (current?.lastOperationId === operationId) {
          requireValue(current.lastPayloadDigest === payloadDigest, 'This save attempt has different details. Refresh the saved property.', 'already-exists');
          return view(propertyId, current);
        }
        requireValue((current?.revision ?? 0) === revision, 'This property changed on another device. Refresh before saving.', 'aborted');
        requireValue(current ? step <= current.nextStep : step === 0, 'Complete the earlier property steps first.');
        requireValue(!current || ['draft', 'property_added', 'plan_requested', 'check_requested'].includes(current.status),
          'The contract or listing needs team review before these details change.');
        requireValue(!property?.activeAgreementId, 'This home already has a tenancy. Ask your manager to change its listing details.');
        if (!current) requireValue((limit?.windowEndsAtMs > now() ? limit.count : 0) < 10,
          'Too many new properties. Try again in an hour.', 'resource-exhausted');
        const details = { ...current?.details, ...value };
        if (step === 4) {
          for (let check = 0; check < 4; check++) validateOwnerPropertyStep(check,
            Object.fromEntries(fields[check].map(key => [key, details[key]])));
          requireValue(details.teamPhotos === true || current.photos?.length > 0,
            'Add 1 to 5 clear property photos, or request our team to take them.');
        }
        const next = { ownerUid: auth.uid, revision: revision + 1, details,
          nextStep: Math.max(current?.nextStep ?? 0, Math.min(step + 1, 4)),
          status: step === 4 ? 'property_added' : 'draft', photos: current?.photos ?? [],
          createdAtMs: current?.createdAtMs ?? now(), updatedAtMs: now(), lastOperationId: operationId, lastPayloadDigest: payloadDigest };
        if (!current) transaction.set(`ownerPropertyLimits/${auth.uid}`, {
          count: (limit?.windowEndsAtMs > now() ? limit.count : 0) + 1,
          windowEndsAtMs: limit?.windowEndsAtMs > now() ? limit.windowEndsAtMs : now() + 3600000 });
        transaction.set(`ownerProperties/${propertyId}`, next);
        if (step === 4) transaction.set(`properties/${propertyId}`, { ...property,
          ownerUid: auth.uid, participantUids: property?.participantUids ?? [auth.uid], address: details.address || details.name,
          name: details.name || details.address, rooms: details.rooms, floor: details.floor, totalFloors: details.totalFloors,
          sizeSqFt: details.sizeSqFt, furnishing: details.furnishing, source: 'owner_self_onboarding',
          ownerOnboardingId: propertyId, updatedAtMs: now() });
        audit(transaction, propertyId, revision + 1, step === 4 ? 'owner_property_added' : 'owner_property_step_saved', { step });
        return view(propertyId, next);
      });
    },
    async beginPhotos({ id, revision, operationId, specs, admin = false }) {
      let validated;
      try { validated = validateImportFiles(specs); } catch { throw new OwnerPropertyError('invalid-argument', 'Add 1 to 5 JPG/PNG photos, up to 10 MB each and 20 MB in total.'); }
      requireValue(validated.length <= 5 && validated.every(file => file.contentType !== 'application/pdf' && file.size <= 10485760) &&
        typeof operationId === 'string' && /^[a-f0-9]{32}$/.test(operationId), 'Choose 1 to 5 clear photos.', 'invalid-argument');
      const uploadId = hash([auth?.uid, id, operationId]);
      return store.transaction(async transaction => {
        const current = await home(transaction, id, admin);
        const existing = await transaction.get(`ownerPropertyUploads/${uploadId}`);
        const payload = hash([id, revision, validated]);
        if (existing) {
          requireValue(existing.payload === payload && existing.uid === auth.uid && (existing.admin === true) === admin, 'Keep the same photos for this retry.', 'already-exists');
          requireValue(existing.status === 'completed' || existing.expiresAtMs > now(), 'This photo upload expired.');
          return { uploadId, completed: existing.status === 'completed', paths: validated.map((_, index) => `ownerPropertyUploads/${auth.uid}/${uploadId}/${index}`) };
        }
        requireValue(current.revision === revision && current.nextStep === 4 &&
          ['draft', 'property_added', 'check_requested', 'check_confirmed', 'fee_offered', 'contract_accepted', 'plan_active', 'listing_paused'].includes(current.status) && !current.chosenTenantId,
          'Refresh and finish the earlier steps before adding photos.', 'aborted');
        transaction.set(`ownerPropertyUploads/${uploadId}`, { uid: auth.uid, propertyId: id, revision, admin,
          specs: validated, payload, status: 'uploading', expiresAtMs: now() + 3600000 });
        return { uploadId, completed: false, paths: validated.map((_, index) => `ownerPropertyUploads/${auth.uid}/${uploadId}/${index}`) };
      });
    },
    async completePhotos({ uploadId, admin = false }) {
      requireValue(safe(uploadId), 'Choose the current photos.', 'invalid-argument');
      const grant = await store.transaction(async transaction => {
        await identity(transaction, admin);
        const upload = await transaction.get(`ownerPropertyUploads/${uploadId}`);
        requireValue(upload?.uid === auth?.uid && (upload.admin === true) === admin, 'These photos belong to another account.', 'permission-denied');
        const current = await home(transaction, upload.propertyId, admin);
        requireValue(upload.status === 'completed' || upload.expiresAtMs > now() && current.revision === upload.revision,
          'This home changed or the upload expired. Refresh.', 'aborted');
        return upload;
      });
      if (grant.status === 'completed') return this.read({ id: grant.propertyId, admin });
      const photos = await files.snapshot(grant, uploadId);
      const result = await store.transaction(async transaction => {
        const upload = await transaction.get(`ownerPropertyUploads/${uploadId}`);
        const current = await home(transaction, grant.propertyId, admin);
        if (upload.status === 'completed') return view(grant.propertyId, current);
        requireValue(upload.expiresAtMs > now() && current.revision === grant.revision, 'This home changed. Refresh.', 'aborted');
        const next = { ...current, photos, revision: current.revision + 1, updatedAtMs: now() };
        transaction.set(`ownerProperties/${grant.propertyId}`, next);
        transaction.update(`ownerPropertyUploads/${uploadId}`, { status: 'completed' });
        audit(transaction, grant.propertyId, next.revision, 'owner_property_photos_received', { photoCount: photos.length });
        return view(grant.propertyId, next);
      });
      await files.cleanup(grant, uploadId).catch(() => {});
      return result;
    },
    async read({ id, admin = false }) { return store.transaction(async transaction => view(id, await home(transaction, id, admin))); },
    async readPhoto({ id, index, admin = false }) {
      const current = await store.transaction(transaction => home(transaction, id, admin));
      requireValue(integer(index, 0, (current.photos?.length ?? 0) - 1), 'This photo is not available.', 'not-found');
      const file = current.photos[index]; return { ...file, path: undefined, generation: undefined, base64: await files.read(file) };
    },
    async requestPlan({ id, revision, plan, method, day, slot }) {
      requireValue(['diy', 'full_service'].includes(plan) && ['visit', 'video'].includes(method) && date(day) &&
        Date.parse(`${day}T00:00:00+05:30`) <= now() + 60 * 86400000 &&
        ['10:00–12:00', '12:00–14:00', '16:00–18:00'].includes(slot), 'Pick a plan, a future day and a time for the free check.', 'invalid-argument');
      requireValue(Date.parse(`${day}T${slot.slice(0, 5)}:00+05:30`) > now(), 'Choose a check time that has not passed.', 'invalid-argument');
      return store.transaction(async transaction => {
        const current = await home(transaction, id);
        requireValue(current.revision === revision && ['property_added', 'plan_requested', 'check_requested'].includes(current.status),
          'Refresh the saved property before requesting a plan.', 'aborted');
        const next = { ...current, status: 'check_requested', revision: revision + 1,
          plan, check: { status: 'requested', method, day, slot, requestedAtMs: now() }, updatedAtMs: now() };
        transaction.set(`ownerProperties/${id}`, next);
        audit(transaction, id, revision + 1, 'owner_plan_check_requested', { plan, method, day, slot });
        return view(id, next);
      });
    },
    async recordCheck({ id, revision, action, managerName, managerPhone, day, slot, reference, notes = '',
      feeBps, effectiveFrom, checkCompleted }) {
      requireValue(integer(revision, 1, Number.MAX_SAFE_INTEGER) && ['confirm', 'offer_fee'].includes(action) &&
        text(reference, 3, 200) && text(notes, 0, 1000), 'Record the actual check reference and current revision.', 'invalid-argument');
      if (action === 'confirm') requireValue(text(managerName, 2, 100) && /^\+91[0-9]{10}$/.test(managerPhone ?? '') &&
        date(day) && ['10:00–12:00', '12:00–14:00', '16:00–18:00'].includes(slot) &&
        Date.parse(`${day}T${slot.slice(0, 5)}:00+05:30`) > now() && Date.parse(`${day}T00:00:00+05:30`) <= now() + 60 * 86400000,
        'Record the assigned manager and an actual future appointment.', 'invalid-argument');
      if (action === 'offer_fee') requireValue(integer(feeBps, 500, 2000) && date(effectiveFrom) && checkCompleted === true &&
        effectiveFrom >= new Date(now() + 19800000).toISOString().slice(0, 10),
        'Complete the real home check, then record a 5–20% offer with its effective date.', 'invalid-argument');
      return store.transaction(async transaction => {
        const current = await home(transaction, id, true);
        requireValue(current.revision === revision, 'This property changed. Refresh before recording the check.', 'aborted');
        requireValue(action === 'confirm' ? ['check_requested', 'check_confirmed'].includes(current.status) : current.status === 'check_confirmed',
          'Confirm the requested check before recording the completed check and fee.');
        const next = { ...current, revision: revision + 1, status: action === 'confirm' ? 'check_confirmed' : 'fee_offered', updatedAtMs: now() };
        if (action === 'confirm') next.check = { ...current.check, status: 'confirmed', managerName: managerName.trim(),
          managerPhone, day, slot, reference: reference.trim(), confirmedByUid: auth.uid, confirmedAtMs: now() };
        else {
          requireValue(Date.parse(`${current.check.day}T${current.check.slot.slice(0, 5)}:00+05:30`) <= now(),
            'The confirmed visit has not occurred yet. Record a fee only after the actual check.');
          next.check = { ...current.check, status: 'completed', completedAtMs: now(), completedByUid: auth.uid };
          next.feeOffer = { version: revision + 1, feeBps, effectiveFrom, reference: reference.trim(), notes: notes.trim(),
            recordedByUid: auth.uid, recordedAtMs: now(), status: 'offered' };
        }
        transaction.set(`ownerProperties/${id}`, next);
        audit(transaction, id, revision + 1, action === 'confirm' ? 'owner_check_confirmed' : 'owner_fee_offered',
          { reference: reference.trim(), notes: notes.trim(), ...(action === 'offer_fee' ? { feeBps, effectiveFrom, checkCompleted } : { day, slot, managerName: managerName.trim(), managerPhone }) });
        return view(id, next);
      });
    },
  };
}
