const operations = new Set(['requestEmailOtp', 'verifyEmailOtp', 'requestProfileEmailOtp', 'verifyProfileEmailOtp']);
const codes = new Set(['auth/insufficient-permission', 'auth/invalid-credential',
  'auth/internal-error', 'auth/invalid-argument', 'auth/email-already-exists',
  'auth/user-not-found', 'auth/project-not-found', 'app/invalid-credential']);
const types = new Set(['Error', 'FirebaseError', 'FirebaseAuthError', 'FirebaseAppError']);

export function emailFailureMetadata(operation, error) {
  return {
    operation: operations.has(operation) ? operation : 'unknown',
    code: codes.has(error?.code) ? error.code : 'unknown',
    type: types.has(error?.name) ? error.name : 'unknown',
  };
}
