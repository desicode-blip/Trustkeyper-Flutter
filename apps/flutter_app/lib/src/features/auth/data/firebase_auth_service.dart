import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'auth_capabilities.dart';
import 'firebase_session_preferences.dart';

String firebaseAuthErrorMessage({required String code, String? message}) {
  final normalizedMessage = (message ?? '').toUpperCase();
  if (code == 'billing-not-enabled' ||
      normalizedMessage.contains('BILLING_NOT_ENABLED')) {
    return 'SMS OTP is unavailable because Firebase phone billing is not enabled. '
        'Use a configured test number for internal testing or ask the project owner to enable billing.';
  }

  return switch (code) {
    'invalid-phone-number' => 'Enter a valid mobile number.',
    'invalid-verification-code' => 'That OTP is not correct. Try again.',
    'session-expired' => 'That OTP expired. Request a new one.',
    'too-many-requests' => 'Too many attempts. Try again after 15 minutes.',
    'network-request-failed' => 'No internet connection. Try again.',
    'quota-exceeded' => 'OTP service is temporarily unavailable.',
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'The email or password is incorrect.',
    'email-already-in-use' =>
      'An account already uses this email. Log in instead.',
    'credential-already-in-use' || 'account-exists-with-different-credential' =>
      'This phone belongs to another account. Log in to that account or contact support. Your accounts have not been merged.',
    'weak-password' => 'Use a password with at least 8 characters.',
    'invalid-email' => 'Enter a valid email address.',
    'app-not-authorized' =>
      'This app build is not authorized for phone login. Update the Firebase signing fingerprints.',
    'invalid-app-credential' || 'missing-client-identifier' =>
      'Google could not verify this app build. Update the app or try again on mobile data.',
    'captcha-check-failed' =>
      'Google could not verify this request. Close the app and try again.',
    'operation-not-allowed' =>
      'This sign-in method is disabled in Firebase Authentication.',
    'internal-error' =>
      'Firebase could not complete this request. Try again shortly.',
    _ => message ?? 'Could not sign you in. Try again.',
  };
}

class AuthResult {
  const AuthResult({required this.route, this.isNewUser = false});

  final String route;
  final bool isNewUser;
}

class FirebaseAuthService {
  FirebaseAuthService._()
    : _auth = FirebaseAuth.instance,
      _functionsOverride = null;

  FirebaseAuthService.forTesting({
    required FirebaseAuth auth,
    FirebaseFunctions? functions,
  }) : _auth = auth,
       _functionsOverride = functions;

