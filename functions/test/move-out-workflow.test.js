import assert from 'node:assert/strict';
import { test } from 'node:test';
import { splitMoveOutCost } from '../move-out-workflow.js';
import { moveOutFixture } from './helpers/move-out-fixture.js';

test('move-out cost allocation preserves paise and deterministic remainders', () => {
  assert.deepEqual(splitMoveOutCost(101, [{ personId: 'first', depositPaise: 1 }, { personId: 'second', depositPaise: 1 }]), { first: 51, second: 50 });
  assert.throws(() => splitMoveOutCost(-1, [{ personId: 'first', depositPaise: 1 }]));
});

test('move-out requires signed current home, verified identity, active notice and approved broker', async () => {
  const flow = moveOutFixture();
  await assert.rejects(flow.service(null).read(flow.base), { code: 'unauthenticated' });
  await assert.rejects(flow.service('outsider').read({ ...flow.base, role: 'tenant' }), { code: 'permission-denied' });
  flow.records.get('users/broker').approvalStatus = 'pending';
  await assert.rejects(flow.service('broker').read(flow.base), { code: 'permission-denied' });
  flow.records.get('users/broker').approvalStatus = 'approved';
  flow.records.get('moveOuts/move-out-home').createdAtMs++;
  await assert.rejects(flow.service('broker').read(flow.base), { code: 'failed-precondition' });
});

test('booking respects notice date; physical records reject stale versions and forged evidence', async () => {
  const flow = moveOutFixture();
  await assert.rejects(flow.action('book', { date: '2026-11-09', slot: '09:00–12:00' }, 'tenant'), { code: 'invalid-argument' });
  await flow.action('book', { date: '2026-11-10', slot: '09:00–12:00' }, 'tenant');
  assert.equal((await flow.service('owner').read({ ...flow.base, role: 'owner' })).booking.status, 'requested');
  await assert.rejects(flow.service('broker').record({ ...flow.base, version: 1, operationId: 'a'.repeat(32), action: 'meters', payload: {} }), { code: 'aborted' });
  const item = (await flow.service('broker').read(flow.base)).rooms[0].items[0];
  flow.addPhoto('wrong-photo', 'move_in', item.id);
  await assert.rejects(flow.action('compare', { itemId: item.id, checkId: 'wrong-photo', condition: 'same', costPaise: 0, note: '' }), { code: 'invalid-argument' });
  await assert.rejects(flow.action('compare', { itemId: item.id, checkId: 'wrong-photo', condition: 'same', costPaise: 0, note: '' }, 'owner'), { code: 'permission-denied' });
});

test('key return has tenant count consent, scoped codes, replay-safe errors and persistent lockout', async () => {
  const flow = moveOutFixture();
  await flow.action('keys', { counts: { mainDoor: 2, bedrooms: 0, letterBox: 1, parkingCard: 1 }, personId: 'tenant' });
  await assert.rejects(flow.service('tenant').issueCode({ ...flow.base, role: 'tenant', countsConfirmed: false }), { code: 'invalid-argument' });
  await assert.rejects(flow.service('flatmate').issueCode({ ...flow.base, role: 'tenant', countsConfirmed: true }), { code: 'permission-denied' });
  const issued = await flow.service('tenant').issueCode({ ...flow.base, role: 'tenant', countsConfirmed: true });
  await assert.rejects(flow.service('tenant').issueCode({ ...flow.base, role: 'tenant', countsConfirmed: true }), { code: 'resource-exhausted' });
  const input = { ...flow.base, version: flow.records.get('moveOuts/move-out-home').version, operationId: 'd'.repeat(32),
    action: 'confirm_keys', payload: { code: '000000', challengeId: issued.challengeId } };
  assert.equal((await flow.service('broker').record(input)).codeAccepted, false);
  assert.equal((await flow.service('broker').record(input)).codeAccepted, false);
  for (let attempt = 0; attempt < 4; attempt++) await flow.action('confirm_keys', { code: '000000', challengeId: issued.challengeId });
  await assert.rejects(flow.action('confirm_keys', { code: issued.code, challengeId: issued.challengeId }), { code: 'failed-precondition' });
  flow.advance(31000);
  await assert.rejects(flow.action('keys', { counts: { mainDoor: 1, bedrooms: 0, letterBox: 1, parkingCard: 1 }, personId: 'tenant' }), { code: 'failed-precondition' });
});

