export function verifiedPhone(auth) {
  if (!auth?.uid) return null;
  const token = auth.token;
  const phone = token?.phone_number;
  if (typeof phone !== 'string' || !/^\+[1-9]\d{7,14}$/.test(phone)) return null;
  if (token.firebase?.sign_in_provider === 'phone') return phone;
  if (token.firebase?.sign_in_provider === 'custom' && token.trustkeyper_email_otp === true &&
      token.email_verified === true && typeof token.email === 'string' && token.email.length > 0 &&
      token.trustkeyper_verified_phone === phone) return phone;
  return null;
}
