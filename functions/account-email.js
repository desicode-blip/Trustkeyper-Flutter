import { OtpError } from './email-otp.js';
import { createProfileEmailBinding } from './profile-email.js';

export async function createAccountEmailBinding(options, email) {
  const initial = createProfileEmailBinding({ ...options, allowEmailChange: true });
  const context = await initial.check(email);
  const binding = createProfileEmailBinding({ ...options, allowEmailChange: true, expectedIdentity: context.identityContext });
  return {
    uid: binding.uid,
    identityContext: context.identityContext,
    async link(address) {
      const result = await binding.link(address);
      const person = await options.auth.getUser(binding.uid);
      const profile = await options.getProfile(binding.uid);
      if (person.disabled || profile?.paused === true || person.email?.toLowerCase() !== result.email ||
          person.emailVerified !== true || !person.phoneNumber || profile?.roles?.includes('admin') ||
          person.customClaims?.admin === true || person.customClaims?.roles?.includes('admin')) {
        throw new OtpError('aborted', 'Your account changed. Log in again before continuing.');
      }
      return { ...result, customToken: await options.auth.createCustomToken(binding.uid, {
        trustkeyper_email_otp: true, trustkeyper_verified_phone: person.phoneNumber,
      }) };
    },
  };
}
