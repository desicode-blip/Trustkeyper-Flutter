import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/auth/data/firebase_auth_service.dart';

class PhoneAuthFake extends Fake implements FirebaseAuth {
  final requests = <PhoneRequest>[];
  final credentials = <PhoneAuthCredential>[];
  User? activeUser;

  @override
  User? get currentUser => activeUser;

  @override
  Future<void> verifyPhoneNumber({
    String? phoneNumber,
    PhoneMultiFactorInfo? multiFactorInfo,
    required PhoneVerificationCompleted verificationCompleted,
    required PhoneVerificationFailed verificationFailed,
    required PhoneCodeSent codeSent,
    required PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
    String? autoRetrievedSmsCodeForTesting,
    Duration timeout = const Duration(seconds: 30),
    int? forceResendingToken,
    MultiFactorSession? multiFactorSession,
  }) async {
    requests.add(
      PhoneRequest(verificationCompleted, codeSent, codeAutoRetrievalTimeout),
    );
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    credentials.add(credential as PhoneAuthCredential);
    return NewPhoneUserCredential();
  }
}

class PhoneRequest {
  PhoneRequest(this.completed, this.sent, this.timedOut);

  final PhoneVerificationCompleted completed;
  final PhoneCodeSent sent;
  final PhoneCodeAutoRetrievalTimeout timedOut;
}

class NewPhoneUserCredential extends Fake implements UserCredential {
  @override
  User get user => PhoneUserFake();

  @override
  AdditionalUserInfo get additionalUserInfo =>
      AdditionalUserInfo(isNewUser: true);
}

class PhoneUserFake extends Fake implements User {
  @override
  List<UserInfo> get providerData => [];
}

class LinkedPhoneUserFake extends Fake implements User {
  final linkedCredentials = <AuthCredential>[];
  bool collision = false;
  String? linkedPhone;
  int refreshes = 0;

  @override
  String get uid => 'email-first-user';

  @override
  String get email => 'verified@example.com';

  @override
  bool get emailVerified => true;

  @override
  String? get phoneNumber => linkedPhone;

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    if (collision) {
      throw FirebaseAuthException(code: 'credential-already-in-use');
    }
    linkedCredentials.add(credential);
    linkedPhone = '+919999999999';
    return LinkedPhoneCredentialFake(this);
  }

  @override
  Future<void> reload() async {}

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    if (forceRefresh) refreshes++;
    return 'test-token';
  }
}

class LinkedPhoneCredentialFake extends Fake implements UserCredential {
  LinkedPhoneCredentialFake(this.linkedUser);
  final User linkedUser;

  @override
  User get user => linkedUser;

  @override
  AdditionalUserInfo get additionalUserInfo =>
      AdditionalUserInfo(isNewUser: false);
}

