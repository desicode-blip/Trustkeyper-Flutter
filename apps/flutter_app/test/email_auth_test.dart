import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/auth/presentation/auth_screens.dart';
import 'package:trustkeyper/src/features/auth/data/firebase_auth_service.dart';

class EmailFunctionsFake extends Fake implements FirebaseFunctions {
  final calls = <({String name, dynamic data})>[];
  String challengeId = 'first-challenge';
  bool deliveryFails = false;
  String responseUid = 'phone-user';
  Future<Map<String, dynamic>> Function(String, dynamic)? responseOverride;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      EmailCallableFake((data) async {
        calls.add((name: name, data: data));
        if (responseOverride != null) return responseOverride!(name, data);
        if (name == 'requestEmailOtp' || name == 'requestProfileEmailOtp') {
          if (deliveryFails) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'Email could not be sent.',
            );
          }
          return {'challengeId': challengeId};
        }
        if (name == 'verifyProfileEmailOtp') {
          return {'uid': responseUid, 'email': data['email'], 'verified': true};
        }
        return {'customToken': 'verified-email-token'};
      });
}

class EmailCallableFake extends Fake implements HttpsCallable {
  EmailCallableFake(this.handler);
  final Future<Map<String, dynamic>> Function(dynamic) handler;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async =>
      EmailCallableResult<T>((await handler(parameters)) as T);
}

class EmailCallableResult<T> extends Fake implements HttpsCallableResult<T> {
  EmailCallableResult(this.result);
  final T result;

  @override
  T get data => result;
}

class EmailAuthFake extends Fake implements FirebaseAuth {
  final signedInTokens = <String>[];
  User? activeUser;
  User? tokenUser;

  @override
  User? get currentUser => activeUser;

  @override
  Future<void> signOut() async {
    activeUser = null;
  }

  @override
  Future<UserCredential> signInWithCustomToken(String token) async {
    signedInTokens.add(token);
    if (tokenUser != null) {
      activeUser = tokenUser;
      return BoundEmailCredentialFake(tokenUser!);
    }
    return EmailUserCredentialFake();
  }
}

class BoundEmailCredentialFake extends Fake implements UserCredential {
  BoundEmailCredentialFake(this.person);
  final User person;
  @override
  User get user => person;
}

class EmailUserCredentialFake extends Fake implements UserCredential {
  @override
  User get user => EmailUserFake();

  @override
  AdditionalUserInfo get additionalUserInfo =>
      AdditionalUserInfo(isNewUser: true);
}

class EmailUserFake extends Fake implements User {
  @override
  List<UserInfo> get providerData => [];
}

class PhoneProfileUserFake extends Fake implements User {
  PhoneProfileUserFake({this.userUid = 'phone-user'});
  final String userUid;
  bool verified = false;
  int tokenRefreshes = 0;

  @override
  String get uid => userUid;

  @override
  String? get phoneNumber => '+919999999999';

  @override
  String? get email => verified ? 'ajay@example.com' : null;

  @override
  bool get emailVerified => verified;

  @override
  Future<void> reload() async {
    verified = true;
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    if (forceRefresh) tokenRefreshes++;
    return 'test-token';
  }
}

class ProfileScreenAuthFake extends Fake implements FirebaseAuthService {
  bool failDelivery = false;
  bool failPreference = false;
  User? activeUser;
  int emailRequests = 0;
  String? requestedEmail;
  String? savedName;
  String? savedEmail;
  bool? rememberedSession;
  bool? phoneLinkRequested;
  String? requestedPhone;
  bool autoVerifyPhone = false;

  @override
  Future<void> configureSessionPersistence({required bool keepLoggedIn}) async {
    if (failPreference) {
      throw const FirebaseAuthFailure('Could not save your login preference.');
    }
    rememberedSession = keepLoggedIn;
  }

  @override
  User? get currentUser => activeUser;

