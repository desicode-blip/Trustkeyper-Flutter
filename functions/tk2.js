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
    return store.transaction(async tx => {
      const visit = await tx.get(`tk2Visits/${visitId}`);
      if (!visit || visit.brokerUid !== uid) throw new Tk2Error('permission-denied', 'This is not your visit.');
      const secret = await tx.get(`tk2Visits/${visitId}/secret/code`);
      const result = tk2CheckCode({ visit, secret, code: data?.code, nowMs: now() });
      if (result === null) tx.update(`tk2Visits/${visitId}`, { status: 'done', doneAt: now() });
      return { result: result ?? 'done' };
    });
  }
  return { confirmVisit };
}
