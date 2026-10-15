import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createOwnerLifecycleService } from '../owner-lifecycle.js';

const id = 'a'.repeat(64);
const contractSpec = { size: 120, sha256: 'b'.repeat(64), contentType: 'application/pdf' };
function fixture() {
  const clock = { value: Date.parse('2026-10-11T06:00:00.250Z') };
  let records = new Map([['users/owner', { phone: '+911111111111', roles: ['owner'] }],
    ['users/other', { phone: '+912222222222', roles: ['owner'] }], ['users/admin', { roles: ['admin'] }],
    [`ownerProperties/${id}`, { ownerUid: 'owner', revision: 8, nextStep: 4, status: 'fee_offered', plan: 'full_service',
      details: { name: 'PRIVATE nickname', address: 'PRIVATE door number', rentPaise: 2000000, depositPaise: 4000000,
        maintenancePaise: 100000, availableFrom: '2026-11-01', rooms: '2 BHK', furnishing: 'Semi', features: ['Lift'], whoCanStay: 'Family', pets: 'Ask me' },
      photos: [{ path: 'PRIVATE photo', generation: '1', size: 20, contentType: 'image/png', sha256: 'e'.repeat(64) }],
      feeOffer: { version: 8, feeBps: 800, effectiveFrom: '2026-11-01', status: 'offered' } }],
    [`properties/${id}`, { ownerUid: 'owner' }]]);
  const store = { transaction: async handler => {
    const next = structuredClone(records); let wrote = false;
    const result = await handler({ get: async path => { assert.equal(wrote, false, 'Firestore reads precede writes'); return next.get(path); },
      set: (path, data) => { wrote = true; next.set(path, structuredClone(data)); },
      update: (path, data) => { wrote = true; next.set(path, { ...next.get(path), ...structuredClone(data) }); } });
    records = next; return result;
  } };
  const files = { count: 0, read: async () => 'TEST_PDF', cleanup: async () => {}, snapshot: async grant => {
    files.count++; return { ...grant.spec, pageCount: 2, path: 'PRIVATE contract object', generation: '1' };
  } };
  const service = (uid, token) => createOwnerLifecycleService({ store, files, photos: { read: async () => 'TEST_PHOTO' }, now: () => clock.value,
    auth: uid ? { uid, token: token ?? { phone_number: records.get(`users/${uid}`)?.phone, firebase: { sign_in_provider: 'phone' }, auth_time: Math.floor(clock.value / 1000) } } : null });
  const property = () => records.get(`ownerProperties/${id}`);
  async function upload(kind = 'source') {
    const grant = await service('admin').beginContract({ id, revision: property().revision, operationId: (kind === 'source' ? '1' : '2').repeat(32), kind,
      spec: kind === 'source' ? contractSpec : { ...contractSpec, sha256: 'c'.repeat(64) }, reference: 'TEST ONLY externally checked PDF', originalChecked: true, signaturesChecked: true });
    return service('admin').completeContract({ uploadId: grant.uploadId });
  }
  async function consent() {
    const challenge = await service('owner').change({ id, revision: property().revision, action: 'begin_consent', operationId: '3'.repeat(32) });
    clock.value += 2000;
    const input = { id, revision: property().revision, action: 'confirm_consent', challengeId: challenge.challengeId, readTerms: true, acceptTerms: true };
    const result = await service('owner').change(input); return { input, result };
  }
  async function publish() {
    await upload(); await consent(); await upload('signed');
    return service('owner').change({ id, revision: property().revision, action: 'publish_listing', title: 'TEST Example apartments', locality: 'TEST Hyderabad',
      publicDetailsApproved: true, publicPhotosApproved: true });
  }
  const interest = (uid = 'other') => service(uid).enquire({ id, action: 'interest', name: 'TEST consenting tenant', household: 3, work: 'TEST workplace', moveIn: '2026-11-01' });
  return { clock, property, service, upload, consent, publish, interest, files, get: path => records.get(path), set: (path, value) => records.set(path, value) };
}