  @override
  Future<String> requestEmailOtp(String email) async {
    emailRequests++;
    requestedEmail = email;
    if (failDelivery) {
      throw const FirebaseAuthFailure('Email could not be sent.');
    }
    return 'sent-email-challenge';
  }

  @override
  void savePendingProfile({required String name, required String email}) {
    savedName = name;
    savedEmail = email;
  }

  @override
  Future<String> requestProfileEmailOtp(String email) async {
    emailRequests++;
    if (failDelivery) {
      throw const FirebaseAuthFailure('Email could not be sent.');
    }
    return 'bound-profile-challenge';
  }

  @override
  Future<void> requestPhoneOtp({
    required String phoneNumber,
    required void Function() onCodeSent,
    required void Function(String message) onError,
    required void Function(String route) onAutoVerified,
    bool resend = false,
    bool linkToCurrentUser = false,
  }) async {
    requestedPhone = phoneNumber;
    phoneLinkRequested = linkToCurrentUser;
    if (failDelivery) {
      onError('Phone code could not be sent.');
    } else if (autoVerifyPhone) {
      onAutoVerified('/profile-setup');
    } else {
      onCodeSent();
    }
  }
}

class EmailFirstProfileUserFake extends PhoneProfileUserFake {
  @override
  bool get emailVerified => true;

  @override
  String get email => 'email-first@example.com';

  @override
  String? get phoneNumber => null;
}

