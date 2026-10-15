import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAgreementApprovalService, approvalRoundId } from '../agreement-approvals.js';
import { createAgreementReviewService } from '../agreement-review.js';

function fixture() {
  let clock = 100000;
  let sequence = 0;
  let data = new Map([
    ['users/broker', { roles: ['broker'], approvalStatus: 'approved', displayName: 'Test Broker' }],
    ['users/owner', { roles: ['owner'] }],
    ['agreements/test', { schemaVersion: 2, propertyAddress: 'TEST Flat 402, Test Towers',
      owners: [{ id: 'owner-1', name: 'Test Owner', phone: '+911111111111', email: '', rentSharePaise: 0, depositSharePaise: 0 }],
      tenants: [{ id: 'tenant-1', name: 'Test Tenant', phone: '+912222222222', email: '', rentSharePaise: 2200000, depositSharePaise: 4400000 }],
      monthlyRentPaise: 2200000, monthlyMaintenancePaise: 0, securityDepositPaise: 4400000,
      ownerBrokeragePaise: 1100000, tenantBrokeragePaise: 2200000,
      startDateISO: '2026-10-01T00:00:00.000', endDateISO: '2027-08-31T00:00:00.000',
      rentDueDay: 5, lockInMonths: 6, noticeMonths: 1, status: 'draft', revision: 1,
      brokerUid: 'broker', participantUids: ['broker'] }],
  ]);
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
  const identity = (uid, phone, provider = 'phone') => ({ uid, token: { phone_number: phone, firebase: { sign_in_provider: provider } } });
  const service = auth => createAgreementApprovalService({ store, auth, now: () => clock,
    nonce: () => `${++sequence}`.padStart(43, 'a'), eventId: () => `event-${++sequence}` });
  return { get: path => data.get(path), set: (path, value) => data.set(path, value),
    size: () => data.size, clock: value => { clock = value; }, service, identity,
    broker: () => service(identity('broker', '+919999999999')),
    owner: () => service(identity('owner', '+911111111111')),
    tenant: () => service(identity('tenant', '+912222222222')),
    prepare: (revision = 1, extra = {}) => service(identity('broker', '+919999999999')).prepare({
      agreementId: 'test', revision, operationId: `op-${revision}`, ...extra }),
    review: () => createAgreementReviewService({ store, uid: 'broker', now: () => clock, eventId: () => `review-${++sequence}` }),
  };
}
async function yes(flow, link, operationId = 'reply-1') {
  const service = link.role === 'owner' ? flow.owner() : flow.tenant();
  const read = await service.read({ token: link.token });
  return service.reply({ token: link.token, revision: read.revision, digest: read.digest,
    decision: 'agreed', readAll: true, agreeTerms: true, operationId });
}

test('published signed copy is readable from the verified link but cannot be withdrawn as a draft', async () => {
  const flow = fixture();
  const { links } = await flow.prepare();
  await yes(flow, links[0]); await yes(flow, links[1]);
  const agreement = flow.get('agreements/test');
  flow.set('agreements/test', { ...agreement, status: 'signed_copy_received', agreementCopy: { revision: 1, mode: 'externally_signed' } });
  const read = await flow.owner().read({ token: links[0].token });
  assert.equal(read.copyReady, true);
  assert.equal(read.copyMode, 'externally_signed');
  await assert.rejects(flow.owner().reply({ token: links[0].token, revision: 1, digest: read.digest,
    decision: 'change_requested', category: 'Dates', note: 'Change the date please.', operationId: 'withdraw-final' }));
  assert.equal(flow.get('agreements/test').status, 'signed_copy_received');
});