test('actual owner contract has private immutable terms, fresh OTP consent, signed original and no automatic money or tenancy', async () => {
  const flow = fixture(); const terms = await flow.upload();
  assert.equal(terms.contract.status, 'ready'); assert.equal(terms.contract.sourceFile.path, undefined);
  const { input } = await flow.consent();
  assert.equal(flow.property().status, 'contract_accepted');
  assert.deepEqual(await flow.service('owner').change(input), await flow.service('owner').change(input));
  const signed = await flow.upload('signed');
  assert.equal(signed.contract.status, 'signed'); assert.equal(signed.status, 'plan_active');
  assert.equal(signed.feeOffer.status, 'accepted'); assert.equal(flow.get(`properties/${id}`).activeAgreementId, undefined);
  assert.equal((await flow.service('owner').readContract({ id, signed: true })).base64, 'TEST_PDF');
});

test('contract processing rejects impersonation, stale revision, same unsigned file, missing evidence and forged consent', async () => {
  const flow = fixture();
  const request = { id, revision: 8, operationId: '1'.repeat(32), kind: 'source', spec: contractSpec, reference: 'TEST reference', originalChecked: true };
  await assert.rejects(flow.service('owner').beginContract(request), { code: 'permission-denied' });
  await assert.rejects(flow.service(null).completeContract({ uploadId: 'd'.repeat(64) }), { code: 'unauthenticated' });
  await assert.rejects(flow.service('admin').beginContract({ ...request, originalChecked: false }), { code: 'invalid-argument' });
  await flow.upload();
  await assert.rejects(flow.service('other').readContract({ id }), { code: 'permission-denied' });
  await assert.rejects(flow.service('owner').readContract({ id, admin: true }), { code: 'permission-denied' });
  const { input } = await flow.consent();
  await assert.rejects(flow.service('other').change(input), { code: 'permission-denied' });
  await assert.rejects(flow.service('admin').beginContract({ ...request, revision: flow.property().revision, kind: 'signed', signaturesChecked: true }), { code: 'invalid-argument' });
  assert.equal(flow.files.count, 1);
});

test('contract OTP binds to the current terms and only an authentication after the challenge counts', async () => {
  const flow = fixture(); await flow.upload();
  const challenge = await flow.service('owner').change({ id, revision: flow.property().revision, action: 'begin_consent', operationId: '3'.repeat(32) });
  const input = { id, revision: flow.property().revision, action: 'confirm_consent', challengeId: challenge.challengeId, readTerms: true, acceptTerms: true };
  await assert.rejects(flow.service('owner').change(input), { code: 'unauthenticated' });
  flow.clock.value += 2000;
  await assert.rejects(flow.service('owner', { phone_number: '+911111111111', trustkeyper_email_otp: true, email_verified: true,
    email: 'test@example.invalid', trustkeyper_verified_phone: '+911111111111', firebase: { sign_in_provider: 'custom' }, auth_time: Math.floor(flow.clock.value / 1000) }).change(input), { code: 'unauthenticated' });
  const changed = flow.property(); flow.set(`ownerProperties/${id}`, { ...changed, contract: { ...changed.contract, sourceFile: { ...changed.contract.sourceFile, sha256: 'f'.repeat(64) } } });
  await assert.rejects(flow.service('owner').change(input), { code: 'failed-precondition' });
});

test('expired OTP and unchecked agreement cannot consent or publish', async () => {
  const flow = fixture(); await flow.upload();
  const challenge = await flow.service('owner').change({ id, revision: flow.property().revision, action: 'begin_consent', operationId: '3'.repeat(32) });
  const input = { id, revision: flow.property().revision, action: 'confirm_consent', challengeId: challenge.challengeId, readTerms: false, acceptTerms: true };
  flow.clock.value += 2000;
  await assert.rejects(flow.service('owner').change(input), { code: 'unauthenticated' });
  flow.clock.value += 300000;
  await assert.rejects(flow.service('owner').change({ ...input, readTerms: true }), { code: 'failed-precondition' });
  await assert.rejects(flow.service('owner').change({ id, revision: flow.property().revision, action: 'publish_listing' }), { code: 'failed-precondition' });
});