test('actual room comparison, final meters, tenant key confirmation, decisions and refund queue never fabricate a transfer', async () => {
  const flow = moveOutFixture(); await flow.inspect(350001);
  await flow.action('publish', {});
  const published = flow.records.get('moveOuts/move-out-home').report;
  const line = published.lines[0];
  await assert.rejects(flow.action('compare', { itemId: line.id, checkId: line.afterId, condition: 'same', costPaise: 0, note: '' }), { code: 'failed-precondition' });
  await flow.action('owner_approve', { reportVersion: published.version, reviewedAllItems: true }, 'owner');
  await flow.action('respond', { reportVersion: published.version, itemId: line.id, status: 'agreed' }, 'flatmate');
  await flow.action('respond', { reportVersion: published.version, itemId: line.id, status: 'disputed', reason: 'These marks were present at move-in.' }, 'tenant');
  const before = await flow.service('tenant').read({ ...flow.base, role: 'tenant' });
  assert.equal(before.shares.length, 1); assert.equal(before.shares[0].heldPaise, 175000);
  await flow.action('decide', { reportVersion: published.version, itemId: line.id, amountPaise: 100001, reason: 'Photos show only some new marks.' }, 'admin');
  const decided = await flow.service('tenant').read({ ...flow.base, role: 'tenant' });
  assert.equal(decided.shares[0].heldPaise, 0); assert.equal(decided.shares[0].deductionsPaise, 50000);
  await flow.action('complete', { reportVersion: published.version, confirmedPhysicalHandover: true });
  await flow.action('destination', { reportVersion: published.version, method: 'bank_review', name: 'TEST tenant', account: '12345678901',
    ifsc: 'HDFC0001234', inMyName: true }, 'tenant');
  const tenant = await flow.service('tenant').read({ ...flow.base, role: 'tenant' });
  assert.equal(tenant.destination.maskedAccount, '•••• 8901'); assert.equal(tenant.destination.account, undefined);
  assert.equal((await flow.service('broker').read(flow.base)).destination, null);
  await flow.action('refund_request', { reportVersion: published.version, personId: 'tenant' }, 'admin');
  const requested = await flow.service('tenant').read({ ...flow.base, role: 'tenant' });
  assert.equal(requested.shares[0].refundStatus, 'awaiting_provider'); assert.equal(requested.shares[0].requestedPaise, 2150000);
  await assert.rejects(flow.action('destination', { reportVersion: published.version, method: 'original_payment' }, 'tenant'), { code: 'failed-precondition' });
  assert.equal(flow.records.get('moveOuts/move-out-home/destinations/tenant').method, 'bank_review');
  assert.equal(flow.records.get('properties/move-out-flat').activeAgreementId, 'move-out-home');
  await assert.rejects(flow.action('refund_request', { reportVersion: published.version, personId: 'tenant' }, 'admin'), { code: 'failed-precondition' });
  await assert.rejects(flow.action('decide', { reportVersion: published.version, itemId: line.id, amountPaise: 200000, reason: 'Trying to increase an agreed item.' }, 'owner'), { code: 'permission-denied' });
});

test('official move-out uploads are bound to current room; completed move-in baseline remains unchanged', async () => {
  const flow = moveOutFixture();
  const original = structuredClone(flow.records.get('tenancies/move-out-home'));
  const room = (await flow.service('broker').read(flow.base)).rooms[0];
  const item = room.items[0];
  const service = flow.photos('broker');
  const upload = await service.begin({ propertyId: 'move-out-flat', agreementId: 'move-out-home', role: 'broker',
    room: room.room, title: item.title, note: '', itemId: item.id, purpose: 'move_out', source: 'camera', operationId: 'f'.repeat(32) });
  await service.submit({ checkId: upload.checkId });
  assert.deepEqual(flow.records.get('tenancies/move-out-home'), original);
  assert.equal(flow.records.get('moveOuts/move-out-home').photoSlots[`move_out:${item.id}`], upload.checkId);
  const saved = await flow.service('broker').read(flow.base);
  assert.equal(saved.rooms[0].items[0].afterId, upload.checkId);
  assert.equal(saved.inspectionComplete, false);
});