test('prepares private per-person seven-day links; retry preserves tokens and audit', async () => {
  const flow = fixture();
  const first = await flow.prepare();
  const size = flow.size();
  assert.deepEqual(await flow.prepare(), first);
  assert.equal(flow.size(), size);
  assert.equal(first.links.length, 2);
  assert.notEqual(first.links[0].token, first.links[1].token);
  assert.equal(first.links[0].expiresAtMs, 100000 + 7 * 86400000);
  assert.equal(first.signable, false);
  assert.equal(flow.get('agreements/test').status, 'draft');
});
test('unverified and wrong-phone reads reveal no property, snapshot, name or reply', async () => {
  const flow = fixture();
  const { links } = await flow.prepare();
  for (const service of [flow.service(null), flow.tenant(), flow.service(flow.identity('owner', '+911111111111', 'password'))]) {
    const read = await service.read({ token: links[0].token });
    assert.equal(read.verified, false);
    for (const key of ['snapshot', 'partyName', 'agreementId', 'reply', 'people', 'digest']) assert.equal(read[key], undefined);
  }
  assert.equal(flow.get(`agreementInvitations/${links[0].invitationId}`).status, 'not_opened');
  await assert.rejects(flow.tenant().reply({ token: links[0].token, decision: 'agreed', readAll: true, agreeTerms: true, operationId: 'wrong' }), { code: 'permission-denied' });
});
test('phone proof without profile opens the correct snapshot; seen is recorded only once', async () => {
  const flow = fixture();
  const { links } = await flow.prepare();
  const read = await flow.tenant().read({ token: links[1].token });
  const size = flow.size();
  assert.equal(read.verified, true);
  assert.equal(read.status, 'seen');
  assert.equal(read.snapshot.tenants[0].rentSharePaise, 2200000);
  assert.deepEqual(await flow.tenant().read({ token: links[1].token }), read);
  assert.equal(flow.size(), size);
  assert.equal(flow.get('users/tenant'), undefined);
});
test('two confirmations, exact version and digest are mandatory; invalid replies do not write', async () => {
  const flow = fixture();
  const { links } = await flow.prepare();
  const read = await flow.owner().read({ token: links[0].token });
  const input = { token: links[0].token, revision: read.revision, digest: read.digest, decision: 'agreed', readAll: true, agreeTerms: true, operationId: 'yes' };
  for (const change of [{ readAll: false }, { agreeTerms: false }, { readAll: 'true' }, { revision: 2 }, { digest: 'a'.repeat(64) }]) {
    await assert.rejects(flow.owner().reply({ ...input, ...change }));
    assert.equal(flow.get(`agreementInvitations/${links[0].invitationId}`).status, 'seen');
  }
});
test('same-version replies gate team review; retries are idempotent and demo cannot become signable', async () => {
  const flow = fixture();
  await assert.rejects(flow.review().submit({ agreementId: 'test', revision: 1 }));
  const { links } = await flow.prepare();
  await yes(flow, links[0]);
  await assert.rejects(flow.review().submit({ agreementId: 'test', revision: 1 }));
  const reply = await yes(flow, links[1]);
  const size = flow.size();
  assert.equal(reply.allAgreed, true);
  assert.deepEqual(await yes(flow, links[1]), reply);
  assert.equal(flow.size(), size);
  assert.equal(reply.signable, false);
  assert.equal(reply.reply.evidenceVersion, 'demo-reply-v1');
  assert.equal((await flow.review().submit({ agreementId: 'test', revision: 1 })).status, 'review_requested');
  assert.equal(flow.get('agreements/test').reviewSignable, false);
});
test('change request after yes removes all-yes gate, preserves old audit and requires revision', async () => {
  const flow = fixture();
  const { links } = await flow.prepare();
  const read = await yes(flow, links[0]);
  await yes(flow, links[1]);
  const request = { token: links[0].token, revision: 1, digest: read.digest, decision: 'change_requested',
    category: 'Rent or deposit', note: 'Please increase the deposit.', operationId: 'change-1' };
  for (const change of [{ note: 'x' }, { category: 'forged' }]) await assert.rejects(flow.owner().reply({ ...request, ...change }));
  const reply = await flow.owner().reply(request);
  assert.equal(reply.allAgreed, false);
  assert.equal(reply.reply.note, request.note);
  assert.deepEqual(await flow.owner().reply(request), reply);
  await assert.rejects(flow.owner().reply({ ...request, note: 'Another note with same ID' }), { code: 'aborted' });
  await assert.rejects(yes(flow, links[0], 'again'));
  await assert.rejects(flow.review().submit({ agreementId: 'test', revision: 1 }));
});
test('changed terms revoke every old link and reset every reply; changed fields are server derived', async () => {
  const flow = fixture();
  const old = await flow.prepare();
  await yes(flow, old.links[0]);
  await yes(flow, old.links[1]);
  const agreement = flow.get('agreements/test');
  agreement.revision = 2; agreement.rentDueDay = 10;
  for (const link of old.links) await assert.rejects(flow.owner().read({ token: link.token }));
  const next = await flow.prepare(2);
  const read = await flow.owner().read({ token: next.links[0].token });
  assert.deepEqual(read.changedFields, ['rentDueDay']);
  assert.equal(read.status, 'seen');
  assert.equal(read.allAgreed, false);
  assert.equal(flow.get(`agreementApprovalRounds/${approvalRoundId('test', 1)}`).replies['owner-1'].status, 'agreed');
});
test('a later change request stops an in-progress demo review and reopens broker editing', async () => {
  const flow = fixture();
  const { links } = await flow.prepare();
  const agreed = await yes(flow, links[0]);
  await yes(flow, links[1]);
  await flow.review().submit({ agreementId: 'test', revision: 1 });
  await flow.owner().reply({ token: links[0].token, revision: 1, digest: agreed.digest,
    decision: 'change_requested', category: 'Dates', note: 'Please change the starting date.', operationId: 'after-review' });
  assert.equal(flow.get('agreements/test').status, 'draft');
  await assert.rejects(flow.review().submit({ agreementId: 'test', revision: 1 }));
});
test('expiry and reissue invalidate only the selected old link; retries do not rotate again', async () => {
  const flow = fixture();
  const old = await flow.prepare();
  flow.clock(old.links[0].expiresAtMs);
  await assert.rejects(flow.owner().read({ token: old.links[0].token }));
  const extra = { refreshPartyId: 'owner-1', operationId: 'refresh-1' };
  const next = await flow.prepare(1, extra);
  assert.notEqual(next.links[0].token, old.links[0].token);
  assert.equal(next.links[1].token, old.links[1].token);
  assert.deepEqual(await flow.prepare(1, extra), next);
  await assert.rejects(flow.owner().read({ token: old.links[0].token }));
  assert.equal((await flow.owner().read({ token: next.links[0].token })).verified, true);
});
test('disabled actors, changed contacts, tampered snapshots, other brokers and malformed links fail closed', async () => {
  for (const change of [{ revision: 2 }, { status: 'cancelled' }, { monthlyRentPaise: 2300000 }]) {
    const flow = fixture();
    const { links } = await flow.prepare();
    Object.assign(flow.get('agreements/test'), change);
    await assert.rejects(flow.owner().read({ token: links[0].token }));
  }
  const flow = fixture();
  const { links } = await flow.prepare();
  flow.set('users/owner', { roles: ['owner'], paused: true });
  await assert.rejects(flow.owner().read({ token: links[0].token }), { code: 'permission-denied' });
  await assert.rejects(flow.tenant().prepare({ agreementId: 'test', revision: 1, operationId: 'bad' }), { code: 'permission-denied' });
  for (const token of ['', '../../test', `${links[0].token.slice(0, -1)}z`]) await assert.rejects(flow.owner().read({ token }));
  flow.get('agreements/test').owners[0].phone = '+913333333333';
  await assert.rejects(flow.owner().read({ token: links[0].token }));
});