test('live Firebase listing publishes approved fields and photos only; pause revokes public access', async () => {
  const flow = fixture(); await assert.rejects(flow.service(null).readPublic({ id }), { code: 'not-found' });
  await flow.publish();
  const publicData = await flow.service(null).readPublic({ id });
  assert.equal(publicData.title, 'TEST Example apartments'); assert.equal(publicData.photoCount, 1);
  for (const value of ['PRIVATE', 'ownerUid', 'phone', 'contract', 'candidate', 'generation']) assert.equal(JSON.stringify(publicData).includes(value), false);
  assert.equal((await flow.service(null).readPublic({ id, photoIndex: 0 })).base64, 'TEST_PHOTO');
  await assert.rejects(flow.service(null).readPublic({ id, photoIndex: 10 }), { code: 'not-found' });
  await flow.service('owner').change({ id, revision: flow.property().revision, action: 'pause_listing' });
  await assert.rejects(flow.service(null).readPublic({ id }), { code: 'not-found' });
  await assert.rejects(flow.service(null).readPublic({ id, photoIndex: 0 }), { code: 'not-found' });
});

test('tenant interest and views are real verified-phone events, deduplicated, private and bounded', async () => {
  const flow = fixture(); await flow.publish();
  await assert.rejects(flow.service(null).enquire({ id, action: 'view' }), { code: 'unauthenticated' });
  await assert.rejects(flow.service('owner').enquire({ id, action: 'view' }), { code: 'permission-denied' });
  await flow.service('other').enquire({ id, action: 'view' }); await flow.service('other').enquire({ id, action: 'view' });
  const result = await flow.interest(); await flow.interest();
  assert.equal(flow.property().listing.views, 1); assert.equal(Object.keys(flow.property().candidates).length, 1);
  assert.equal(flow.property().candidates[result.candidateId].identityCheck, undefined);
  assert.equal(JSON.stringify(await flow.service(null).readPublic({ id })).includes('+912222222222'), false);
  await assert.rejects(flow.service('other').enquire({ id, action: 'interest', name: 'TEST', household: 0, work: 'TEST', moveIn: '2026-02-30' }), { code: 'invalid-argument' });
});

test('actual identity check, visit, tenant choice and agreement link have revision guards and never fake activation', async () => {
  const flow = fixture(); await flow.publish(); const { candidateId } = await flow.interest();
  const change = (uid, action, extra = {}) => flow.service(uid).change({ id, revision: flow.property().revision, candidateId, action, ...extra });
  await assert.rejects(change('owner', 'choose_tenant'), { code: 'failed-precondition' });
  await assert.rejects(change('owner', 'check_tenant', { identityChecked: true, reference: 'TEST proof' }), { code: 'permission-denied' });
  await change('admin', 'check_tenant', { identityChecked: true, reference: 'TEST identity reviewed with consent' });
  await assert.rejects(change('owner', 'visit', { day: '2026-10-10', slot: '10:00–12:00' }), { code: 'invalid-argument' });
  await change('owner', 'visit', { day: '2026-10-12', slot: '10:00–12:00' });
  const revision = flow.property().revision;
  await change('owner', 'choose_tenant');
  await assert.rejects(flow.service('owner').change({ id, revision, action: 'choose_tenant', candidateId }), { code: 'aborted' });
  assert.equal(flow.property().status, 'tenant_chosen'); assert.equal(flow.property().listing.status, 'paused');
  assert.equal(flow.get(`properties/${id}`).activeAgreementId, undefined);
  await assert.rejects(change('admin', 'link_agreement', { agreementId: 'fake' }), { code: 'invalid-argument' });
  flow.set('agreements/real-test', { propertyId: id, owners: [{ phone: '+911111111111' }], tenants: [{ phone: '+912222222222' }] });
  await assert.rejects(change('admin', 'link_agreement', { agreementId: 'real-test' }), { code: 'failed-precondition' });
  flow.set('agreements/real-test', { ...flow.get('agreements/real-test'), participantUids: ['owner', 'other'], status: 'cancelled' });
  await assert.rejects(change('admin', 'link_agreement', { agreementId: 'real-test' }), { code: 'failed-precondition' });
  flow.set('agreements/real-test', { ...flow.get('agreements/real-test'), status: 'signed' });
  await change('admin', 'link_agreement', { agreementId: 'real-test' });
  assert.equal(flow.property().agreementId, 'real-test');
});