test('move-out rejects stale notices, other tenants, future physical handover, missing live deposits and unwitnessed money', async () => {
  const flow = moveOutFixture();
  const original = structuredClone(flow.records.get('moveOuts/move-out-home'));
  flow.records.get('moveOuts/move-out-home').personIds = ['tenant'];
  await assert.rejects(flow.service('broker').read(flow.base), { code: 'failed-precondition' });
  flow.records.set('moveOuts/move-out-home', original);
  flow.advance(-86400000);
  await assert.rejects(flow.action('keys', { personId: 'tenant', counts: flow.records.get('tenancies/move-out-home').keys }), { code: 'failed-precondition' });
  flow.advance(86400000);
  await flow.inspect();
  flow.records.get('payments/pay_tenant').mode = 'test';
  await assert.rejects(flow.action('publish', {}), { code: 'failed-precondition' });
  flow.records.get('payments/pay_tenant').mode = 'live';
  await flow.action('publish', {});
  const reportVersion = flow.records.get('moveOuts/move-out-home').report.version;
  await assert.rejects(flow.action('destination', { reportVersion, method: 'bank_review', name: 'TEST tenant', account: '12345678901', ifsc: 'HDFC0001234', inMyName: false }, 'tenant'), { code: 'invalid-argument' });
  await assert.rejects(flow.action('refund_request', { reportVersion, personId: 'tenant' }, 'broker'), { code: 'permission-denied' });
  await assert.rejects(flow.action('destination', { reportVersion: reportVersion - 1, method: 'original_payment' }, 'tenant'), { code: 'aborted' });
});

test('owner review, unagreed deductions and all rent are independent refund gates', async () => {
  const flow = moveOutFixture(); await flow.inspect(350000); await flow.action('publish', {});
  const report = flow.records.get('moveOuts/move-out-home').report;
  await flow.action('complete', { reportVersion: report.version, confirmedPhysicalHandover: true });
  await flow.action('destination', { reportVersion: report.version, method: 'original_payment' }, 'tenant');
  await assert.rejects(flow.action('refund_request', { reportVersion: report.version, personId: 'tenant' }, 'admin'), { code: 'permission-denied' });
  await flow.action('owner_approve', { reportVersion: report.version, reviewedAllItems: true }, 'owner');
  const state = await flow.service('tenant').read({ ...flow.base, role: 'tenant' });
  assert.equal(state.shares[0].heldPaise, 175000); assert.equal(state.shares[0].refundableNowPaise, 2025000);
  const payment = structuredClone(flow.records.get('payments/pay_flatmate'));
  flow.records.get('payments/pay_flatmate').lines.pop();
  await assert.rejects(flow.action('refund_request', { reportVersion: report.version, personId: 'tenant' }, 'admin'), { code: 'failed-precondition' });
  flow.records.set('payments/pay_flatmate', payment);
  await flow.action('refund_request', { reportVersion: report.version, personId: 'tenant' }, 'admin');
  assert.equal((await flow.service('tenant').read({ ...flow.base, role: 'tenant' })).shares[0].refundStatus, 'awaiting_provider');
});

