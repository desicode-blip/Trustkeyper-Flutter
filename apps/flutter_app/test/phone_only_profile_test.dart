import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/auth/data/auth_capabilities.dart';

void main() {
  test('email OTP is enabled for the Firebase test release', () {
    expect(AuthCapabilities.emailOtpEnabled, true);
  });
  test('phone-only identity never needs or invents a verified email', () {
    expect(
      profileIdentityError(
        email: '',
        verifiedEmail: null,
        emailVerified: false,
        phone: '+919999999999',
      ),
      isNull,
    );
    expect(
      profileIdentityError(
        email: '',
        verifiedEmail: null,
        emailVerified: false,
        phone: null,
      ),
      isNotNull,
    );
    expect(
      profileIdentityError(
        email: '',
        verifiedEmail: null,
        emailVerified: false,
        phone: 'invalid',
      ),
      isNotNull,
    );
  });
  test(
    'entered email still requires actual same-account email verification',
    () {
      expect(
        profileIdentityError(
          email: 'test@example.com',
          verifiedEmail: 'test@example.com',
          emailVerified: false,
          phone: '+919999999999',
        ),
        isNotNull,
      );
      expect(
        profileIdentityError(
          email: 'other@example.com',
          verifiedEmail: 'test@example.com',
          emailVerified: true,
          phone: '+919999999999',
        ),
        isNotNull,
      );
      expect(
        profileIdentityError(
          email: 'test@example.com',
          verifiedEmail: 'test@example.com',
          emailVerified: true,
          phone: null,
        ),
        isNull,
      );
    },
  );
}
