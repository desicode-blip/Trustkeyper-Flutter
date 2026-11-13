// TrustKeeper 2: server-only steps. See docs/TRUSTKEEPER2-BACKEND.md.
//
// tk2ConfirmVisit: the broker types the tenant's 4-digit code after the visit.
// The code lives in tk2Visits/{id}/secret/code, which only the tenant can read,
// so the check must run here. On success the visit becomes "done" and the
// visit fee is released to the broker (payout itself is still manual/test).

export class Tk2Error extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

/// Same window as the app (Tk2Visit.codeWorks): 24 hours before or after the visit time.
export const CODE_WINDOW_MS = 24 * 60 * 60 * 1000;
const MAX_FAILED_CODES = 5;
const CODE_LOCK_MS = 15 * 60 * 1000;

/// Pure check, shared by the callable and the tests.
/// Returns null when the visit may be marked done, else 'wrong' or 'window'.
export function tk2CheckCode({ visit, secret, code, nowMs }) {
  if (!visit || visit.status !== 'booked' || !secret || String(code ?? '').trim() !== secret.code) return 'wrong';
  if (Math.abs(nowMs - visit.at) > CODE_WINDOW_MS) return 'window';
  return null;
}

/// store: { transaction(handler) } where handler gets { get(path), update(path, data) }.
export function createTk2Service({ store, now = () => Date.now() }) {
  async function confirmVisit(auth, data) {
    const uid = auth?.uid;
    const visitId = data?.visitId;
    if (!uid) throw new Tk2Error('unauthenticated', 'Log in again.');
    if (typeof visitId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(visitId)) throw new Tk2Error('invalid-argument', 'Unknown visit.');
    const code = typeof data?.code === 'string' ? data.code.trim() : '';
    if (!/^[0-9]{4}$/.test(code)) throw new Tk2Error('invalid-argument', 'Enter the four-digit visit code.');
    return store.transaction(async tx => {
      const visitPath = `tk2Visits/${visitId}`;
      const visit = await tx.get(visitPath);
      if (!visit || visit.brokerUid !== uid) throw new Tk2Error('permission-denied', 'This is not your visit.');
      const nowMs = now();
      if (visit.status === 'done') return { result: 'done' };
      if (visit.status !== 'booked') return { result: 'wrong' };
      if (typeof visit.at !== 'number' || !Number.isFinite(visit.at) || Math.abs(nowMs - visit.at) > CODE_WINDOW_MS) return { result: 'window' };
      if ((visit.codeLockUntil ?? 0) > nowMs) return { result: 'locked' };
      const secret = await tx.get(`${visitPath}/secret/code`);
      const result = tk2CheckCode({ visit, secret, code, nowMs });
      if (result === null) {
        tx.update(visitPath, { status: 'done', doneAt: nowMs, failedCodes: 0, codeLockUntil: 0 });
      } else if (result === 'wrong') {
        const failedCodes = visit.codeLockUntil ? 1 : (visit.failedCodes ?? 0) + 1;
        const codeLockUntil = failedCodes >= MAX_FAILED_CODES ? nowMs + CODE_LOCK_MS : 0;
        tx.update(visitPath, { failedCodes, codeLockUntil });
        if (codeLockUntil) return { result: 'locked' };
      }
      return { result: result ?? 'done' };
    });
  }
  return { confirmVisit };
}

export function createTk2FileFinalizer({ getRecord, bucket }) {
  return async (auth, path) => {
    const uid = auth?.uid;
    if (!uid) throw new Tk2Error('unauthenticated', 'Log in again.');
    const match = typeof path === 'string' && /^tk2\/(visits|deals)\/([A-Za-z0-9_-]{1,128})\/([A-Za-z0-9_-]{1,64}\.[A-Za-z0-9]{1,16})$/.exec(path);
    if (!match) throw new Tk2Error('invalid-argument', 'Unknown file.');
    const [, kind, id] = match;
    const visit = kind === 'visits';
    const record = await getRecord(visit ? `tk2Visits/${id}` : `tk2Deals/${id}`);
    if (!record || !(visit ? record.brokerUid === uid : [record.brokerUid, record.tenantUid, record.verifiedOwnerUid].includes(uid))) {
      throw new Tk2Error('permission-denied', 'You cannot add a file here.');
    }
    const source = bucket.file(`tk2Uploads/${uid}/${path}`);
    const destination = bucket.file(path);
    const existing = await readMetadata(destination);
    if (existing) {
      confirmPrivateFile(existing, uid);
      await source.delete({ ignoreNotFound: true });
      return { path };
    }
    const original = await readMetadata(source);
    if (!original) throw new Tk2Error('not-found', 'The upload has not finished.');
    const size = Number(original.size);
    const type = original.contentType;
    const document = /^image\/(jpeg|png)$|^application\/pdf$/.test(type);
    const dealImage = !visit && /^image\/(webp|heic)$/.test(type);
    const video = !visit && /^video\/[A-Za-z0-9.+-]+$/.test(type);
    if (!Number.isSafeInteger(size) || size <= 0 || !(document || dealImage || video) || size > (video ? 200 : 10) * 1024 * 1024) {
      throw new Tk2Error('invalid-argument', 'The uploaded file type or size is not allowed.');
    }
    try {
      await bucket.file(source.name, { generation: original.generation }).copy(destination, {
        preconditionOpts: { ifGenerationMatch: 0 }, contentType: type, cacheControl: 'private, no-store',
        metadata: { sourceUid: uid, firebaseStorageDownloadTokens: null },
      });
    } catch (error) {
      if (error.code !== 412) throw error;
    }
    confirmPrivateFile(await readMetadata(destination), uid);
    await source.delete({ ignoreNotFound: true });
    return { path };
  };
}

async function readMetadata(file) {
  try {
    const [metadata] = await file.getMetadata();
    return metadata;
  } catch (error) {
    if (error.code !== 404) throw error;
    return null;
  }
}

function confirmPrivateFile(metadata, uid) {
  if (metadata?.metadata?.sourceUid !== uid || metadata.metadata.firebaseStorageDownloadTokens) {
    throw new Tk2Error('failed-precondition', 'The private file could not be confirmed.');
  }
}
