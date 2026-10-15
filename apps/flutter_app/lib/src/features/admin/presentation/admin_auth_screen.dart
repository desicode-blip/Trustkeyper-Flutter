import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_brand.dart';
import '../../auth/data/firebase_session_preferences.dart';

const _ink = Color(0xFF172231);
const _muted = Color(0xFF5E7087);
const _blue = Color(0xFF3160FF);
const _line = Color(0xFFDCE2E9);
const _canvas = Color(0xFFF6F9FD);
const _red = Color(0xFFB3261E);

class AdminLoginResult {
  const AdminLoginResult({
    this.phoneNumber,
    this.requiresPhoneVerification = false,
  });

  final String? phoneNumber;
  final bool requiresPhoneVerification;
}

abstract interface class AdminAuthGateway {
  Future<AdminLoginResult> signIn(String email, String password);

  Future<void> sendCode();

  Future<void> confirmCode(String code);

  Future<bool> hasAdminAccess();

  Future<void> signOut();
}

class FirebaseAdminAuthGateway implements AdminAuthGateway {
  FirebaseAdminAuthGateway({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String? _phoneNumber;
  String? _expectedUid;
  String? _verificationId;
  ConfirmationResult? _webConfirmation;

  @override
  Future<AdminLoginResult> signIn(String email, String password) async {
    try {
      await FirebaseSessionPreferences(
        auth: _auth,
      ).configure(keepLoggedIn: true);
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = credential.user;
      if (user == null) throw const AdminAuthFailure('Could not sign in.');
      final profile = await _firestore.collection('users').doc(user.uid).get();
      final data = profile.data() ?? const <String, dynamic>{};
      final roles =
          (data['roles'] as List?)?.whereType<String>().toList() ?? const [];
      if (!roles.contains('admin')) {
        await _auth.signOut();
        throw const AdminAuthFailure('This account is not an administrator.');
      }
      if (data['paused'] == true) {
        await _auth.signOut();
        throw const AdminAuthFailure('This administrator account is paused.');
      }
      final phone =
          (data['phone'] ?? user.phoneNumber)?.toString().trim() ?? '';
      final phoneLinked = user.providerData.any(
        (provider) => provider.providerId == 'phone',
      );
      _phoneNumber = phone;
      _expectedUid = user.uid;
      return AdminLoginResult(
        phoneNumber: phone.isEmpty ? null : phone,
        requiresPhoneVerification: phone.isNotEmpty && phoneLinked,
      );
    } on FirebaseAuthException catch (error) {
      throw AdminAuthFailure(_message(error));
    }
  }

  @override
  Future<void> sendCode() async {
    final phone = _phoneNumber;
    if (phone == null) throw const AdminAuthFailure('Log in again.');
    try {
      if (kIsWeb) {
        _webConfirmation = await _auth.signInWithPhoneNumber(phone);
        return;
      }
      final result = Completer<void>();
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 45),
        verificationCompleted: (_) {
          if (!result.isCompleted) result.complete();
        },
        verificationFailed: (error) {
          if (!result.isCompleted) {
            result.completeError(AdminAuthFailure(_message(error)));
          }
        },
        codeSent: (verificationId, _) {
          _verificationId = verificationId;
          if (!result.isCompleted) result.complete();
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
          if (!result.isCompleted) result.complete();
        },
      );
      await result.future.timeout(const Duration(seconds: 50));
    } on FirebaseAuthException catch (error) {
      throw AdminAuthFailure(_message(error));
    } on TimeoutException {
      throw const AdminAuthFailure('The code request timed out. Try again.');
    }
  }

  @override
  Future<void> confirmCode(String code) async {
    try {
      UserCredential result;
      if (kIsWeb) {
        final confirmation = _webConfirmation;
        if (confirmation == null) {
          throw const AdminAuthFailure('Request a new code.');
        }
        result = await confirmation.confirm(code);
      } else {
        final verificationId = _verificationId;
        final currentUser = _auth.currentUser;
        if (verificationId == null || currentUser == null) {
          throw const AdminAuthFailure('Request a new code.');
        }
        final credential = PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: code,
        );
        result = await currentUser.reauthenticateWithCredential(credential);
      }
      if (result.user?.uid != _expectedUid || !await hasAdminAccess()) {
        await _auth.signOut();
        throw const AdminAuthFailure(
          'That phone number is not linked to this admin account.',
        );
      }
    } on FirebaseAuthException catch (error) {
      throw AdminAuthFailure(_message(error));
    }
  }

  @override
  Future<bool> hasAdminAccess() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final profile = await _firestore.collection('users').doc(user.uid).get();
    final data = profile.data() ?? const <String, dynamic>{};
    final roles =
        (data['roles'] as List?)?.whereType<String>().toList() ?? const [];
    return roles.contains('admin') && data['paused'] != true;
  }

  @override
  Future<void> signOut() => _auth.signOut();

  String _message(FirebaseAuthException error) {
    if (error.code == 'billing-not-enabled' ||
        (error.message ?? '').toUpperCase().contains('BILLING_NOT_ENABLED')) {
      return 'Admin SMS verification requires Firebase phone billing to be enabled.';
    }
    return switch (error.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'The email or password is incorrect.',
      'too-many-requests' => 'Too many attempts. Try again later.',
      'network-request-failed' => 'No internet connection. Try again.',
      'invalid-verification-code' => 'That code is incorrect.',
      'session-expired' => 'That code expired. Request a new one.',
      'operation-not-allowed' =>
        'Enable Email/Password and Phone in Firebase Authentication.',
      'internal-error' => 'Firebase could not complete sign-in. Try again.',
      _ => error.message ?? 'Could not sign in.',
    };
  }
}

