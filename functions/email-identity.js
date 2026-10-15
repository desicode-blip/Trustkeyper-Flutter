import { OtpError } from './email-otp.js';

export function createEmailTokenIssuer({ auth, getProfile }) {
  return async email => {
    let user;
    try {
      user = await auth.getUserByEmail(email);
    } catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;
      try {
        user = await auth.createUser({ email, emailVerified: true });
      } catch (creationError) {
        if (creationError.code !== 'auth/email-already-exists') throw creationError;
        user = await auth.getUserByEmail(email);
      }
    }
    const profile = await getProfile(user.uid);
    if (user.disabled || profile?.paused === true) {
      throw new OtpError('permission-denied', 'This account is paused. Contact support.');
    }
    if (profile?.roles?.includes('admin') || user.customClaims?.admin === true ||
        user.customClaims?.roles?.includes('admin')) {
      throw new OtpError('permission-denied', 'Administrators must use the admin sign-in page.');
    }
    if (!user.emailVerified) await auth.updateUser(user.uid, { emailVerified: true });
    const claims = { trustkeyper_email_otp: true };
    if (typeof user.phoneNumber === 'string' && /^\+[1-9]\d{7,14}$/.test(user.phoneNumber)) {
      claims.trustkeyper_verified_phone = user.phoneNumber;
    }
    return { customToken: await auth.createCustomToken(user.uid, claims) };
  };
}
