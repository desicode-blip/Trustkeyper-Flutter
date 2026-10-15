import { createHash } from 'node:crypto';
import { OwnerPropertyError } from './owner-properties.js';
import { verifiedPhone } from './verified-phone.js';

const digest = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const safe = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const text = (value, minimum, maximum) => typeof value === 'string' && value.trim().length >= minimum && value.trim().length <= maximum;
const integer = (value, minimum, maximum) => Number.isSafeInteger(value) && value >= minimum && value <= maximum;
const validDate = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
  Number.isFinite(Date.parse(`${value}T00:00:00Z`)) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
const requireValue = (condition, message, code = 'failed-precondition') => {
  if (!condition) throw new OwnerPropertyError(code, message);
};
export function ownerLifecycleView(id, value) {
  const fileView = file => file ? { size: file.size, sha256: file.sha256, pageCount: file.pageCount } : null;
  return { ...value, id, photos: (value.photos ?? []).map(({ path, generation, ...photo }) => photo),
    ...(value.contract ? { contract: { ...value.contract, sourceFile: fileView(value.contract.sourceFile),
      signedFile: fileView(value.contract.signedFile) } } : {}) };
}

export function createOwnerLifecycleService({ auth, store, files, photos, now = Date.now }) {
  async function identity(transaction, admin = false) {
    requireValue(auth?.uid, 'Log in again.', 'unauthenticated');
    const profile = await transaction.get(`users/${auth.uid}`);
    requireValue(profile?.paused !== true && (admin ? profile?.roles?.includes('admin') :
      profile?.roles?.includes('owner') && verifiedPhone(auth) === profile.phone), 'This account cannot change this property.', 'permission-denied');
    return profile;
  }
  async function home(transaction, id, admin = false) {
    requireValue(safe(id), 'Open a saved property.', 'invalid-argument');
    await identity(transaction, admin);
    const property = await transaction.get(`ownerProperties/${id}`);
    requireValue(property && (admin || property.ownerUid === auth.uid), 'This property is private to its owner.', 'permission-denied');
    return property;
  }
  function write(transaction, id, current, next, action, detail = {}) {
    next.revision = current.revision + 1; next.updatedAtMs = now();
    transaction.set(`ownerProperties/${id}`, next);
    transaction.set(`adminAuditLogs/owner-property-${id}-${next.revision}`, {
      action, actorUid: auth.uid, propertyId: id, revision: next.revision, ...detail, createdAtMs: now() });
    return ownerLifecycleView(id, next);
  }
  function currentRevision(property, revision) {
    requireValue(integer(revision, 1, Number.MAX_SAFE_INTEGER) && property.revision === revision,
      'This property changed on another device. Refresh before continuing.', 'aborted');
  }
  function listing(property) {
    requireValue(property?.listing?.status === 'live' && property.status === 'listing_live' && property.contract?.status === 'signed',
      'This listing is no longer available.', 'not-found');
    return { title: property.listing.title, locality: property.listing.locality,
      rooms: property.details.rooms, furnishing: property.details.furnishing, features: property.details.features,
      pets: property.details.pets, whoCanStay: property.details.whoCanStay, availableFrom: property.details.availableFrom,
      rentPaise: property.details.rentPaise, depositPaise: property.details.depositPaise,
      maintenancePaise: property.details.maintenancePaise, photoCount: property.photos?.length ?? 0 };
  }
  async function prospect(transaction) {
    requireValue(auth?.uid && verifiedPhone(auth), 'Verify your phone to contact TrustKeyper about this home.', 'unauthenticated');
    const profile = await transaction.get(`users/${auth.uid}`);
    requireValue(profile?.paused !== true, 'This account is paused.', 'permission-denied');
    return verifiedPhone(auth);
  }
  return {
    async beginContract({ id, revision, operationId, kind, spec, reference, originalChecked, signaturesChecked }) {
      requireValue(['source', 'signed'].includes(kind) && text(reference, 3, 200) &&
        typeof operationId === 'string' && /^[a-f0-9]{32}$/.test(operationId) &&
        spec?.contentType === 'application/pdf' && integer(spec.size, 1, 20971520) && safe(spec.sha256) &&
        originalChecked === true && (kind !== 'signed' || signaturesChecked === true),
      'Review the actual owner contract PDF, reference, terms and signatures before uploading.', 'invalid-argument');
      const uploadId = digest([auth?.uid, id, operationId, kind]);
      const payload = digest([id, revision, kind, spec, reference.trim()]);
      return store.transaction(async transaction => {
        const property = await home(transaction, id, true);
        const existing = await transaction.get(`ownerContractUploads/${uploadId}`);
        if (existing) {
          requireValue(existing.payload === payload && existing.uid === auth.uid, 'Keep the same PDF and reference for this retry.', 'already-exists');
          requireValue(existing.status === 'completed' || existing.expiresAtMs > now(), 'This upload expired.');
          return { uploadId, path: `ownerContractUploads/${auth.uid}/${uploadId}/contract.pdf`, completed: existing.status === 'completed' };
        }
        currentRevision(property, revision);
        requireValue(kind === 'source' ? property.status === 'fee_offered' && !property.contract?.consent :
          property.status === 'contract_accepted' && property.contract?.status === 'accepted',
        'Publish terms after the fee offer; publish a signed original only after owner consent.');
        requireValue(kind !== 'signed' || spec.sha256 !== property.contract.sourceFile.sha256,
          'The unsigned contract is not a signed original.', 'invalid-argument');
        transaction.set(`ownerContractUploads/${uploadId}`, { uid: auth.uid, propertyId: id, revision, kind, spec,
          reference: reference.trim(), payload, status: 'uploading', expiresAtMs: now() + 3600000,
          offerVersion: property.feeOffer.version, originalChecked: true, signaturesChecked: kind === 'signed' });
        return { uploadId, path: `ownerContractUploads/${auth.uid}/${uploadId}/contract.pdf`, completed: false };
      });
    },
    async completeContract({ uploadId }) {
      requireValue(safe(uploadId), 'Reopen the contract upload.', 'invalid-argument');
      const context = await store.transaction(async transaction => {
        await identity(transaction, true);
        const grant = await transaction.get(`ownerContractUploads/${uploadId}`);
        requireValue(grant?.uid === auth.uid, 'This upload belongs to another administrator.', 'permission-denied');
        const property = await home(transaction, grant.propertyId, true);
        if (grant.status !== 'completed') {
          currentRevision(property, grant.revision);
          requireValue(grant.expiresAtMs > now(), 'This upload expired.');
        }
        return { grant, property };
      });
      if (context.grant.status === 'completed') return ownerLifecycleView(context.grant.propertyId, context.property);
      const file = await files.snapshot(context.grant, uploadId);
      const result = await store.transaction(async transaction => {
        const property = await home(transaction, context.grant.propertyId, true);
        const grant = await transaction.get(`ownerContractUploads/${uploadId}`);
        if (grant.status === 'completed') return ownerLifecycleView(grant.propertyId, property);
        currentRevision(property, grant.revision);
        requireValue(grant.payload === context.grant.payload && grant.expiresAtMs > now() && grant.offerVersion === property.feeOffer.version,
          'The contract terms changed. Refresh before uploading.', 'aborted');
        requireValue(grant.kind === 'source' ? property.status === 'fee_offered' : property.status === 'contract_accepted',
          'The contract stage changed. Refresh.', 'aborted');
        requireValue(grant.kind !== 'signed' || file.sha256 !== property.contract.sourceFile.sha256,
          'An actual signed original is required.', 'invalid-argument');
        const contract = grant.kind === 'source' ? { status: 'ready', sourceFile: file, offerVersion: grant.offerVersion,
          publishedAtMs: now(), publishedByUid: auth.uid, reference: grant.reference } :
          { ...property.contract, status: 'signed', signedFile: file, signedAtMs: now(), signedReference: grant.reference,
            signaturesCheckedByUid: auth.uid };
        transaction.update(`ownerContractUploads/${uploadId}`, { status: 'completed' });
        return write(transaction, grant.propertyId, property, { ...property, contract,
          status: grant.kind === 'source' ? 'fee_offered' : 'plan_active',
          feeOffer: { ...property.feeOffer, status: grant.kind === 'source' ? 'offered' : 'accepted' } },
        grant.kind === 'source' ? 'owner_contract_terms_published' : 'owner_signed_contract_received',
        { sha256: file.sha256, reference: grant.reference, originalChecked: true, signaturesChecked: grant.signaturesChecked });
      });
      await files.cleanup(context.grant, uploadId).catch(() => {});
      return result;
    },
    async readContract({ id, signed = false, admin = false }) {
      const property = await store.transaction(transaction => home(transaction, id, admin));
      const file = signed ? property.contract?.signedFile : property.contract?.sourceFile;
      requireValue(file, 'Your contract copy is not ready yet.', 'not-found');
      return { id, signed, size: file.size, sha256: file.sha256, pageCount: file.pageCount, base64: await files.read(file) };
    },
    async change({ id, revision, action, ...input }) {
      const adminActions = ['check_tenant', 'link_agreement'];
      requireValue(['begin_consent', 'confirm_consent', 'publish_listing', 'pause_listing', 'check_tenant',
        'visit', 'decline_tenant', 'choose_tenant', 'link_agreement'].includes(action), 'Choose a supported property action.', 'invalid-argument');
      return store.transaction(async transaction => {
        const property = await home(transaction, id, adminActions.includes(action));
        const tenancyProperty = await transaction.get(`properties/${id}`);
        const challenge = action === 'confirm_consent' && safe(input.challengeId) ?
          await transaction.get(`ownerContractChallenges/${input.challengeId}`) : null;
        const agreement = action === 'link_agreement' && text(input.agreementId, 1, 150) && !input.agreementId.includes('/') ?
          await transaction.get(`agreements/${input.agreementId}`) : null;
        if (action === 'confirm_consent' && property.contract?.consent?.challengeId === input.challengeId) {
          requireValue(challenge?.uid === auth.uid && input.readTerms === true && input.acceptTerms === true, 'Confirm the terms.', 'permission-denied');
          return ownerLifecycleView(id, property);
        }
        currentRevision(property, revision);
        if (action === 'begin_consent') {
          requireValue(property.status === 'fee_offered' && property.contract?.status === 'ready' &&
            property.contract.offerVersion === property.feeOffer.version, 'Read the current full contract before agreeing.');
          requireValue(typeof input.operationId === 'string' && /^[a-f0-9]{32}$/.test(input.operationId), 'Start a new verification.', 'invalid-argument');
          const challengeId = digest([auth.uid, id, input.operationId]);
          const existing = await transaction.get(`ownerContractChallenges/${challengeId}`);
          requireValue(!existing || existing.expiresAtMs > now() && existing.sha256 === property.contract.sourceFile.sha256,
            'This verification expired. Request a new code.');
          if (!existing) transaction.set(`ownerContractChallenges/${challengeId}`, { uid: auth.uid, propertyId: id,
            issuedAtMs: now(), expiresAtMs: now() + 300000, sha256: property.contract.sourceFile.sha256, offerVersion: property.feeOffer.version });
          return { challengeId, expiresAtMs: existing?.expiresAtMs ?? now() + 300000 };
        }
        if (action === 'confirm_consent') {
          requireValue(challenge?.uid === auth.uid && challenge.propertyId === id && challenge.expiresAtMs > now() &&
            challenge.sha256 === property.contract?.sourceFile?.sha256 && challenge.offerVersion === property.feeOffer.version &&
            property.contract?.status === 'ready', 'The terms changed or verification expired. Read the contract and request a new code.');
          requireValue(input.readTerms === true && input.acceptTerms === true && auth.token?.firebase?.sign_in_provider === 'phone' &&
            Number.isSafeInteger(auth.token.auth_time) && auth.token.auth_time >= Math.ceil(challenge.issuedAtMs / 1000) &&
            auth.token.auth_time * 1000 <= now() + 5000, 'Verify the new phone OTP for these contract terms.', 'unauthenticated');
          return write(transaction, id, property, { ...property, status: 'contract_accepted',
            contract: { ...property.contract, status: 'accepted', consent: { challengeId: input.challengeId, uid: auth.uid,
              phone: verifiedPhone(auth), sha256: challenge.sha256, offerVersion: challenge.offerVersion, acceptedAtMs: now(),
              authTime: auth.token.auth_time, readTerms: true, acceptTerms: true } } }, 'owner_contract_consent_recorded');
        }
        if (action === 'publish_listing') {
          requireValue(['plan_active', 'listing_paused'].includes(property.status) && property.contract?.status === 'signed' && !tenancyProperty?.activeAgreementId,
            'Complete your owner contract before listing an unoccupied property.');
          requireValue(text(input.title, 3, 100) && text(input.locality, 3, 150) && input.publicDetailsApproved === true &&
            property.photos?.length > 0 && input.publicPhotosApproved === true, 'Review the public title, locality and actual property photos.', 'invalid-argument');
          requireValue(!property.chosenTenantId, 'Finish or cancel the selected tenant’s agreement before relisting.');
          return write(transaction, id, property, { ...property, status: 'listing_live', listing: { ...property.listing,
            title: input.title.trim(), locality: input.locality.trim(), status: 'live', publishedAtMs: now(),
            publicDetailsApproved: true, publicPhotosApproved: true, views: property.listing?.views ?? 0 },
            candidates: property.candidates ?? {} }, 'owner_listing_published');
        }
        if (action === 'pause_listing') {
          requireValue(property.listing?.status === 'live', 'This listing is already paused.');
          return write(transaction, id, property, { ...property, status: 'listing_paused', listing: { ...property.listing, status: 'paused' } }, 'owner_listing_paused');
        }
        const candidate = property.candidates?.[input.candidateId];
        requireValue(safe(input.candidateId) && candidate, 'Open a tenant who actually enquired about this home.', 'not-found');
        const candidates = { ...property.candidates };
        if (action === 'check_tenant') {
          requireValue(property.listing?.status === 'live' && ['interested', 'visit_confirmed'].includes(candidate.status) &&
            input.identityChecked === true && text(input.reference, 3, 200), 'Review the tenant’s actual identity evidence and record its reference.', 'invalid-argument');
          candidates[input.candidateId] = { ...candidate, identityCheck: { checked: true, reference: input.reference.trim(), checkedByUid: auth.uid, checkedAtMs: now() } };
        }
        if (action === 'visit') {
          requireValue(property.listing?.status === 'live' && ['interested', 'visit_confirmed'].includes(candidate.status) &&
            validDate(input.day) && ['10:00–12:00', '12:00–14:00', '16:00–18:00'].includes(input.slot) &&
            Date.parse(`${input.day}T${input.slot.slice(0, 5)}:00+05:30`) > now() && Date.parse(`${input.day}T00:00:00+05:30`) < now() + 60 * 86400000,
          'Confirm a future visit time for an interested tenant.', 'invalid-argument');
          candidates[input.candidateId] = { ...candidate, status: 'visit_confirmed', visit: { day: input.day, slot: input.slot, confirmedAtMs: now() } };
        }
        if (['decline_tenant', 'choose_tenant'].includes(action)) {
          requireValue(property.listing?.status === 'live' && ['interested', 'visit_confirmed'].includes(candidate.status) && !property.chosenTenantId,
            'This tenant or listing changed. Refresh before deciding.', 'aborted');
          requireValue(action !== 'choose_tenant' || candidate.identityCheck?.checked === true && !tenancyProperty?.activeAgreementId,
            'TrustKeyper must check the tenant’s identity before selection.');
          candidates[input.candidateId] = { ...candidate, status: action === 'choose_tenant' ? 'chosen' : 'declined', decidedAtMs: now() };
        }
        if (action === 'link_agreement') {
          requireValue(property.chosenTenantId === input.candidateId && candidate.status === 'chosen' &&
            agreement?.propertyId === id && agreement.owners?.some(person => person.phone === property.contract.consent.phone) &&
            agreement.tenants?.some(person => person.phone === candidate.phone), 'Link the actual agreement for this property, owner and chosen tenant.', 'invalid-argument');
          requireValue(Array.isArray(agreement.participantUids) && agreement.participantUids.includes(property.ownerUid) &&
            agreement.participantUids.includes(candidate.uid) && agreement.status !== 'cancelled',
          'Finish the verified participant account linkage before publishing this agreement entry. Keep using the private review links until then.');
          requireValue(!property.agreementId || property.agreementId === input.agreementId, 'Another agreement is already linked.', 'already-exists');
        }
        return write(transaction, id, property, { ...property, candidates,
          ...(action === 'choose_tenant' ? { chosenTenantId: input.candidateId, status: 'tenant_chosen', listing: { ...property.listing, status: 'paused' } } : {}),
          ...(action === 'link_agreement' ? { agreementId: input.agreementId } : {}) }, `owner_${action}`, { candidateId: input.candidateId });
      });
    },
    async readPublic({ id, photoIndex }) {
      requireValue(safe(id), 'This listing is unavailable.', 'not-found');
      const property = await store.transaction(transaction => transaction.get(`ownerProperties/${id}`));
      const data = listing(property);
      if (photoIndex != null) {
        requireValue(integer(photoIndex, 0, data.photoCount - 1), 'This listing photo is unavailable.', 'not-found');
        const photo = property.photos[photoIndex];
        return { id, index: photoIndex, contentType: photo.contentType, size: photo.size, sha256: photo.sha256, base64: await photos.read(photo) };
      }
      return { id, ...data };
    },
    async enquire({ id, action, name, household, work, moveIn, visitDay, visitSlot }) {
      requireValue(safe(id) && ['view', 'interest', 'status'].includes(action), 'Open an available listing.', 'invalid-argument');
      if (action === 'interest') requireValue(text(name, 2, 100) && integer(household, 1, 20) && text(work, 2, 200) && validDate(moveIn) &&
        moveIn >= new Date(now() + 19800000).toISOString().slice(0, 10) &&
        (visitDay == null || validDate(visitDay) && ['10:00–12:00', '12:00–14:00', '16:00–18:00'].includes(visitSlot) &&
          Date.parse(`${visitDay}T${visitSlot.slice(0, 5)}:00+05:30`) > now() && Date.parse(`${visitDay}T00:00:00+05:30`) < now() + 60 * 86400000),
      'Enter your household, work, move-in date and an optional future visit.', 'invalid-argument');
      return store.transaction(async transaction => {
        const phone = await prospect(transaction);
        const property = await transaction.get(`ownerProperties/${id}`);
        if (action === 'status') {
          const candidate = property?.candidates?.[digest([id, phone])];
          if (!candidate) return { received: false };
          return { received: true, status: candidate.status, name: candidate.name, moveIn: candidate.moveIn,
            identityChecked: candidate.identityCheck?.checked === true, visit: candidate.visit ?? null,
            managerName: property.check?.managerName ?? null, managerPhone: property.check?.managerPhone ?? null,
            agreementReady: property.chosenTenantId === digest([id, phone]) && !!property.agreementId };
        }
        listing(property);
        requireValue(property.ownerUid !== auth.uid, 'Owner activity is not counted as tenant interest.', 'permission-denied');
        const candidateId = digest([id, phone]);
        const seen = await transaction.get(`ownerListingViews/${candidateId}`);
        const existing = property.candidates?.[candidateId];
        requireValue(action !== 'interest' || !existing || ['interested', 'visit_confirmed'].includes(existing.status),
          'Your enquiry is already being handled. Contact the manager.');
        requireValue(action !== 'interest' || existing || Object.keys(property.candidates ?? {}).length < 100,
          'Contact TrustKeyper directly about this listing.', 'resource-exhausted');
        if (!seen) transaction.set(`ownerListingViews/${candidateId}`, { propertyId: id, createdAtMs: now() });
        const candidates = { ...property.candidates };
        const changedIdentity = action === 'interest' && existing && (existing.name !== name.trim() || existing.household !== household || existing.work !== work.trim());
        if (action === 'interest') candidates[candidateId] = { ...existing, ...(changedIdentity ? { identityCheck: null } : {}), name: name.trim(), phone, uid: auth.uid, household,
          work: work.trim(), moveIn, status: existing?.status ?? 'interested', createdAtMs: existing?.createdAtMs ?? now(), updatedAtMs: now(),
          ...(visitDay ? { requestedVisit: { day: visitDay, slot: visitSlot } } : {}) };
        if (!seen || action === 'interest') transaction.set(`ownerProperties/${id}`, { ...property, candidates,
          revision: property.revision + 1, updatedAtMs: now(), listing: { ...property.listing, views: (property.listing.views ?? 0) + (seen ? 0 : 1) } });
        return { received: true, ...(action === 'interest' ? { candidateId, status: candidates[candidateId].status } : {}) };
      });
    },
  };
}
