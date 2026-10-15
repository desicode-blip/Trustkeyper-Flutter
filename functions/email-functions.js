import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { error as logError } from 'firebase-functions/logger';
import { emailFailureMetadata } from './email-diagnostics.js';
import { createEmailOtpService, OtpError } from './email-otp.js';
import { createEmailTokenIssuer } from './email-identity.js';
import { createProfileEmailBinding } from './profile-email.js';
import { createAccountEmailBinding } from './account-email.js';
import { createResendEmailSender } from './resend-email.js';

const resendApiKey = defineSecret('RESEND_API_KEY');
const otpSecret = defineSecret('EMAIL_OTP_SECRET');
const emailFrom = 'TrustKeyper <noreply@trustkeyper.com>';
const options = {
  region: 'asia-south1', maxInstances: 3, timeoutSeconds: 60,
  cpu: 'gcf_gen1', concurrency: 1, memory: '256MiB',
  secrets: [resendApiKey, otpSecret],
};

function service(binding = null, purpose = binding ? 'profile-email' : 'sign-in') {
  const database = getFirestore();
  const auth = getAuth();
  return createEmailOtpService({
    purpose,
    subjectUid: binding?.uid ?? null,
    subjectContext: binding?.identityContext ?? null,
    secret: otpSecret.value(),
    store: {
      transaction: handler => database.runTransaction(transaction => handler({
        get: async path => (await transaction.get(database.doc(path))).data(),
        set: (path, data) => transaction.set(database.doc(path), data),
      })),
    },
    sendMail: createResendEmailSender({ apiKey: resendApiKey.value(), from: emailFrom }),
    issueToken: binding ? binding.link : createEmailTokenIssuer({ auth,
      getProfile: async uid => (await database.doc(`users/${uid}`).get()).data(),
    }),
  });
}

async function execute(name, operation) {
  try {
    return await operation();
  } catch (error) {
    if (error instanceof OtpError) throw new HttpsError(error.code, error.message);
    logError('Email OTP operation failed', emailFailureMetadata(name, error));
    throw new HttpsError('internal', 'Email sign-in could not be completed. Request a new code and try again.');
  }
}

export const requestEmailOtp = onCall(options, request => execute('requestEmailOtp', () => service().request({
  email: request.data?.email, ip: request.rawRequest.ip,
})));
export const verifyEmailOtp = onCall(options, request => execute('verifyEmailOtp', () => service().verify({
  email: request.data?.email, challengeId: request.data?.challengeId, code: request.data?.code,
})));

function profileBindingOptions(request) {
  const database = getFirestore();
  return {
    auth: getAuth(), uid: request.auth?.uid, authTime: request.auth?.token.auth_time,
    getProfile: async uid => (await database.doc(`users/${uid}`).get()).data(),
    updateProfile: (uid, email) => database.doc(`users/${uid}`).update({
      email, emailVerifiedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    }),
  };
}

function profileBinding(request) {
  return createProfileEmailBinding(profileBindingOptions(request));
}

export const requestProfileEmailOtp = onCall(options, request => execute('requestProfileEmailOtp', async () => {
  const binding = profileBinding(request);
  await binding.check(request.data?.email);
  return service(binding).request({ email: request.data?.email, ip: request.rawRequest.ip });
}));

export const verifyProfileEmailOtp = onCall(options, request => execute('verifyProfileEmailOtp', async () => {
  const binding = profileBinding(request);
  await binding.check(request.data?.email);
  return service(binding).verify({
    email: request.data?.email, challengeId: request.data?.challengeId, code: request.data?.code,
  });
}));

export const requestAccountEmailOtp = onCall(options, request => execute('requestAccountEmailOtp', async () => {
  const binding = await createAccountEmailBinding(profileBindingOptions(request), request.data?.email);
  return service(binding, 'account-email').request({ email: request.data?.email, ip: request.rawRequest.ip });
}));

export const verifyAccountEmailOtp = onCall(options, request => execute('verifyAccountEmailOtp', async () => {
  const binding = await createAccountEmailBinding(profileBindingOptions(request), request.data?.email);
  return service(binding, 'account-email').verify({
    email: request.data?.email, challengeId: request.data?.challengeId, code: request.data?.code,
  });
}));
