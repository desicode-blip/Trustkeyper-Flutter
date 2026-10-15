class AuthCapabilities {
  static const emailOtpEnabled = bool.fromEnvironment(
    'TRUSTKEYPER_EMAIL_OTP_ENABLED',
    defaultValue: true,
  );
}

String? profileIdentityError({
  required String email,
  required String? verifiedEmail,
  required bool emailVerified,
  required String? phone,
}) {
  if (email.isNotEmpty) {
    return emailVerified && verifiedEmail?.toLowerCase() == email.toLowerCase()
        ? null
        : 'Verify your email before choosing your role.';
  }
  return phone != null && RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)
      ? null
      : 'Log in with your phone before continuing without email.';
}
