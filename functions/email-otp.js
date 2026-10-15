import { createHmac, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';

const lifetimeMs = 5 * 60 * 1000;
const hourMs = 60 * 60 * 1000;

export class OtpError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

export function normalizeEmail(value) {
  if (typeof value !== 'string' || value.length > 254 ||
      !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value.trim())) {
    throw new OtpError('invalid-argument', 'Enter a valid email address.');
  }
  return value.trim().toLowerCase();
}

function nextRate(previous, timestamp, interval, limit) {
  const current = previous && timestamp - previous.startedAt < interval
    ? previous : { startedAt: timestamp, count: 0 };
  if (current.count >= limit) {
    throw new OtpError('resource-exhausted', 'Too many requests. Please try again later.');
  }
  return { startedAt: current.startedAt, count: current.count + 1 };
}

export function createEmailOtpService({ store, sendMail, issueToken, secret,
  purpose = 'sign-in', subjectUid = null, subjectContext = null,
  now = Date.now, generateCode = () => randomInt(0, 1000000).toString().padStart(6, '0'),
  generateId = randomUUID }) {
  if (typeof secret !== 'string' || secret.length < 32) {
    throw new Error('Email OTP secret must contain at least 32 characters.');
  }
  if (!['sign-in', 'profile-email', 'account-email'].includes(purpose) ||
      (purpose !== 'sign-in' && (typeof subjectUid !== 'string' || !subjectUid)) ||
      (purpose === 'account-email' && (typeof subjectContext !== 'string' || !subjectContext))) {
    throw new Error('Profile email codes require an authenticated subject.');
  }
  const digest = value => createHmac('sha256', secret).update(value).digest('hex');
  const contextHash = subjectContext === null ? null : digest(`identity:${subjectContext}`);

  async function request({ email: value, ip }) {
    const email = normalizeEmail(value);
    const challengeId = generateId();
    const code = generateCode();
    const timestamp = now();
    const path = `emailOtpChallenges/${digest(`email:${email}`)}`;
    const ipPath = `emailOtpRates/${digest(`ip:${ip || 'unknown'}`)}`;
    const globalPath = 'emailOtpRates/global';
    await store.transaction(async transaction => {
      const [previous, ipRate, globalRate] = await Promise.all([
        transaction.get(path), transaction.get(ipPath), transaction.get(globalPath),
      ]);
      if (previous?.lockedUntil > timestamp) {
        throw new OtpError('resource-exhausted', 'Too many incorrect codes. Try again after 15 minutes.');
      }
      if (previous && timestamp - previous.requestedAt < 60000) {
        throw new OtpError('resource-exhausted', 'Wait 60 seconds before requesting another code.');
      }
      const emailRate = nextRate(previous?.rate, timestamp, hourMs, 5);
      const nextIpRate = nextRate(ipRate, timestamp, hourMs, 20);
      const nextGlobalRate = nextRate(globalRate, timestamp, 24 * hourMs, 200);
      transaction.set(path, {
        challengeId, hash: digest(`${email}:${challengeId}:${code}`),
        purpose, subjectUid, contextHash,
        requestedAt: timestamp, expiresAt: timestamp + lifetimeMs,
        attempts: 0, status: 'pending', rate: emailRate,
      });
      transaction.set(ipPath, nextIpRate);
      transaction.set(globalPath, nextGlobalRate);
    });
    try {
      await sendMail({ email, code, challengeId });
    } catch {
      await store.transaction(async transaction => {
        const current = await transaction.get(path);
        if (current?.challengeId === challengeId) {
          transaction.set(path, { ...current, status: 'failed' });
        }
      });
      throw new OtpError('unavailable', 'The email could not be sent. Please try again shortly.');
    }
    await store.transaction(async transaction => {
      const current = await transaction.get(path);
      if (current?.challengeId !== challengeId || current.status !== 'pending') {
        throw new OtpError('failed-precondition', 'Request a new email code.');
      }
      transaction.set(path, { ...current, status: 'sent', expiresAt: now() + lifetimeMs });
    });
    return { challengeId, expiresInSeconds: 300, resendAfterSeconds: 60 };
  }

  async function verify({ email: value, challengeId, code }) {
    const email = normalizeEmail(value);
    if (typeof challengeId !== 'string' || challengeId.length > 128 ||
        typeof code !== 'string' || !/^\d{6}$/.test(code)) {
      throw new OtpError('invalid-argument', 'Enter the six-digit email code.');
    }
    const path = `emailOtpChallenges/${digest(`email:${email}`)}`;
    const verdict = await store.transaction(async transaction => {
      const current = await transaction.get(path);
      if (!current || current.challengeId !== challengeId ||
          (current.purpose ?? 'sign-in') !== purpose ||
          (current.subjectUid ?? null) !== subjectUid ||
          (current.contextHash ?? null) !== contextHash ||
          current.status !== 'sent' || current.expiresAt <= now()) {
        return 'expired';
      }
      if (current.attempts >= 5) return 'locked';
      const expected = Buffer.from(current.hash, 'hex');
      const supplied = Buffer.from(digest(`${email}:${challengeId}:${code}`), 'hex');
      if (!timingSafeEqual(expected, supplied)) {
        const attempts = current.attempts + 1;
        transaction.set(path, { ...current, attempts,
          ...(attempts >= 5 ? { lockedUntil: now() + 15 * 60 * 1000 } : {}) });
        return attempts >= 5 ? 'locked' : 'incorrect';
      }
      transaction.set(path, { ...current, status: 'used', usedAt: now() });
      return 'verified';
    });
    if (verdict === 'expired') {
      throw new OtpError('failed-precondition', 'This email code expired or was already used. Request a new one.');
    }
    if (verdict === 'locked') {
      throw new OtpError('resource-exhausted', 'Too many incorrect codes. Try again after 15 minutes.');
    }
    if (verdict === 'incorrect') {
      throw new OtpError('invalid-argument', 'That email code is incorrect. Try again.');
    }
    return issueToken(email);
  }
  return { request, verify };
}
