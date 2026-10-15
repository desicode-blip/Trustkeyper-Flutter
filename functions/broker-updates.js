import { createHash } from 'node:crypto';

export function documentSubmittedUpdate(requestId, record) {
  const id = createHash('sha256').update(JSON.stringify([
    requestId, record.version, record.submission.uploadId,
  ])).digest('hex');
  const paper = { all: 'documents', aadhaar: 'Aadhaar card', pan: 'PAN card', bank: 'bank details', linkedin: 'LinkedIn profile' }[record.type];
  return { id, data: {
    kind: 'documents_received', brokerUid: record.brokerUid,
    requestId, requestVersion: record.version, draftId: record.draftId,
    revision: record.revision, partyId: record.partyId, role: record.role,
    title: `${record.partyName} added ${paper}`,
    address: record.address, atMs: record.submission.atMs,
    readAt: null, pushState: 'pending', pushAcceptedDeviceIds: [],
  } };
}

export async function deliverBrokerUpdate({ store, messaging, now = Date.now }, brokerUid, updateId) {
  if (!/^[\w-]{1,128}$/.test(brokerUid) || !/^[a-f0-9]{64}$/.test(updateId)) throw new Error('Invalid update reference');
  const path = `users/${brokerUid}/updates/${updateId}`;
  const update = await store.transaction(async transaction => {
    const profile = await transaction.get(`users/${brokerUid}`);
    const record = await transaction.get(path);
    if (!record || record.brokerUid !== brokerUid || record.kind !== 'documents_received') return null;
    if (['accepted', 'no_devices', 'blocked'].includes(record.pushState)) return null;
    if (!profile?.roles?.includes('broker') || profile.approvalStatus !== 'approved' || profile.paused === true) {
      transaction.update(path, { pushState: 'blocked' });
      return null;
    }
    if (record.pushState === 'sending' && record.pushLeaseUntilMs > now()) throw new Error('Push lease active');
    transaction.update(path, { pushState: 'sending', pushLeaseUntilMs: now() + 120000 });
    return record;
  });
  if (!update) return;
  try {
    const accepted = new Set(update.pushAcceptedDeviceIds ?? []);
    const devices = (await store.devices(brokerUid)).filter(device => device.enabled === true &&
      typeof device.token === 'string' && device.token.length >= 20 && device.token.length <= 4096 &&
      device.updatedAtMs > now() - 30 * 86400000 && !accepted.has(device.id));
    if (devices.length === 0) {
      await store.update(path, { pushState: accepted.size ? 'accepted' : 'no_devices', pushLeaseUntilMs: 0 });
      return;
    }
    const result = await messaging.sendEachForMulticast({
      tokens: devices.map(device => device.token),
      notification: { title: 'TrustKeyper · documents received', body: 'Documents were uploaded. Open TrustKeyper to review them.' },
      data: { kind: 'broker_update', brokerUid, updateId },
      android: { priority: 'high', notification: { tag: updateId } },
    });
    let retry = false;
    if (!Array.isArray(result.responses) || result.responses.length !== devices.length) {
      throw new Error('Incomplete push response');
    }
    for (const [index, response] of result.responses.entries()) {
      const device = devices[index];
      if (response.success) accepted.add(device.id);
      else if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(response.error?.code)) {
        await store.disableDevice(brokerUid, device.id);
      } else retry = true;
    }
    await store.update(path, { pushState: retry ? 'retry' : accepted.size ? 'accepted' : 'no_devices',
      pushAcceptedDeviceIds: [...accepted], pushLeaseUntilMs: 0, pushAttemptedAtMs: now() });
    if (retry) throw new Error('Push delivery needs retry');
  } catch (error) {
    await store.update(path, { pushState: 'retry', pushLeaseUntilMs: 0 });
    throw error;
  }
}
