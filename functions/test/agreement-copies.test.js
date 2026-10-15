import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAgreementCopyService } from '../agreement-copies.js';
import { approvalDigest, approvalRoundId } from '../agreement-approvals.js';
import { reviewSnapshot } from '../agreement-review.js';

function fixture() {
  let sequence = 0;
  let time = 10000;
  let data = new Map([
    ['users/admin', { roles: ['admin'] }],
    ['users/broker', { roles: ['broker'], approvalStatus: 'approved' }],
    ['users/owner', { roles: ['owner'], phone: '+911111111111' }],
    ['users/tenant', { roles: ['tenant'], phone: '+912222222222' }],
  ]);
  const agreement = { schemaVersion: 2, propertyAddress: 'TEST Flat 402', owners: [{ id: 'owner-1', name: 'Test Owner', phone: '+911111111111', email: '', rentSharePaise: 0, depositSharePaise: 0 }],
    tenants: [{ id: 'tenant-1', name: 'Test Tenant', phone: '+912222222222', email: '', rentSharePaise: 2200000, depositSharePaise: 4400000 }],
    monthlyRentPaise: 2200000, monthlyMaintenancePaise: 0, securityDepositPaise: 4400000,
    ownerBrokeragePaise: 0, tenantBrokeragePaise: 0, startDateISO: '2026-10-01T00:00:00.000', endDateISO: '2027-08-31T00:00:00.000',
    rentDueDay: 5, lockInMonths: 6, noticeMonths: 1, status: 'reviewed', revision: 1, brokerUid: 'broker', participantUids: ['broker'],
    lastReviewRevision: 1, reviewTemplateVersion: 'demo-v1', reviewSignable: false };
  agreement.reviewDigest = approvalDigest(reviewSnapshot(agreement));
  data.set('agreements/test', agreement);
  const roundId = approvalRoundId('test', 1);
  data.set(`agreementApprovalRounds/${roundId}`, { digest: agreement.reviewDigest, replies: {
    'owner-1': { status: 'agreed', revision: 1, digest: agreement.reviewDigest, actorUid: 'owner' },
    'tenant-1': { status: 'agreed', revision: 1, digest: agreement.reviewDigest, actorUid: 'tenant' },
  } });
  const store = { transaction: async handler => {
    const next = structuredClone(data);
    let written = false;
    const result = await handler({
      get: async path => { assert.equal(written, false); return next.get(path); },
      set: (path, value) => { written = true; next.set(path, structuredClone(value)); },
      update: (path, value) => { written = true; next.set(path, { ...next.get(path), ...structuredClone(value) }); },
    });
    data = next;
    return result;
  } };
  const files = { snapshots: 0, cleaned: 0,
    snapshot: async (upload, id) => {
      files.snapshots++;
      return { path: `agreementCopies/test/1/${id}.pdf`, generation: '1', size: upload.size, sha256: upload.sha256 };
    },
    read: async () => 'private-pdf-base64', cleanup: async () => { files.cleaned++; },
  };
  const identity = (uid, phone, provider = 'phone') => ({ uid, token: { phone_number: phone, firebase: { sign_in_provider: provider } } });
  const service = auth => createAgreementCopyService({ store, files, auth, now: () => time, eventId: () => `event-${++sequence}` });
  const input = { agreementId: 'test', revision: 1, operationId: 'copy-one', mode: 'demo', sha256: 'a'.repeat(64), size: 50 };
  const external = { ...input, mode: 'externally_signed', templateName: 'Approved external original v1',
    approvedOriginal: true, allPartiesSigned: true, matchesReviewedTerms: true };
  return { files, input, external, service, identity, admin: service(identity('admin')), roundId,
    get: path => data.get(path), set: (path, value) => data.set(path, value), clock: value => { time = value; } };
}

test('only enabled admins can begin; exact reviewed approvals and legal attestations are required', async () => {
  const flow = fixture();
  for (const auth of [undefined, flow.identity('broker'), flow.identity('owner')]) {
    await assert.rejects(flow.service(auth).begin(flow.input));
  }
  for (const invalid of [{ size: 0 }, { size: 21 * 1024 * 1024 }, { sha256: 'wrong' }, { revision: 2 }]) {
    await assert.rejects(flow.admin.begin({ ...flow.input, ...invalid }));
  }
  for (const invalid of [{ approvedOriginal: false }, { allPartiesSigned: false }, { matchesReviewedTerms: false }, { templateName: 'demo-v1' }]) {
    await assert.rejects(flow.admin.begin({ ...flow.external, ...invalid }), { code: 'invalid-argument' });
  }
  const round = flow.get(`agreementApprovalRounds/${flow.roundId}`);
  round.replies['tenant-1'].status = 'change_requested';
  flow.set(`agreementApprovalRounds/${flow.roundId}`, round);
  await assert.rejects(flow.admin.begin(flow.input));
});