void main() {
  testWidgets(
    'automatic profile phone verification advances instead of reopening the same page',
    (tester) async {
      final auth = ProfileScreenAuthFake()
        ..activeUser = EmailFirstProfileUserFake()
        ..autoVerifyPhone = true;
      final router = GoRouter(
        initialLocation: '/profile-setup',
        routes: [
          GoRoute(
            path: '/profile-setup',
            builder: (context, state) => ProfileSetupScreen(
              authService: auth,
              verifiedEmail: 'email-first@example.com',
              requiresPhoneVerification: true,
            ),
          ),
          GoRoute(
            path: '/roles',
            builder: (context, state) =>
                const Scaffold(body: Text('Linked account roles')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Ajay');
      await tester.enterText(find.byType(TextFormField).at(1), '9999999999');
      await tester.tap(find.text('Send OTP to phone'));
      await tester.pumpAndSettle();
      expect(find.text('Linked account roles'), findsOneWidget);
      expect(auth.phoneLinkRequested, true);
      expect(auth.savedEmail, 'email-first@example.com');
    },
  );
  for (final failure in [false, true]) {
    testWidgets(
      'email-first onboarding requests a phone link (failure=$failure)',
      (tester) async {
        final auth = ProfileScreenAuthFake()
          ..activeUser = EmailFirstProfileUserFake()
          ..failDelivery = failure;
        final router = GoRouter(
          initialLocation: '/profile-setup',
          routes: [
            GoRoute(
              path: '/profile-setup',
              builder: (context, state) => ProfileSetupScreen(
                authService: auth,
                verifiedEmail: 'email-first@example.com',
                requiresPhoneVerification: true,
              ),
            ),
            GoRoute(
              path: '/otp',
              builder: (context, state) => Scaffold(
                body: Text(
                  '${state.uri.queryParameters['purpose']}:${state.uri.queryParameters['destination']}',
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(theme: AppTheme.light, routerConfig: router),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(0), 'Ajay');
        await tester.enterText(find.byType(TextFormField).at(1), '9999999999');
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(2))
              .enabled,
          false,
        );
        await tester.tap(find.text('Send OTP to phone'));
        await tester.pumpAndSettle();
        expect(auth.phoneLinkRequested, true);
        expect(auth.requestedPhone, '9999999999');
        expect(auth.savedEmail, 'email-first@example.com');
        expect(auth.emailRequests, 0);
        expect(
          find.text('profile-phone:9999999999'),
          failure ? findsNothing : findsOneWidget,
        );
        if (failure) {
          expect(find.text('Phone code could not be sent.'), findsOneWidget);
        }
      },
    );
  }
  for (final scenario in [
    (deliveryFails: false, preferenceFails: false),
    (deliveryFails: true, preferenceFails: false),
    (deliveryFails: false, preferenceFails: true),
  ]) {
    final deliveryFails = scenario.deliveryFails;
    testWidgets(
      'email login requires persistence and delivery acceptance ($scenario)',
      (tester) async {
        final auth = ProfileScreenAuthFake()
          ..failDelivery = deliveryFails
          ..failPreference = scenario.preferenceFails;
        final router = GoRouter(
          initialLocation: '/login',
          routes: [
            GoRoute(
              path: '/login',
              builder: (context, state) => LoginScreen(authService: auth),
            ),
            GoRoute(
              path: '/otp',
              builder: (context, state) => Scaffold(
                body: Text(
                  'email:${state.uri.queryParameters['destination']}:${state.uri.queryParameters['challengeId']}',
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(theme: AppTheme.light, routerConfig: router),
        );
        await tester.tap(find.text('Email'));
        await tester.pump();
        await tester.enterText(find.byType(TextField), ' OWNER@example.com ');
        if (deliveryFails) await tester.tap(find.text('Keep me logged in'));
        await tester.tap(find.text('Get OTP'));
        await tester.pumpAndSettle();
        expect(auth.emailRequests, scenario.preferenceFails ? 0 : 1);
        expect(
          auth.rememberedSession,
          scenario.preferenceFails ? null : !deliveryFails,
        );
        expect(
          auth.requestedEmail,
          scenario.preferenceFails ? null : 'owner@example.com',
        );
        expect(
          find.text('email:owner@example.com:sent-email-challenge'),
          deliveryFails || scenario.preferenceFails
              ? findsNothing
              : findsOneWidget,
        );
        if (deliveryFails) {
          expect(find.text('Email could not be sent.'), findsOneWidget);
        }
        if (scenario.preferenceFails) {
          expect(
            find.text('Could not save your login preference.'),
            findsOneWidget,
          );
        }
      },
    );
  }

  test(
    'sign-out invalidates a delayed email request before it can replace the challenge',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final functions = EmailFunctionsFake()
        ..responseOverride = ((name, data) => pending.future);
      final service = FirebaseAuthService.forTesting(
        auth: EmailAuthFake(),
        functions: functions,
      );
      final response = service.requestEmailOtp('owner@example.com');
      final rejected = expectLater(
        response,
        throwsA(isA<FirebaseAuthFailure>()),
      );
      await service.signOut();
      pending.complete({'challengeId': 'old-response'});
      await rejected;
    },
  );

  test(
    'a delayed email verification never replaces a changed Firebase session',
    () async {
      final functions = EmailFunctionsFake();
      final auth = EmailAuthFake();
      final service = FirebaseAuthService.forTesting(
        auth: auth,
        functions: functions,
      );
      final challenge = await service.requestEmailOtp('owner@example.com');
      final pending = Completer<Map<String, dynamic>>();
      functions.responseOverride = ((name, data) => pending.future);
      final response = service.verifyEmailOtp(
        email: 'owner@example.com',
        code: '123456',
        challengeId: challenge,
      );
      final rejected = expectLater(
        response,
        throwsA(isA<FirebaseAuthFailure>()),
      );
      auth.activeUser = PhoneProfileUserFake(userUid: 'new-phone-session');
      pending.complete({'customToken': 'stale-token'});
      await rejected;
      expect(auth.signedInTokens, isEmpty);
      expect(auth.currentUser?.uid, 'new-phone-session');
    },
  );

  for (final authenticated in [true, false]) {
    testWidgets(
      'deferred email requires phone identity (signed in=$authenticated)',
      (tester) async {
        final auth = ProfileScreenAuthFake()
          ..activeUser = authenticated ? PhoneProfileUserFake() : null;
        final router = GoRouter(
          initialLocation: '/profile-setup',
          routes: [
            GoRoute(
              path: '/profile-setup',
              builder: (context, state) =>
                  ProfileSetupScreen(authService: auth, emailOtpEnabled: false),
            ),
            GoRoute(
              path: '/roles',
              builder: (context, state) =>
                  const Scaffold(body: Text('Verified phone roles')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(theme: AppTheme.light, routerConfig: router),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(1))
              .enabled,
          false,
        );
        await tester.enterText(find.byType(TextFormField).first, 'Ajay');
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(auth.savedEmail, '');
        expect(auth.emailRequests, 0);
        expect(
          find.text('Verified phone roles'),
          authenticated ? findsOneWidget : findsNothing,
        );
        if (!authenticated) {
          expect(
            find.text('Log in with your verified phone again.'),
            findsOneWidget,
          );
        }
      },
    );
  }
  for (final failure in [false, true]) {
    testWidgets(
      'profile email send preserves identity and draft (failure=$failure)',
      (tester) async {
        final auth = ProfileScreenAuthFake()..failDelivery = failure;
        final router = GoRouter(
          initialLocation: '/profile-setup',
          routes: [
            GoRoute(
              path: '/profile-setup',
              builder: (context, state) =>
                  ProfileSetupScreen(authService: auth, emailOtpEnabled: true),
            ),
            GoRoute(
              path: '/otp',
              builder: (context, state) => Scaffold(
                body: Text(
                  '${state.uri.queryParameters['purpose']}:${state.uri.queryParameters['challengeId']}',
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(theme: AppTheme.light, routerConfig: router),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(0), 'Ajay');
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'AJAY@example.com',
        );
        await tester.tap(find.text('Send OTP to email'));
        await tester.pumpAndSettle();
        expect(auth.savedName, 'Ajay');
        expect(auth.savedEmail, 'ajay@example.com');
        if (failure) {
          expect(find.text('Email could not be sent.'), findsOneWidget);
          expect(find.text('AJAY@example.com'), findsOneWidget);
          expect(find.text('Send OTP to email'), findsOneWidget);
        } else {
          expect(
            find.text('profile-email:bound-profile-challenge'),
            findsOneWidget,
          );
        }
      },
    );
  }
  test(
    'profile OTP verifies email without replacing the phone session',
    () async {
      final user = PhoneProfileUserFake();
      final auth = EmailAuthFake()..activeUser = user;
      final functions = EmailFunctionsFake();
      final service = FirebaseAuthService.forTesting(
        auth: auth,
        functions: functions,
      );
      service.savePendingProfile(name: 'Ajay', email: 'ajay@example.com');
      final challenge = await service.requestProfileEmailOtp(
        ' AJAY@example.com ',
      );
      final result = await service.verifyProfileEmailOtp(
        email: 'ajay@example.com',
        code: '123456',
        challengeId: challenge,
      );
      expect(result.route, '/roles');
      expect(auth.currentUser?.uid, 'phone-user');
      expect(auth.signedInTokens, isEmpty);
      expect(user.tokenRefreshes, 1);
      expect(functions.calls.map((call) => call.name), [
        'requestProfileEmailOtp',
        'verifyProfileEmailOtp',
      ]);
      expect(functions.calls.first.data, {'email': 'ajay@example.com'});
      await expectLater(
        service.verifyProfileEmailOtp(
          email: 'ajay@example.com',
          code: '123456',
          challengeId: challenge,
        ),
        throwsA(isA<FirebaseAuthFailure>()),
      );
    },
  );

  test(
    'profile OTP rejects a different session before contacting the server',
    () async {
      final auth = EmailAuthFake()..activeUser = PhoneProfileUserFake();
      final functions = EmailFunctionsFake();
      final service = FirebaseAuthService.forTesting(
        auth: auth,
        functions: functions,
      );
      final challenge = await service.requestProfileEmailOtp(
        'ajay@example.com',
      );
      auth.activeUser = PhoneProfileUserFake(userUid: 'other-user');
      await expectLater(
        service.verifyProfileEmailOtp(
          email: 'ajay@example.com',
          code: '123456',
          challengeId: challenge,
        ),
        throwsA(isA<FirebaseAuthFailure>()),
      );
      expect(functions.calls.length, 1);
      expect(auth.signedInTokens, isEmpty);
    },
  );

  test('profile OTP rejects a response for another UID', () async {
    final user = PhoneProfileUserFake();
    final auth = EmailAuthFake()..activeUser = user;
    final functions = EmailFunctionsFake()..responseUid = 'other-user';
    final service = FirebaseAuthService.forTesting(
      auth: auth,
      functions: functions,
    );
    final challenge = await service.requestProfileEmailOtp('ajay@example.com');
    await expectLater(
      service.verifyProfileEmailOtp(
        email: 'ajay@example.com',
        code: '123456',
        challengeId: challenge,
      ),
      throwsA(isA<FirebaseAuthFailure>()),
    );
    expect(user.verified, false);
    expect(auth.signedInTokens, isEmpty);
  });

  test(
    'account email edit refreshes only the same UID with its verified server session',
    () async {
      final user = PhoneProfileUserFake();
      final auth = EmailAuthFake()
        ..activeUser = user
        ..tokenUser = user;
      final functions = EmailFunctionsFake()
        ..responseOverride = (name, data) async =>
            name == 'requestAccountEmailOtp'
            ? {'challengeId': 'account-challenge'}
            : {
                'uid': 'phone-user',
                'email': data['email'],
                'verified': true,
                'customToken': 'same-uid-token',
              };
      final service = FirebaseAuthService.forTesting(
        auth: auth,
        functions: functions,
      );
      final challenge = await service.requestAccountEmailOtp(
        'ajay@example.com',
      );
      await expectLater(
        service.verifyProfileEmailOtp(
          email: 'ajay@example.com',
          code: '123456',
          challengeId: challenge,
        ),
        throwsA(isA<FirebaseAuthFailure>()),
      );
      await service.verifyAccountEmailOtp(
        email: 'ajay@example.com',
        code: '123456',
        challengeId: challenge,
      );
      expect(auth.currentUser?.uid, 'phone-user');
      expect(auth.signedInTokens, ['same-uid-token']);
      expect(functions.calls.map((call) => call.name), [
        'requestAccountEmailOtp',
        'verifyAccountEmailOtp',
      ]);
    },
  );

  test(
    'out-of-order profile email requests never replace the newest challenge',
    () async {
      final late = Completer<Map<String, dynamic>>();
      final auth = EmailAuthFake()..activeUser = PhoneProfileUserFake();
      final functions = EmailFunctionsFake()
        ..responseOverride = (name, data) async {
          if (name == 'requestProfileEmailOtp') {
            return data['email'] == 'old@example.com'
                ? late.future
                : {'challengeId': 'newest'};
          }
          return {
            'uid': 'phone-user',
            'email': data['email'],
            'verified': true,
          };
        };
      final service = FirebaseAuthService.forTesting(
        auth: auth,
        functions: functions,
      );
      final old = service.requestProfileEmailOtp('old@example.com');
      final oldFailure = expectLater(old, throwsA(isA<FirebaseAuthFailure>()));
      final challenge = await service.requestProfileEmailOtp(
        'ajay@example.com',
      );
      late.complete({'challengeId': 'stale'});
      await oldFailure;
      await service.verifyProfileEmailOtp(
        email: 'ajay@example.com',
        code: '123456',
        challengeId: challenge,
      );
      expect(auth.currentUser?.uid, 'phone-user');
    },
  );

  test(
    'late email verification cannot refresh a newly changed session',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final auth = EmailAuthFake()..activeUser = PhoneProfileUserFake();
      final functions = EmailFunctionsFake()
        ..responseOverride = (name, data) async =>
            name == 'requestAccountEmailOtp'
            ? {'challengeId': 'account-challenge'}
            : pending.future;
      final service = FirebaseAuthService.forTesting(
        auth: auth,
        functions: functions,
      );
      final challenge = await service.requestAccountEmailOtp(
        'ajay@example.com',
      );
      final result = service.verifyAccountEmailOtp(
        email: 'ajay@example.com',
        code: '123456',
        challengeId: challenge,
      );
      final failure = expectLater(result, throwsA(isA<FirebaseAuthFailure>()));
      auth.activeUser = PhoneProfileUserFake(userUid: 'different-user');
      pending.complete({
        'uid': 'phone-user',
        'email': 'ajay@example.com',
        'verified': true,
        'customToken': 'old-session',
      });
      await failure;
      expect(auth.signedInTokens, isEmpty);
      expect(auth.currentUser?.uid, 'different-user');
    },
  );

  test('role selection cannot bypass email verification', () async {
    final auth = EmailAuthFake()..activeUser = PhoneProfileUserFake();
    final service = FirebaseAuthService.forTesting(auth: auth);
    service.savePendingProfile(name: 'Ajay', email: 'ajay@example.com');
    await expectLater(
      service.createProfile('broker'),
      throwsA(isA<FirebaseAuthFailure>()),
    );
    await expectLater(
      service.createProfile('admin'),
      throwsA(isA<FirebaseAuthFailure>()),
    );
  });

  test(
    'email request and verification sign into Firebase with the server token',
    () async {
      final auth = EmailAuthFake();
      final functions = EmailFunctionsFake();
      final service = FirebaseAuthService.forTesting(
        auth: auth,
        functions: functions,
      );
      final challenge = await service.requestEmailOtp(' AJAY@example.com ');
      expect(functions.calls.single.data, {'email': 'ajay@example.com'});
      expect(auth.signedInTokens, isEmpty);
      final result = await service.verifyEmailOtp(
        email: 'ajay@example.com',
        code: '123456',
        challengeId: challenge,
      );
      expect(functions.calls.last.data, {
        'email': 'ajay@example.com',
        'code': '123456',
        'challengeId': challenge,
      });
      expect(auth.signedInTokens, ['verified-email-token']);
      expect(result.route, '/profile-setup');
      await expectLater(
        service.verifyEmailOtp(
          email: 'ajay@example.com',
          code: '123456',
          challengeId: challenge,
        ),
        throwsA(isA<FirebaseAuthFailure>()),
      );
    },
  );

  test('email delivery failure is surfaced without signing in', () async {
    final auth = EmailAuthFake();
    final functions = EmailFunctionsFake()..deliveryFails = true;
    final service = FirebaseAuthService.forTesting(
      auth: auth,
      functions: functions,
    );
    await expectLater(
      service.requestEmailOtp('ajay@example.com'),
      throwsA(isA<FirebaseAuthFailure>()),
    );
    expect(auth.signedInTokens, isEmpty);
  });

  test(
    'resend rejects the old email challenge before calling verification',
    () async {
      final auth = EmailAuthFake();
      final functions = EmailFunctionsFake();
      final service = FirebaseAuthService.forTesting(
        auth: auth,
        functions: functions,
      );
      final previous = await service.requestEmailOtp('ajay@example.com');
      functions.challengeId = 'replacement-challenge';
      await service.requestEmailOtp('ajay@example.com');
      await expectLater(
        service.verifyEmailOtp(
          email: 'ajay@example.com',
          code: '123456',
          challengeId: previous,
        ),
        throwsA(isA<FirebaseAuthFailure>()),
      );
      expect(
        functions.calls.map((call) => call.name),
        everyElement('requestEmailOtp'),
      );
      expect(auth.signedInTokens, isEmpty);
    },
  );
}