test('owner missed-item proposals require team evidence review, re-consent and immutable report history', async () => {
  const flow = moveOutFixture(); await flow.inspect(350000); await flow.action('publish', {});
  const state = await flow.service('broker').read(flow.base);
  const report = state.report;
  await flow.action('owner_approve', { reportVersion: report.version, reviewedAllItems: true }, 'owner');
  const item = state.rooms[0].items[1];
  await assert.rejects(flow.action('propose', { reportVersion: report.version, itemId: item.id, amountPaise: 80000, reason: 'TEST lock replacement was missed.' }, 'tenant'), { code: 'permission-denied' });
  await flow.action('propose', { reportVersion: report.version, itemId: item.id, amountPaise: 80000, reason: 'TEST lock replacement was missed.' }, 'owner');
  const proposal = Object.values(flow.records.get('moveOuts/move-out-home').proposals)[0];
  await assert.rejects(flow.action('review_proposal', { reportVersion: report.version, proposalId: proposal.id, amountPaise: 90000, decision: 'accept', reason: 'TEST proposed too much money.' }, 'admin'), { code: 'invalid-argument' });
  await flow.action('review_proposal', { reportVersion: report.version, proposalId: proposal.id, amountPaise: 70000, decision: 'accept', reason: 'TEST before and after justify partial cost.' }, 'admin');
  const revised = await flow.service('broker').read(flow.base);
  assert.equal(revised.report.lines.length, 2); assert.notEqual(revised.report.version, report.version); assert.equal(revised.ownersApproved, false);
  assert.deepEqual(revised.responses, {}); assert.equal(flow.records.get(`moveOuts/move-out-home/reports/${report.version}`).lines.length, 1);
  await assert.rejects(flow.action('owner_approve', { reportVersion: report.version, reviewedAllItems: true }, 'owner'), { code: 'aborted' });
});

test('rent continues until actual physical handover, then delayed settlement never invents later rent', async () => {
  const delayed = moveOutFixture(); delayed.advance(40 * 86400000);
  assert.ok((await delayed.service('broker').read(delayed.base)).rent.every(row => row.status === 'unpaid'));
  const flow = moveOutFixture(); await flow.inspect(); await flow.action('publish', {});
  await flow.action('complete', { reportVersion: flow.records.get('moveOuts/move-out-home').report.version, confirmedPhysicalHandover: true });
  flow.advance(40 * 86400000);
  const moveOut = await flow.service('broker').read(flow.base);
  assert.ok(moveOut.rent.every(row => row.status === 'paid'));
  flow.records.get('agreements/move-out-home').agreementCopy.people = flow.records.get('agreements/move-out-home').agreementCopy.people.filter(person => person.role !== 'owner');
  await assert.rejects(flow.service('broker').read(flow.base), { code: 'failed-precondition' });
});

test('an unresolved owner proposal blocks premature refunds without becoming an accepted deduction', async () => {
  const flow = moveOutFixture(); await flow.inspect(); await flow.action('publish', {});
  const current = await flow.service('owner').read({ ...flow.base, role: 'owner' });
  const reportVersion = current.report.version;
  await flow.action('complete', { reportVersion, confirmedPhysicalHandover: true });
  await flow.action('owner_approve', { reportVersion, reviewedAllItems: true }, 'owner');
  await flow.action('destination', { reportVersion, method: 'original_payment' }, 'tenant');
  await flow.action('propose', { reportVersion, itemId: current.rooms[0].items[0].id, amountPaise: 80000, reason: 'Actual lock replacement was missed.' }, 'owner');
  const pending = await flow.service('tenant').read({ ...flow.base, role: 'tenant' });
  assert.equal(pending.pendingOwnerReview, true); assert.equal(pending.shares[0].refundableNowPaise, 0);
  assert.equal(pending.shares[0].deductionsPaise, 0);
  await assert.rejects(flow.action('refund_request', { reportVersion, personId: 'tenant' }, 'admin'), { code: 'failed-precondition' });
  await flow.action('review_proposal', { reportVersion, proposalId: pending.proposals[0].id, decision: 'reject', reason: 'The original comparison shows no damage.' }, 'admin');
  await flow.action('refund_request', { reportVersion, personId: 'tenant' }, 'admin');
  assert.equal((await flow.service('tenant').read({ ...flow.base, role: 'tenant' })).shares[0].refundStatus, 'awaiting_provider');
});