test('demo copy remains non-signable; retry publishes one immutable copy and audit', async () => {
  const flow = fixture();
  const first = await flow.admin.begin(flow.input);
  assert.deepEqual(await flow.admin.begin(flow.input), first);
  await assert.rejects(flow.admin.begin({ ...flow.input, size: 100 }), { code: 'aborted' });
  const result = await flow.admin.complete({ uploadId: first.uploadId });
  assert.equal(result.mode, 'demo');
  assert.equal(result.receivedBy, undefined);
  assert.equal(flow.get('agreements/test').status, 'reviewed');
  assert.equal(flow.get('agreements/test').reviewSignable, false);
  assert.deepEqual(flow.get('agreements/test').participantUids, ['broker']);
  assert.deepEqual(await flow.admin.complete({ uploadId: first.uploadId }), result);
  assert.equal(flow.files.snapshots, 1);
  assert.equal(flow.files.cleaned, 1);
  await assert.rejects(flow.admin.begin({ ...flow.input, operationId: 'different' }));
});

test('external completed original is distinct from demo; verified recipients are linked without payment or legal-template mutation', async () => {
  const flow = fixture();
  flow.set('users/owner', { roles: ['broker'], approvalStatus: 'pending', phone: '+911111111111' });
  const grant = await flow.admin.begin(flow.external);
  await flow.admin.complete({ uploadId: grant.uploadId });
  const agreement = flow.get('agreements/test');
  assert.equal(agreement.status, 'signed_copy_received');
  assert.equal(agreement.reviewSignable, false);
  assert.equal(agreement.agreementCopy.source, 'manual_external_portal');
  assert.deepEqual(agreement.participantUids, ['broker', 'owner', 'tenant']);
  assert.deepEqual(flow.get('users/owner').roles, ['broker', 'owner']);
  assert.equal(flow.get('users/owner').approvalStatus, 'pending');
  assert.equal(agreement.paid, undefined);
  assert.equal(agreement.active, undefined);
  await assert.rejects(flow.admin.begin({ ...flow.external, operationId: 'replacement' }));
});

test('matching verified recipient can read; wrong identity/phone/provider, paused accounts and outsiders cannot', async () => {
  const flow = fixture();
  const grant = await flow.admin.begin(flow.external);
  await flow.admin.complete({ uploadId: grant.uploadId });
  const input = { agreementId: 'test', revision: 1 };
  assert.equal((await flow.service(flow.identity('owner', '+911111111111')).read(input)).base64, 'private-pdf-base64');
  for (const auth of [flow.identity('outsider', '+911111111111'), flow.identity('owner', '+912222222222'),
    flow.identity('owner', '+911111111111', 'password'), undefined]) {
    await assert.rejects(flow.service(auth).read(input));
  }
  flow.set('users/owner', { roles: ['owner'], paused: true });
  await assert.rejects(flow.service(flow.identity('owner', '+911111111111')).read(input));
  await assert.rejects(flow.admin.read({ ...input, revision: 2 }));
});

test('expiry, failed checksum and a changed approval during upload cannot publish', async () => {
  for (const scenario of ['expiry', 'checksum', 'withdrawn']) {
    const flow = fixture();
    const grant = await flow.admin.begin(flow.input);
    if (scenario === 'expiry') flow.clock(10000 + 16 * 60000);
    if (scenario === 'checksum') flow.files.snapshot = async upload => ({ size: upload.size, sha256: 'b'.repeat(64) });
    if (scenario === 'withdrawn') {
      const snapshot = flow.files.snapshot;
      flow.files.snapshot = async (...args) => {
        const result = await snapshot(...args);
        const round = flow.get(`agreementApprovalRounds/${flow.roundId}`);
        round.replies['owner-1'].status = 'change_requested';
        flow.set(`agreementApprovalRounds/${flow.roundId}`, round);
        return result;
      };
    }
    await assert.rejects(flow.admin.complete({ uploadId: grant.uploadId }));
    assert.equal(flow.get('agreements/test').agreementCopy, undefined);
    assert.equal(flow.get(`agreementCopyUploads/${grant.uploadId}`).status, 'uploading');
  }
});

test('completed external copy may supersede a demo but never another external original', async () => {
  const flow = fixture();
  const first = await flow.admin.begin(flow.input);
  await flow.admin.complete({ uploadId: first.uploadId });
  const final = await flow.admin.begin({ ...flow.external, operationId: 'external-final' });
  await flow.admin.complete({ uploadId: final.uploadId });
  assert.equal(flow.get('agreements/test').agreementCopy.mode, 'externally_signed');
  await assert.rejects(flow.admin.complete({ uploadId: first.uploadId }));
});

test('account access and exact copy are rechecked after downloading private bytes', async () => {
  const flow = fixture();
  const grant = await flow.admin.begin(flow.external);
  await flow.admin.complete({ uploadId: grant.uploadId });
  flow.files.read = async () => {
    flow.set('users/owner', { roles: ['owner'], paused: true });
    return 'must-not-deliver';
  };
  await assert.rejects(flow.service(flow.identity('owner', '+911111111111')).read({ agreementId: 'test', revision: 1 }), { code: 'permission-denied' });
});
