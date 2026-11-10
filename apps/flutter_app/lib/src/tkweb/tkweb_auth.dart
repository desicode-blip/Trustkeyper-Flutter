import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/auth/presentation/approved_auth_widgets.dart';
import '../features/auth/presentation/login_method.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import '../tk2/tk2_cloud.dart';
import 'tkweb_session.dart';

/// Sign up on the web: the main app's login screen (hero with logo, name,
/// Phone/Email switch) → 6-digit code. Tenants use phone; owners can pick email.
class TkwSignUp extends StatefulWidget {
  const TkwSignUp({required this.allowEmail, required this.subtitle, required this.onDone, super.key});

  /// Owners may sign up with email; tenants with phone (the broker calls them).
  final bool allowEmail;
  final String subtitle;
  final VoidCallback onDone;

  @override
  State<TkwSignUp> createState() => _TkwSignUpState();
}

class _TkwSignUpState extends State<TkwSignUp> {
  final name = TextEditingController();
  final contact = TextEditingController();
  LoginMethod method = LoginMethod.phone;
  String dial = '+91';
  String? nameError;
  String? contactError;

  @override
  void dispose() {
    name.dispose();
    contact.dispose();
    super.dispose();
  }

  bool sending = false;

  Future<void> _next() async {
    final digits = contact.text.replaceAll(RegExp(r'\D'), '');
    final email = contact.text.trim().toLowerCase();
    setState(() {
      nameError = name.text.trim().length < 2 ? 'Type your full name' : null;
      contactError = method == LoginMethod.phone
          ? (PhoneCountry.valid(dial, digits) ? null : (dial == '+91' ? 'Enter a valid 10-digit mobile number' : 'Enter a valid phone number'))
          : (RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(email) ? null : 'Enter a valid email address');
    });
    if (nameError != null || contactError != null) return;
    final destination = method == LoginMethod.phone ? PhoneCountry.format(dial, digits) : email;
    FocusScope.of(context).unfocus();
    if (Tk2Cloud.on) {
      setState(() => sending = true);
      final failed = await Tk2Cloud.sendCode(destination);
      if (!mounted) return;
      setState(() {
        sending = false;
        contactError = failed;
      });
      if (failed != null) return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TkwOtp(
          destination: destination,
          onVerified: () async {
            await TkwSession.instance.signIn(name.text, destination);
            widget.onDone();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keyboard open: the picture folds away so name, number and Get OTP all fit
    // above the keyboard; the button rides on top of it.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ApprovedAuthScaffold(
      showBack: false,
      header: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: typing
            ? Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: ApprovedBackButton(onPressed: () => Navigator.of(context).maybePop()),
                ),
              )
            : ApprovedLoginHero(onBack: () => Navigator.of(context).maybePop()),
      ),
      bodyPadding: EdgeInsets.fromLTRB(24, typing ? 12 : 18, 24, 16),
      footerPadding: EdgeInsets.fromLTRB(24, 12, 24, typing ? 12 : 28),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(label: 'Get OTP', icon: Icons.chevron_right, loading: sending, onPressed: sending ? null : _next),
          if (!typing) ...[const SizedBox(height: 10), const LoginLegalNotice()],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Log in or sign up', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 6),
          Text(
            widget.subtitle,
            style: const TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            onChanged: (_) => setState(() => nameError = null),
            decoration: InputDecoration(labelText: 'Full name', prefixIcon: const Icon(Icons.person_outline), errorText: nameError),
          ),
          const SizedBox(height: 18),
          if (widget.allowEmail) ...[
            AuthMethodSelector(
              selected: method,
              onChanged: (m) => setState(() {
                method = m;
                contact.clear();
                contactError = null;
              }),
            ),
            const SizedBox(height: 18),
          ],
          AuthFieldSwitcher(
            child: method == LoginMethod.phone
                ? ApprovedPhoneField(
                    key: const ValueKey('web-phone'),
                    controller: contact,
                    error: contactError,
                    dialCode: dial,
                    onDialCodeChanged: (c) => setState(() => dial = c),
                  )
                : ApprovedEmailField(key: const ValueKey('web-email'), controller: contact, error: contactError),
          ),
        ],
      ),
    );
  }
}

/// The 6-digit code screen (main app's OTP boxes). With the backend on the
/// code comes by SMS / email (Firebase); in the demo build it is 123456.
/// Also used by the broker app's login.
class TkwOtp extends StatefulWidget {
  const TkwOtp({required this.destination, required this.onVerified, super.key});
  final String destination;
  final Future<void> Function() onVerified;

  static const demoCode = '123456';

  /// Checks the code: null when right, else the red message.
  static Future<String?> check(String code) async {
    if (Tk2Cloud.on) return Tk2Cloud.verifyCode(code);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return code == demoCode ? null : 'That code is not right. Try again.';
  }

  @override
  State<TkwOtp> createState() => _TkwOtpState();
}

class _TkwOtpState extends State<TkwOtp> {
  final code = TextEditingController();
  String? error;
  bool checking = false;
  int wait = 30;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    timer?.cancel();
    wait = 30;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || wait <= 0) return t.cancel();
      setState(() => wait--);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (code.text.length < 6) return setState(() => error = 'Type the 6-digit code');
    setState(() {
      checking = true;
      error = null;
    });
    final wrong = await TkwOtp.check(code.text);
    if (!mounted) return;
    if (wrong != null) {
      setState(() {
        checking = false;
        error = wrong;
      });
      return;
    }
    await widget.onVerified();
  }

  @override
  Widget build(BuildContext context) => ApprovedAuthScaffold(
    onBack: () => Navigator.of(context).maybePop(),
    footer: PrimaryButton(label: 'Verify', icon: Icons.chevron_right, loading: checking, onPressed: checking ? null : _verify),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter the code', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            text: 'We sent a 6-digit code to ',
            children: [
              TextSpan(
                text: widget.destination,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.heading),
              ),
            ],
          ),
          style: const TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.muted),
        ),
        const SizedBox(height: 24),
        ApprovedOtpInput(controller: code, error: error, onComplete: (_) => _verify()),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: wait > 0
                ? null
                : () async {
                    code.clear();
                    _startTimer();
                    final failed = Tk2Cloud.on ? await Tk2Cloud.sendCode(widget.destination) : null;
                    if (!context.mounted) return;
                    if (failed != null) return setState(() => error = failed);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('New code sent')));
                  },
            child: Text(wait > 0 ? 'Send again in 0:${wait.toString().padLeft(2, '0')}' : 'Send code again'),
          ),
        ),
        if (!Tk2Cloud.on) ...[
          const SizedBox(height: 8),
          const OnbBanner('Demo build: the code is 123456. Real SMS and WhatsApp codes come with the backend.', kind: 'wait', icon: Icons.science_outlined),
        ],
      ],
    ),
  );
}