class AdminAuthFailure implements Exception {
  const AdminAuthFailure(this.message);

  final String message;
}

class AdminAccessGate extends StatefulWidget {
  const AdminAccessGate({super.key, this.gateway, required this.child});

  final AdminAuthGateway? gateway;
  final Widget child;

  @override
  State<AdminAccessGate> createState() => _AdminAccessGateState();
}

class _AdminAccessGateState extends State<AdminAccessGate> {
  late final Future<bool> _access =
      (widget.gateway ?? FirebaseAdminAuthGateway()).hasAdminAccess();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _access,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: _canvas,
            child: Center(child: CircularProgressIndicator(color: _blue)),
          );
        }
        if (snapshot.data == true) return widget.child;
        return const AdminLoginScreen();
      },
    );
  }
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key, this.gateway});

  final AdminAuthGateway? gateway;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  late final AdminAuthGateway _gateway =
      widget.gateway ?? FirebaseAdminAuthGateway();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _obscure = true;
  bool _working = false;
  bool _locked = false;
  int _failedAttempts = 0;
  String? _error;
  String? _phone;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: _canvas,
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: _ink,
          displayColor: _ink,
          fontFamily: 'Roboto',
        ),
      ),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, viewport) {
            final wide = viewport.maxWidth >= 760;
            final intro = _intro();
            final form = _phone == null ? _loginForm() : _codeForm();
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: viewport.maxHeight > 48
                      ? viewport.maxHeight - 48
                      : 0,
                ),
                child: Center(
                  child: Container(
                    height: wide ? 560 : null,
                    constraints: const BoxConstraints(maxWidth: 1040),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _line),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x120E2442),
                          blurRadius: 32,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: intro),
                              Expanded(child: form),
                            ],
                          )
                        : Column(children: [intro, form]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _intro() {
    return Container(
      padding: const EdgeInsets.all(42),
      decoration: const BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(17),
          bottomLeft: Radius.circular(17),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const AppBrand(height: 30),
          ),
          const SizedBox(height: 34),
          const Text(
            'Admin panel',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'See and control everything: people, agreements, rent, repairs and photos.',
            style: TextStyle(
              color: Color(0xFFB8C5D6),
              height: 1.55,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 30),
          const Row(
            children: [
              Icon(Icons.lock_outline, color: Color(0xFFB8C5D6), size: 19),
              SizedBox(width: 8),
              Text(
                'Only for TrustKeyper team',
                style: TextStyle(color: Color(0xFFB8C5D6), fontSize: 13.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _loginForm() {
    return Padding(
      padding: const EdgeInsets.all(42),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Log in',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use your TrustKeyper work account.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 28),
          _field(
            controller: _email,
            label: 'Work email',
            hint: 'info@trustkeyper.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          _field(
            controller: _password,
            label: 'Password',
            obscure: _obscure,
            suffix: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _errorBox(_error!),
          ],
          const SizedBox(height: 22),
          _button(
            _locked ? 'Account locked' : 'Log in',
            _locked ? null : _logIn,
          ),
          const SizedBox(height: 14),
          const Center(
            child: Text(
              'Linked admin phone accounts use an extra security code',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeForm() {
    return Padding(
      padding: const EdgeInsets.all(42),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the 6-digit code',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Sent to ${_maskedPhone(_phone ?? '')}',
            style: const TextStyle(color: _muted),
          ),
          const SizedBox(height: 28),
          _field(
            controller: _code,
            label: 'Security code',
            hint: '000000',
            keyboardType: TextInputType.number,
            maxLength: 6,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _errorBox(_error!),
          ],
          const SizedBox(height: 22),
          _button('Verify and open admin', _verify),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _working ? null : _sendAgain,
              child: const Text('Send code again'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffix,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          maxLength: maxLength,
          enabled: !_working,
          decoration: InputDecoration(
            counterText: '',
            hintText: hint,
            suffixIcon: suffix,
            filled: true,
            fillColor: _canvas,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: _line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: _line),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEA),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: _red, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(message, style: const TextStyle(color: _red)),
          ),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: FilledButton(
        onPressed: _working ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _blue,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: _working
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }

  Future<void> _logIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your work email and password.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final result = await _gateway.signIn(_email.text, _password.text);
      if (!result.requiresPhoneVerification) {
        if (mounted) context.go('/admin');
        return;
      }
      await _gateway.sendCode();
      if (!mounted) return;
      setState(() => _phone = result.phoneNumber);
    } on AdminAuthFailure catch (error) {
      _failedAttempts += 1;
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _locked = _failedAttempts >= 5;
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.length != 6) {
      setState(() => _error = 'Enter all 6 digits.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _gateway.confirmCode(_code.text);
      if (mounted) context.go('/admin');
    } on AdminAuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _sendAgain() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _gateway.sendCode();
    } on AdminAuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

String _maskedPhone(String phone) {
  if (phone.length <= 4) return phone;
  return '${phone.substring(0, phone.length - 4).replaceAll(RegExp(r'\d'), '•')}${phone.substring(phone.length - 4)}';
}
