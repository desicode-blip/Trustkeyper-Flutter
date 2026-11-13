import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createTk2Service, tk2CheckCode, CODE_WINDOW_MS } from '../tk2.js';

const at = 1_800_000_000_000;
function fixture(visit = { brokerUid: 'broker', customerUid: 'tenant', status: 'booked', at }, code = '4821') {
  const data = new Map([['tk2Visits/v1', visit], ['tk2Visits/v1/secret/code', { code }]]);
  const store = {
    transaction: async handler => handler({
      get: async path => data.get(path),
      update: (path, values) => data.set(path, { ...data.get(path), ...values }),
    }),
  };
  let nowMs = at + 60_000;
  return { data, service: createTk2Service({ store, now: () => nowMs }), advance: ms => { nowMs += ms; } };
}

test('code check: right code inside 24 h only, booked visits only', () => {
  const visit = { status: 'booked', at };
  assert.equal(tk2CheckCode({ visit, secret: { code: '1234' }, code: ' 1234 ', nowMs: at }), null);
  assert.equal(tk2CheckCode({ visit, secret: { code: '1234' }, code: '1235', nowMs: at }), 'wrong');
  assert.equal(tk2CheckCode({ visit, secret: { code: '1234' }, code: '1234', nowMs: at + CODE_WINDOW_MS + 1 }), 'window');
  assert.equal(tk2CheckCode({ visit, secret: { code: '1234' }, code: '1234', nowMs: at - CODE_WINDOW_MS - 1 }), 'window');
  assert.equal(tk2CheckCode({ visit: { ...visit, status: 'cancelled' }, secret: { code: '1234' }, code: '1234', nowMs: at }), 'wrong');
  assert.equal(tk2CheckCode({ visit, secret: undefined, code: '1234', nowMs: at }), 'wrong');
});

test('only the broker of the visit can confirm; success marks it done', async () => {
  const { data, service } = fixture();
  await assert.rejects(service.confirmVisit(null, { visitId: 'v1', code: '4821' }), { code: 'unauthenticated' });
  await assert.rejects(service.confirmVisit({ uid: 'tenant' }, { visitId: 'v1', code: '4821' }), { code: 'permission-denied' });
  await assert.rejects(service.confirmVisit({ uid: 'broker' }, { visitId: '../x', code: '4821' }), { code: 'invalid-argument' });
  assert.deepEqual(await service.confirmVisit({ uid: 'broker' }, { visitId: 'v1', code: '0000' }), { result: 'wrong' });
  assert.equal(data.get('tk2Visits/v1').status, 'booked');
  assert.deepEqual(await service.confirmVisit({ uid: 'broker' }, { visitId: 'v1', code: '4821' }), { result: 'done' });
  assert.equal(data.get('tk2Visits/v1').status, 'done');
  const doneAt = data.get('tk2Visits/v1').doneAt;
  assert.deepEqual(await service.confirmVisit({ uid: 'broker' }, { visitId: 'v1', code: '4821' }), { result: 'done' });
  assert.equal(data.get('tk2Visits/v1').doneAt, doneAt);
});

test('wrong visit codes lock confirmation until the cooldown expires', async () => {
  const { advance, data, service } = fixture();
  const broker = { uid: 'broker' };
  for (let attempt = 0; attempt < 4; attempt++) {
    assert.deepEqual(await service.confirmVisit(broker, { visitId: 'v1', code: '0000' }), { result: 'wrong' });
  }
  assert.deepEqual(await service.confirmVisit(broker, { visitId: 'v1', code: '0000' }), { result: 'locked' });
  assert.deepEqual(await service.confirmVisit(broker, { visitId: 'v1', code: '4821' }), { result: 'locked' });
  assert.equal(data.get('tk2Visits/v1').status, 'booked');
  advance(15 * 60 * 1000);
  assert.deepEqual(await service.confirmVisit(broker, { visitId: 'v1', code: '4821' }), { result: 'done' });
});