void main() {
  Future<void> sendLinkCode(
    FirebaseAuthService service,
    PhoneAuthFake auth,
  ) async {
    final request = service.requestPhoneOtp(
      phoneNumber: '9999999999',
      linkToCurrentUser: true,
      onCodeSent: () {},
      onError: (message) => fail(message),
      onAutoVerified: (_) {},
    );
    auth.requests.last.sent('link-session', 1);
    await request;
  }

  test(
    'email-first phone OTP links on the existing UID without sign-in',
    () async {
      final user = LinkedPhoneUserFake();
      final auth = PhoneAuthFake()..activeUser = user;
      final service = FirebaseAuthService.forTesting(auth: auth);
      await sendLinkCode(service, auth);
      final result = await service.verifyPhoneOtp(
        '123456',
        linkToCurrentUser: true,
      );
      expect(result.route, '/profile-setup');
      expect(auth.currentUser?.uid, 'email-first-user');
      expect(auth.credentials, isEmpty);
      expect(user.linkedCredentials, hasLength(1));
      expect(user.refreshes, 1);
    },
  );

  test('link code cannot be used as a separate phone sign-in', () async {
    final user = LinkedPhoneUserFake();
    final auth = PhoneAuthFake()..activeUser = user;
    final service = FirebaseAuthService.forTesting(auth: auth);
    await sendLinkCode(service, auth);
    await expectLater(
      service.verifyPhoneOtp('123456'),
      throwsA(isA<FirebaseAuthFailure>()),
    );
    expect(auth.credentials, isEmpty);
    expect(user.linkedCredentials, isEmpty);
  });

  test('changed session cannot consume the email account phone link', () async {
    final user = LinkedPhoneUserFake();
    final auth = PhoneAuthFake()..activeUser = user;
    final service = FirebaseAuthService.forTesting(auth: auth);
    await sendLinkCode(service, auth);
    auth.activeUser = null;
    await expectLater(
      service.verifyPhoneOtp('123456', linkToCurrentUser: true),
      throwsA(isA<FirebaseAuthFailure>()),
    );
    expect(auth.credentials, isEmpty);
    expect(user.linkedCredentials, isEmpty);
  });

  test('phone owned by another UID is not signed in or merged', () async {
    final user = LinkedPhoneUserFake()..collision = true;
    final auth = PhoneAuthFake()..activeUser = user;
    final service = FirebaseAuthService.forTesting(auth: auth);
    await sendLinkCode(service, auth);
    await expectLater(
      service.verifyPhoneOtp('123456', linkToCurrentUser: true),
      throwsA(
        isA<FirebaseAuthFailure>().having(
          (error) => error.message,
          'message',
          contains('not been merged'),
        ),
      ),
    );
    expect(auth.activeUser, same(user));
    expect(auth.credentials, isEmpty);
  });

  test(
    'automatic phone verification also links without account switching',
    () async {
      final user = LinkedPhoneUserFake();
      final auth = PhoneAuthFake()..activeUser = user;
      final service = FirebaseAuthService.forTesting(auth: auth);
      final routes = <String>[];
      final request = service.requestPhoneOtp(
        phoneNumber: '9999999999',
        linkToCurrentUser: true,
        onCodeSent: () => fail('Automatic linking already completed'),
        onError: (message) => fail(message),
        onAutoVerified: routes.add,
      );
      auth.requests.single.completed(
        PhoneAuthProvider.credential(
          verificationId: 'automatic-link',
          smsCode: '123456',
        ),
      );
      await request;
      expect(routes, ['/profile-setup']);
      expect(auth.credentials, isEmpty);
      expect(user.linkedCredentials, hasLength(1));
    },
  );
  test(
    'automatic verification before code sent signs in and navigates once',
    () async {
      final auth = PhoneAuthFake();
      final service = FirebaseAuthService.forTesting(auth: auth);
      final routes = <String>[];
      final pending = service.requestPhoneOtp(
        phoneNumber: '9999999999',
        onCodeSent: () => fail('Automatic verification already owns sign-in'),
        onError: (message) => fail(message),
        onAutoVerified: routes.add,
      );
      final credential = PhoneAuthProvider.credential(
        verificationId: 'automatic-session',
        smsCode: '123456',
      );
      auth.requests.single.completed(credential);
      auth.requests.single.completed(credential);
      auth.requests.single.sent('automatic-session', 1);
      await pending;
      expect(auth.credentials, hasLength(1));
      expect(routes, ['/profile-setup']);
    },
  );

  test('auto retrieval timeout leaves a delivered code usable', () async {
    final auth = PhoneAuthFake();
    final service = FirebaseAuthService.forTesting(auth: auth);
    final pending = service.requestPhoneOtp(
      phoneNumber: '9999999999',
      onCodeSent: () {},
      onError: (message) => fail(message),
      onAutoVerified: (_) {},
    );
    auth.requests.single.sent('manual-session', 1);
    await pending;
    auth.requests.single.timedOut('manual-session');
    final result = await service.verifyPhoneOtp('123456');
    expect(result.route, '/profile-setup');
    expect(auth.credentials.single.verificationId, 'manual-session');
  });

  test(
    'automatic callback after code sent does not consume the manual OTP',
    () async {
      final auth = PhoneAuthFake();
      final service = FirebaseAuthService.forTesting(auth: auth);
      final pending = service.requestPhoneOtp(
        phoneNumber: '9999999999',
        onCodeSent: () {},
        onError: (message) => fail(message),
        onAutoVerified: (_) => fail('The code screen owns verification now'),
      );
      auth.requests.single.sent('current-session', 1);
      await pending;
      auth.requests.single.completed(
        PhoneAuthProvider.credential(
          verificationId: 'current-session',
          smsCode: '123456',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(auth.credentials, isEmpty);
      final result = await service.verifyPhoneOtp('123456');
      expect(result.route, '/profile-setup');
      expect(auth.credentials, hasLength(1));
    },
  );

  test('old timeout cannot overwrite a resent verification session', () async {
    final auth = PhoneAuthFake();
    final service = FirebaseAuthService.forTesting(auth: auth);
    Future<void> request({bool resend = false}) => service.requestPhoneOtp(
      phoneNumber: '9999999999',
      resend: resend,
      onCodeSent: () {},
      onError: (message) => fail(message),
      onAutoVerified: (_) {},
    );
    final first = request();
    auth.requests.first.sent('old-session', 1);
    await first;
    final second = request(resend: true);
    auth.requests.last.sent('new-session', 2);
    await second;
    auth.requests.first.timedOut('old-session');
    await service.verifyPhoneOtp('123456');
    expect(auth.credentials.single.verificationId, 'new-session');
  });
}