test('paused owners and changed contract upload terms are rejected before processing files', async () => {
  const flow = fixture();
  const input = { id, revision: 8, operationId: '4'.repeat(32), kind: 'source', spec: contractSpec, reference: 'TEST source', originalChecked: true };
  const grant = await flow.service('admin').beginContract(input);
  assert.deepEqual(await flow.service('admin').beginContract(input), grant);
  await assert.rejects(flow.service('admin').beginContract({ ...input, reference: 'TEST different source' }), { code: 'already-exists' });
  flow.set(`ownerProperties/${id}`, { ...flow.property(), revision: 9 });
  await assert.rejects(flow.service('admin').completeContract({ uploadId: grant.uploadId }), { code: 'aborted' });
  assert.equal(flow.files.count, 0);
  flow.set('users/owner', { phone: '+911111111111', roles: ['owner'], paused: true });
  await assert.rejects(flow.service('owner').change({ id, revision: 9, action: 'begin_consent', operationId: '5'.repeat(32) }), { code: 'permission-denied' });
});

test('changing applicant identity details clears the old check and private receipts never expose another applicant', async () => {
  const flow = fixture(); await flow.publish(); const { candidateId } = await flow.interest();
  await flow.service('admin').change({ id, revision: flow.property().revision, candidateId, action: 'check_tenant', identityChecked: true, reference: 'TEST actual check' });
  assert.equal((await flow.service('other').enquire({ id, action: 'status' })).identityChecked, true);
  await flow.service('other').enquire({ id, action: 'view' });
  await flow.service('other').enquire({ id, action: 'interest', name: 'TEST new identity name', household: 3, work: 'TEST workplace', moveIn: '2026-11-01' });
  assert.equal(flow.property().candidates[candidateId].identityCheck, null);
  await assert.rejects(flow.service('owner').change({ id, revision: flow.property().revision, candidateId, action: 'choose_tenant' }), { code: 'failed-precondition' });
  assert.deepEqual(await flow.service('owner').enquire({ id, action: 'status' }), { received: false });
  const receipt = await flow.service('other').enquire({ id, action: 'status' });
  assert.equal(receipt.name, 'TEST new identity name'); assert.equal(receipt.identityChecked, false);
  assert.equal(JSON.stringify(receipt).includes('PRIVATE'), false);
  await assert.rejects(flow.service(null).enquire({ id, action: 'status' }), { code: 'unauthenticated' });
});

test('selected tenant can retrieve the actual paused-listing receipt without reviving the public listing', async () => {
  const flow = fixture(); await flow.publish(); const { candidateId } = await flow.interest();
  await flow.service('admin').change({ id, revision: flow.property().revision, candidateId, action: 'check_tenant', identityChecked: true, reference: 'TEST actual check' });
  await flow.service('owner').change({ id, revision: flow.property().revision, candidateId, action: 'choose_tenant' });
  const receipt = await flow.service('other').enquire({ id, action: 'status' });
  assert.equal(receipt.status, 'chosen'); assert.equal(receipt.agreementReady, false);
  await assert.rejects(flow.service(null).readPublic({ id }), { code: 'not-found' });
});