  static final instance = FirebaseAuthService._();

  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'asia-south1');
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  String? _verificationId;
  int? _resendToken;
  int _phoneRequestId = 0;
  String? _phoneLinkUid;
  String? _pendingName;
  String? _pendingEmail;
  String? _emailChallengeId;
  String? _emailChallengeAddress;
  int _emailRequestId = 0;
  String? _profileEmailChallengeId;
  String? _profileEmailChallengeAddress;
  String? _profileEmailChallengeUid;
  String? _profileEmailChallengePurpose;
  int _profileEmailRequestId = 0;

  User? get currentUser => _auth.currentUser;
  String? get pendingName => _pendingName;
  String? get pendingEmail => _pendingEmail;

  Future<void> configureSessionPersistence({required bool keepLoggedIn}) async {
    try {
      await FirebaseSessionPreferences(
        auth: _auth,
      ).configure(keepLoggedIn: keepLoggedIn);
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(_friendlyMessage(error));
    } catch (error, stack) {
      debugPrint(
        'Login preference failure: ${error.runtimeType}\n${stack.toString().split('\n').take(5).join('\n')}',
      );
      throw const FirebaseAuthFailure(
        'Could not save your login preference. Try again.',
      );
    }
  }

  Future<String> requestProfileEmailOtp(String email) =>
      _requestBoundEmailOtp(email, 'profile');

  Future<String> requestAccountEmailOtp(String email) =>
      _requestBoundEmailOtp(email, 'account');

  Future<String> _requestBoundEmailOtp(String email, String purpose) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      throw const FirebaseAuthFailure('Please log in with your phone again.');
    }
    final address = email.trim().toLowerCase();
    _clearProfileEmailChallenge();
    final requestId = _profileEmailRequestId;
    try {
      final response = await _functions
          .httpsCallable(
            purpose == 'account'
                ? 'requestAccountEmailOtp'
                : 'requestProfileEmailOtp',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call<Map<String, dynamic>>({'email': address});
      final challenge = response.data['challengeId'];
      if (currentUser?.uid != uid || requestId != _profileEmailRequestId) {
        throw const FirebaseAuthFailure('Your login changed. Log in again.');
      }
      if (challenge is! String || challenge.isEmpty) {
        throw const FirebaseAuthFailure(
          'The email code could not be sent. Try again.',
        );
      }
      _profileEmailChallengeId = challenge;
      _profileEmailChallengeAddress = address;
      _profileEmailChallengeUid = uid;
      _profileEmailChallengePurpose = purpose;
      return challenge;
    } on FirebaseFunctionsException catch (error) {
      throw FirebaseAuthFailure(_emailOtpError(error));
    }
  }

  Future<AuthResult> verifyProfileEmailOtp({
    required String email,
    required String code,
    required String challengeId,
  }) => _verifyBoundEmailOtp(
    email: email,
    code: code,
    challengeId: challengeId,
    purpose: 'profile',
  );

  Future<AuthResult> verifyAccountEmailOtp({
    required String email,
    required String code,
    required String challengeId,
  }) => _verifyBoundEmailOtp(
    email: email,
    code: code,
    challengeId: challengeId,
    purpose: 'account',
  );

  Future<AuthResult> _verifyBoundEmailOtp({
    required String email,
    required String code,
    required String challengeId,
    required String purpose,
  }) async {
    final uid = currentUser?.uid;
    final address = email.trim().toLowerCase();
    if (uid == null ||
        uid != _profileEmailChallengeUid ||
        purpose != _profileEmailChallengePurpose ||
        challengeId != _profileEmailChallengeId ||
        address != _profileEmailChallengeAddress) {
      throw const FirebaseAuthFailure('Request a new email code to continue.');
    }
    final requestId = _profileEmailRequestId;
    try {
      final response = await _functions
          .httpsCallable(
            purpose == 'account'
                ? 'verifyAccountEmailOtp'
                : 'verifyProfileEmailOtp',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call<Map<String, dynamic>>({
            'email': address,
            'code': code,
            'challengeId': challengeId,
          });
      if (currentUser?.uid != uid ||
          requestId != _profileEmailRequestId ||
          response.data['uid'] != uid ||
          response.data['email'] != address ||
          response.data['verified'] != true) {
        throw const FirebaseAuthFailure(
          'Email verification could not be confirmed. Log in again.',
        );
      }
      if (purpose == 'account') {
        final token = response.data['customToken'];
        if (token is! String || token.isEmpty) {
          throw const FirebaseAuthFailure(
            'Your new email session could not be confirmed. Log in again.',
          );
        }
        final session = await _auth.signInWithCustomToken(token);
        if (currentUser?.uid != uid ||
            session.user?.uid != uid ||
            requestId != _profileEmailRequestId) {
          throw const FirebaseAuthFailure('Your login changed. Log in again.');
        }
      }
      await currentUser!.reload();
      final refreshed = currentUser;
      if (refreshed?.uid != uid ||
          requestId != _profileEmailRequestId ||
          refreshed?.email?.toLowerCase() != address ||
          refreshed?.emailVerified != true) {
        throw const FirebaseAuthFailure(
          'Email verification could not be confirmed. Try again.',
        );
      }
      await refreshed!.getIdToken(true);
      if (currentUser?.uid != uid || requestId != _profileEmailRequestId) {
        throw const FirebaseAuthFailure('Your login changed. Log in again.');
      }
      _clearProfileEmailChallenge();
      return AuthResult(
        route: _pendingEmail == address && _pendingName != null
            ? '/roles'
            : '/profile-setup',
      );
    } on FirebaseFunctionsException catch (error) {
      throw FirebaseAuthFailure(_emailOtpError(error));
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(_friendlyMessage(error));
    }
  }

  void _clearProfileEmailChallenge() {
    _profileEmailRequestId++;
    _profileEmailChallengeId = null;
    _profileEmailChallengeAddress = null;
    _profileEmailChallengeUid = null;
    _profileEmailChallengePurpose = null;
  }

  Future<String> requestEmailOtp(String email) async {
    final address = email.trim().toLowerCase();
    final requestId = ++_emailRequestId;
    final uid = currentUser?.uid;
    _emailChallengeId = null;
    _emailChallengeAddress = null;
    try {
      final response = await _functions
          .httpsCallable(
            'requestEmailOtp',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call<Map<String, dynamic>>({'email': address});
      final challengeId = response.data['challengeId'];
      if (requestId != _emailRequestId || currentUser?.uid != uid) {
        throw const FirebaseAuthFailure(
          'Your login changed. Request a new code.',
        );
      }
      if (challengeId is! String || challengeId.isEmpty) {
        throw const FirebaseAuthFailure(
          'The email code could not be sent. Try again.',
        );
      }
      _emailChallengeId = challengeId;
      _emailChallengeAddress = address;
      return challengeId;
    } on FirebaseFunctionsException catch (error) {
      throw FirebaseAuthFailure(_emailOtpError(error));
    } catch (error, stack) {
      if (error is FirebaseAuthFailure) rethrow;
      debugPrint(
        'Email request failure: ${error.runtimeType}\n${stack.toString().split('\n').take(5).join('\n')}',
      );
      throw const FirebaseAuthFailure(
        'Email request could not start. Try again.',
      );
    }
  }

  Future<AuthResult> verifyEmailOtp({
    required String email,
    required String code,
    required String challengeId,
  }) async {
    final address = email.trim().toLowerCase();
    if (_emailChallengeId != challengeId || _emailChallengeAddress != address) {
      throw const FirebaseAuthFailure('Request a new email code to continue.');
    }
    final requestId = _emailRequestId;
    final phoneRequestId = _phoneRequestId;
    final uid = currentUser?.uid;
    try {
      final response = await _functions
          .httpsCallable(
            'verifyEmailOtp',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call<Map<String, dynamic>>({
            'email': address,
            'code': code,
            'challengeId': challengeId,
          });
      final token = response.data['customToken'];
      if (requestId != _emailRequestId ||
          phoneRequestId != _phoneRequestId ||
          currentUser?.uid != uid) {
        throw const FirebaseAuthFailure(
          'Your login changed. Request a new code.',
        );
      }
      if (token is! String || token.isEmpty) {
        throw const FirebaseAuthFailure(
          'Email verification could not be completed. Request a new code.',
        );
      }
      final result = await _auth.signInWithCustomToken(token);
      _emailChallengeId = null;
      _emailChallengeAddress = null;
      return AuthResult(route: await _routeAfterSignIn(result));
    } on FirebaseFunctionsException catch (error) {
      throw FirebaseAuthFailure(_emailOtpError(error));
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(_friendlyMessage(error));
    }
  }

  String _emailOtpError(
    FirebaseFunctionsException error,
  ) => switch (error.code) {
    'not-found' =>
      'Email sign-in is not available yet. Please use phone login or contact support.',
    'deadline-exceeded' =>
      'The request timed out. Check your inbox before requesting a new code.',
    'internal' =>
      'Email sign-in could not be completed. Request a new code and try again.',
    _ =>
      error.message ?? 'Email sign-in is temporarily unavailable. Try again.',
  };

  Future<String> landingRoute() async {
    final user = _auth.currentUser;
    if (user == null) return '/onboarding';
    if (_needsEmailVerification(user)) return _emailVerificationRoute(user);
    return _routeForUser(user.uid);
  }

  Future<void> requestPhoneOtp({
    required String phoneNumber,
    required void Function() onCodeSent,
    required void Function(String message) onError,
    required void Function(String route) onAutoVerified,
    bool resend = false,
    bool linkToCurrentUser = false,
  }) async {
    final linkingUser = linkToCurrentUser ? currentUser : null;
    if (linkToCurrentUser &&
        (linkingUser == null ||
            linkingUser.emailVerified != true ||
            linkingUser.email == null ||
            linkingUser.phoneNumber != null)) {
      onError('Log in with your verified email before adding a phone.');
      return;
    }
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final normalized = digits.length == 10 ? '+91$digits' : '+$digits';
    final requestId = ++_phoneRequestId;
    _verificationId = null;
    _phoneLinkUid = linkingUser?.uid;
    if (!resend) _resendToken = null;
    final outcome = Completer<void>();
    var resolved = false;
    var automaticVerificationStarted = false;

    bool isActive() => requestId == _phoneRequestId && !resolved;

    void resolve(void Function() callback) {
      if (resolved) return;
      resolved = true;
      if (requestId == _phoneRequestId) callback();
      if (!outcome.isCompleted) outcome.complete();
    }

    void fail(Object error) {
      resolve(() => onError(_messageForError(error)));
    }

    try {
      final request = _auth.verifyPhoneNumber(
        phoneNumber: normalized,
        timeout: const Duration(seconds: 30),
        forceResendingToken: resend ? _resendToken : null,
        verificationCompleted: (credential) async {
          if (!isActive() || automaticVerificationStarted) return;
          automaticVerificationStarted = true;
          try {
            final result = await _completePhoneCredential(
              credential,
              linkUid: linkingUser?.uid,
            ).timeout(const Duration(seconds: 20));
            final route = linkingUser != null
                ? '/profile-setup'
                : await _routeAfterSignIn(
                    result,
                  ).timeout(const Duration(seconds: 20));
            resolve(() => onAutoVerified(route));
          } catch (error) {
            fail(error);
          }
        },
        verificationFailed: fail,
        codeSent: (verificationId, resendToken) {
          if (!isActive()) return;
          _verificationId = verificationId;
          _resendToken = resendToken;
          if (automaticVerificationStarted) return;
          resolve(onCodeSent);
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (!isActive() || automaticVerificationStarted) return;
          fail(
            TimeoutException('Firebase did not return an OTP result in time.'),
          );
        },
      );
      unawaited(
        request.catchError((Object error, StackTrace stackTrace) {
          fail(error);
        }),
      );
    } catch (error) {
      fail(error);
    }

    try {
      await outcome.future.timeout(const Duration(seconds: 35));
    } on TimeoutException catch (error) {
      fail(error);
    }
  }

  Future<UserCredential> _completePhoneCredential(
    PhoneAuthCredential credential, {
    String? linkUid,
  }) async {
    if (linkUid == null) return _auth.signInWithCredential(credential);
    final user = currentUser;
    if (user?.uid != linkUid || user?.emailVerified != true) {
      throw const FirebaseAuthFailure(
        'Your login changed. Log in with your email and request a new phone code.',
      );
    }
    final result = await user!.linkWithCredential(credential);
    if (currentUser?.uid != linkUid || result.user?.uid != linkUid) {
      throw const FirebaseAuthFailure(
        'Phone verification could not be confirmed.',
      );
    }
    await user.reload();
    if (currentUser?.uid != linkUid || currentUser?.phoneNumber == null) {
      throw const FirebaseAuthFailure(
        'Phone verification could not be confirmed.',
      );
    }
    await currentUser!.getIdToken(true);
    return result;
  }

  Future<AuthResult> verifyPhoneOtp(
    String code, {
    bool linkToCurrentUser = false,
  }) async {
    final verificationId = _verificationId;
    if (verificationId == null) {
      throw const FirebaseAuthFailure('Please request a new OTP.');
    }

    try {
      if (linkToCurrentUser != (_phoneLinkUid != null)) {
        throw const FirebaseAuthFailure(
          'Request a new phone code to continue.',
        );
      }
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );
      final result = await _completePhoneCredential(
        credential,
        linkUid: _phoneLinkUid,
      );
      final route = linkToCurrentUser
          ? '/profile-setup'
          : await _routeAfterSignIn(result);
      _verificationId = null;
      _phoneLinkUid = null;
      return AuthResult(
        route: route,
        isNewUser: result.additionalUserInfo?.isNewUser ?? false,
      );
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(_friendlyMessage(error));
    }
  }

  Future<AuthResult> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      return AuthResult(route: await _routeAfterSignIn(result));
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(_friendlyMessage(error));
    }
  }

  Future<AuthResult> createAccountWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = result.user;
      if (user == null) {
        throw const FirebaseAuthFailure(
          'The account was created, but Firebase did not return the user.',
        );
      }
      await user.sendEmailVerification();
      return AuthResult(route: _emailVerificationRoute(user), isNewUser: true);
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(_friendlyMessage(error));
    }
  }

  Future<void> resendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null || !_isPasswordUser(user)) {
      throw const FirebaseAuthFailure(
        'Log in with your email and password to resend verification.',
      );
    }
    if (user.emailVerified) return;

    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(_friendlyMessage(error));
    }
  }

  Future<AuthResult> confirmEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null || !_isPasswordUser(user)) {
      throw const FirebaseAuthFailure(
        'Log in with your email and password to continue.',
      );
    }

    try {
      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) {
        throw const FirebaseAuthFailure('Log in again to continue.');
      }
      if (!refreshedUser.emailVerified) {
        throw const FirebaseAuthFailure(
          'Your email is not verified yet. Open the link in your inbox, then try again.',
        );
      }
      return AuthResult(route: await _routeForUser(refreshedUser.uid));
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(_friendlyMessage(error));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(_friendlyMessage(error));
    }
  }

  void savePendingProfile({required String name, required String email}) {
    _pendingName = name.trim();
    _pendingEmail = email.trim().toLowerCase();
  }

  Future<String> createProfile(String role) async {
    final user = _auth.currentUser;
    if (user == null) throw const FirebaseAuthFailure('Please log in again.');
    if (_pendingName == null || _pendingEmail == null) {
      throw const FirebaseAuthFailure(
        'Please complete your name and email first.',
      );
    }

    final displayName = _pendingName!;
    final email = _pendingEmail!;
    if (user.emailVerified && user.phoneNumber == null) {
      throw const FirebaseAuthFailure(
        'Verify your mobile number on your profile before choosing a role.',
      );
    }
    if (!const ['broker', 'owner', 'tenant'].contains(role)) {
      throw const FirebaseAuthFailure('Choose a valid role.');
    }
    final identityError = profileIdentityError(
      email: email,
      verifiedEmail: user.email,
      emailVerified: user.emailVerified,
      phone: user.phoneNumber,
    );
    if (identityError != null) {
      throw FirebaseAuthFailure(identityError);
    }
    await user.updateDisplayName(displayName);
    await user.reload();
    final reference = _firestore.collection('users').doc(user.uid);
    final existing = await reference.get();
    if (existing.exists) {
      await reference.set({
        'displayName': displayName,
        'email': email,
        'phone': user.phoneNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await reference.set({
        'displayName': displayName,
        'email': email,
        'phone': user.phoneNumber,
        'roles': [role],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    _pendingName = null;
    _pendingEmail = null;
    return _routeForUser(user.uid);
  }

  Future<void> signOut() async {
    _emailRequestId++;
    _pendingName = null;
    _pendingEmail = null;
    _emailChallengeId = null;
    _emailChallengeAddress = null;
    _clearProfileEmailChallenge();
    _verificationId = null;
    _phoneLinkUid = null;
    _resendToken = null;
    _phoneRequestId++;
    if (!kIsWeb &&
        [
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      try {
        final uid = _auth.currentUser?.uid;
        final token = await FirebaseMessaging.instance.getToken().timeout(
          const Duration(seconds: 5),
        );
        if (uid != null && token != null && _auth.currentUser?.uid == uid) {
          final id = sha256.convert(utf8.encode(token)).toString();
          await _firestore
              .doc('users/$uid/pushDevices/$id')
              .delete()
              .timeout(const Duration(seconds: 5));
        }
      } catch (_) {}
      try {
        await FirebaseMessaging.instance.deleteToken().timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {}
    }
    await _auth.signOut();
  }

  Future<String> _routeAfterSignIn(UserCredential result) async {
    final user = result.user;
    if (user != null && _needsEmailVerification(user)) {
      return _emailVerificationRoute(user);
    }
    if (result.additionalUserInfo?.isNewUser ?? false) return '/profile-setup';
    return _routeForUser(user!.uid);
  }

  bool _isPasswordUser(User user) =>
      user.providerData.any((provider) => provider.providerId == 'password');

  bool _needsEmailVerification(User user) =>
      _isPasswordUser(user) && !user.emailVerified;

  String _emailVerificationRoute(User user) => Uri(
    path: '/verify-email',
    queryParameters: {'email': user.email ?? ''},
  ).toString();

  Future<String> _routeForUser(String uid) async {
    final reference = _firestore.collection('users').doc(uid);
    final snapshot = await reference.get();
    if (!snapshot.exists) return '/profile-setup';
    final data = Map<String, dynamic>.from(
      snapshot.data() ?? const <String, dynamic>{},
    );
    final authDisplayName = _auth.currentUser?.displayName?.trim();
    final storedDisplayName = (data['displayName'] as String?)?.trim();
    if (authDisplayName != null &&
        authDisplayName.isNotEmpty &&
        authDisplayName != storedDisplayName) {
      await reference.set({
        'displayName': authDisplayName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      data['displayName'] = authDisplayName;
    }
    if (data['paused'] == true) return '/account-paused';
    final roles = List<String>.from(data['roles'] as List? ?? const []);
    if (roles.contains('admin')) return '/admin';
    if (_auth.currentUser?.emailVerified == true &&
        _auth.currentUser?.phoneNumber == null) {
      return '/profile-setup';
    }
    if (roles
            .where((role) => ['broker', 'owner', 'tenant'].contains(role))
            .length >
        1) {
      return '/switch-role';
    }
    if (roles.contains('broker')) {
      final approved = data['approvalStatus'] == 'approved';
      return approved ? '/broker' : '/broker/approval';
    }
    if (roles.contains('owner')) return '/owner';
    if (roles.contains('tenant')) return '/tenant';
    return '/roles';
  }

  String _friendlyMessage(FirebaseAuthException error) =>
      firebaseAuthErrorMessage(code: error.code, message: error.message);

  String _messageForError(Object error) {
    if (error is FirebaseAuthFailure) return error.message;
    if (error is FirebaseAuthException) return _friendlyMessage(error);
    if (error is TimeoutException) {
      return 'OTP request timed out. Check your internet and tap Continue again.';
    }
    return 'Could not start phone verification. Check your internet and try again.';
  }
}

class FirebaseAuthFailure implements Exception {
  const FirebaseAuthFailure(this.message);
  final String message;
}
