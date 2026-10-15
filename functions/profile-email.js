import { normalizeEmail, OtpError } from './email-otp.js';

export function createProfileEmailBinding({ auth, getProfile, updateProfile,
  uid, authTime, now = Date.now, allowEmailChange = false, expectedIdentity = null }) {
  async function check(value) {
    if (typeof uid !== 'string' || !uid) {
      throw new OtpError('unauthenticated', 'Log in with your phone before verifying your email.');
    }
    const age = now() / 1000 - authTime;
    if (!Number.isInteger(authTime) || age < -60 || age > 15 * 60) {
      throw new OtpError('unauthenticated', 'For safety, log in again before verifying your email.');
    }
    const email = normalizeEmail(value);
    const user = await auth.getUser(uid);
    const profile = await getProfile(uid);
    if (user.disabled || profile?.paused === true || !user.phoneNumber ||
        profile?.roles?.includes('admin') || user.customClaims?.admin === true ||
        user.customClaims?.roles?.includes('admin')) {
      throw new OtpError('permission-denied', 'This account cannot use profile email verification.');
    }
    if (allowEmailChange && !profile?.roles?.some(role => ['broker', 'owner', 'tenant'].includes(role))) {
      throw new OtpError('permission-denied', 'Finish setting up your account before editing its email.');
    }
    const identityContext = JSON.stringify([user.email?.toLowerCase() ?? '', user.phoneNumber]);
    if (expectedIdentity !== null && expectedIdentity !== identityContext) {
      throw new OtpError('aborted', 'Your account contact changed. Request a new email code.');
    }
    if (!allowEmailChange && user.email && user.email.toLowerCase() !== email) {
      throw new OtpError('failed-precondition', 'Changing an existing account email requires account recovery. Contact support.');
    }
    try {
      const existing = await auth.getUserByEmail(email);
      if (existing.uid !== uid) {
        throw new OtpError('already-exists', 'This email belongs to another account. Use a different email or contact support.');
      }
    } catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;
    }
    return { email, profile, identityContext };
  }

  async function link(value) {
    const { email, profile } = await check(value);
    try {
      await auth.updateUser(uid, { email, emailVerified: true });
    } catch (error) {
      if (error.code === 'auth/email-already-exists') {
        throw new OtpError('already-exists', 'This email belongs to another account. Contact support.');
      }
      throw error;
    }
    if (profile) await updateProfile(uid, email);
    return { uid, email, verified: true };
  }
  return { uid, check, link };
}
