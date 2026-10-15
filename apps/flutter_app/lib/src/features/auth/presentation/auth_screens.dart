import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_brand.dart';
import '../../../core/widgets/keyboard_safe_scaffold.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/firebase_auth_service.dart';
import '../data/account_roles.dart';
import '../data/auth_capabilities.dart';
import 'approved_auth_widgets.dart';
import 'login_method.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.authService});

  final FirebaseAuthService? authService;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? navigationTimer;
  bool checking = false;
  String? startupError;

  @override
  void initState() {
    super.initState();
    navigationTimer = Timer(const Duration(milliseconds: 2500), _continue);
  }

  Future<void> _continue() async {
    if (checking || !mounted) return;
    setState(() {
      checking = true;
      startupError = null;
    });
    try {
      final route = await (widget.authService ?? FirebaseAuthService.instance)
          .landingRoute()
          .timeout(const Duration(seconds: 20));
      if (mounted) context.go(route);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        checking = false;
        startupError =
            'Could not check your login. Check your connection and try again.';
      });
    }
  }

  @override
  void dispose() {
    navigationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(32),
                        ),
                        child: const SizedBox(width: 92, child: AppBrand()),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'TrustKeyper',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.32,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Your home,\nin trusted hands.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xEBFFFFFF),
                          fontSize: 18,
                          height: 26 / 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 70,
                child: Center(
                  child: startupError != null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                startupError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _continue,
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                            backgroundColor: Color(0x59FFFFFF),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const autoAdvance = Duration(seconds: 4);

  final pageController = PageController();
  Timer? autoTimer;
  int selectedPage = 0;

  static const pages = [
    (
      icon: 'welcome-agreement',
      color: AppColors.primaryDark,
      background: AppColors.primarySoft,
      title: 'Paperwork without the stress',
      body: 'Your rent agreement, done from your sofa.',
    ),
    (
      icon: 'welcome-rent',
      color: AppColors.success,
      background: AppColors.successSoft,
      title: 'Rent that never slips',
      body: 'On time, every month. No reminders, no awkward calls.',
    ),
    (
      icon: 'welcome-home',
      color: Color(0xFFD86A10),
      background: Color(0xFFFFF1E3),
      title: 'A home that feels cared for',
      body: 'Every repair seen, approved and handled.',
    ),
    (
      icon: 'welcome-trust',
      color: Color(0xFF7A4DFF),
      background: Color(0xFFF1EAFF),
      title: 'Everyone on the same page',
      body: 'Brokers, owners and tenants. Trust, finally.',
    ),
  ];

  bool get isLast => selectedPage == pages.length - 1;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    autoTimer?.cancel();
    pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    autoTimer?.cancel();
    autoTimer = Timer(autoAdvance, _next);
  }

  void _stopTimer() => autoTimer?.cancel();

  void _next() {
    if (!mounted) return;
    if (isLast) {
      autoTimer?.cancel();
      context.go('/login');
      return;
    }
    pageController.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = pages[selectedPage];
    return ApprovedAuthScaffold(
      showBack: false,
      scrollable: false,
      footerBorder: false,
      header: const Padding(
        padding: EdgeInsets.fromLTRB(24, 18, 24, 0),
        child: Align(alignment: Alignment.centerLeft, child: AppBrand(height: 32)),
      ),
      footer: Row(
        children: [
          TextButton(
            onPressed: () => context.go('/login'),
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text(
              'Skip',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 15,
                height: 18 / 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 148,
            child: PrimaryButton(
              label: isLast ? 'Get started' : 'Next',
              icon: Icons.chevron_right,
              onPressed: () {
                _stopTimer();
                _next();
              },
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              // Pause the 4s timer while a finger is on the image.
              child: Listener(
                onPointerDown: (_) => _stopTimer(),
                onPointerUp: (_) => _startTimer(),
                onPointerCancel: (_) => _startTimer(),
                child: PageView.builder(
                  controller: pageController,
                  itemCount: pages.length,
                  onPageChanged: (index) {
                    setState(() => selectedPage = index);
                    _startTimer();
                  },
                  itemBuilder: (context, index) {
                    final p = pages[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: p.background,
                          borderRadius: BorderRadius.circular(36),
                        ),
                        child: Center(
                          child: FractionallySizedBox(
                            widthFactor: 0.55,
                            child: SvgPicture.asset(
                              'assets/design/${p.icon}.svg',
                              fit: BoxFit.contain,
                              colorFilter: ColorFilter.mode(
                                p.color,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              pages.length,
              (dot) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: dot == selectedPage ? 24 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: dot == selectedPage
                      ? AppColors.primary
                      : AppColors.primaryBorder,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 112,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Column(
                  key: ValueKey(selectedPage),
                  children: [
                    Text(
                      page.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        height: 34 / 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      page.body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 25 / 17,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.authService,
    this.emailOtpEnabled = AuthCapabilities.emailOtpEnabled,
  });

  final FirebaseAuthService? authService;
  final bool emailOtpEnabled;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final identityController = TextEditingController();
  LoginMethod method = LoginMethod.phone;
  bool keepLoggedIn = true;
  bool sending = false;
  String? errorMessage;

  FirebaseAuthService get auth =>
      widget.authService ?? FirebaseAuthService.instance;

  @override
  void dispose() {
    identityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ApprovedAuthScaffold(
      showBack: false,
      header: const ApprovedLoginHero(),
      bodyPadding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: sending ? 'Sending OTP…' : 'Get OTP',
            icon: Icons.chevron_right,
            onPressed:
                sending ||
                    (method == LoginMethod.email && !widget.emailOtpEnabled)
                ? null
                : _continue,
          ),
          const SizedBox(height: 10),
          const DefaultTextStyle(
            style: TextStyle(fontSize: 13.5, color: AppColors.muted),
            child: LoginLegalNotice(),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Log in or sign up',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 18),
          AuthMethodSelector(
            selected: method,
            enabled: !sending,
            onChanged: (value) {
              setState(() {
                method = value;
                identityController.clear();
                errorMessage = null;
              });
            },
          ),
          const SizedBox(height: 18),
          if (method == LoginMethod.phone)
            ApprovedPhoneField(
              controller: identityController,
              enabled: !sending,
              error: errorMessage,
            )
          else
            ApprovedEmailField(
              controller: identityController,
              enabled: !sending,
              error: errorMessage,
            ),
          if (method == LoginMethod.email && !widget.emailOtpEnabled) ...[
            const SizedBox(height: 12),
            const Text(
              'Email OTP is deferred for this test build. Choose Phone to log in.',
            ),
          ],
          const SizedBox(height: 18),
          Semantics(
            checked: keepLoggedIn,
            label: 'Keep me logged in',
            child: InkWell(
              onTap: sending
                  ? null
                  : () => setState(() => keepLoggedIn = !keepLoggedIn),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: keepLoggedIn ? AppColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: keepLoggedIn
                            ? null
                            : Border.all(color: AppColors.border),
                      ),
                      child: keepLoggedIn
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Keep me logged in',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.heading,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _continue() async {
    if (method == LoginMethod.phone) {
      await _requestOtp();
      return;
    }

    final email = identityController.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => errorMessage = 'Enter a valid email address');
      return;
    }

    setState(() {
      sending = true;
      errorMessage = null;
    });
    try {
      await auth.configureSessionPersistence(keepLoggedIn: keepLoggedIn);
      final challengeId = await auth.requestEmailOtp(email);
      if (!mounted) return;
      context.go(
        Uri(
          path: '/otp',
          queryParameters: {
            'destination': email,
            'method': LoginMethod.email.name,
            'challengeId': challengeId,
          },
        ).toString(),
      );
    } on FirebaseAuthFailure catch (error) {
      if (!mounted) return;
      setState(() {
        sending = false;
        errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        sending = false;
        errorMessage = 'Could not complete email authentication. Try again.';
      });
    }
  }

  Future<void> _requestOtp() async {
    final digits = identityController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      setState(() => errorMessage = 'Enter a valid 10-digit mobile number');
      return;
    }
    setState(() {
      sending = true;
      errorMessage = null;
    });
    try {
      await auth.configureSessionPersistence(keepLoggedIn: keepLoggedIn);
      await auth.requestPhoneOtp(
        phoneNumber: digits,
        onCodeSent: () {
          if (!mounted) return;
          setState(() => sending = false);
          context.go(
            '/otp?destination=$digits&method=${LoginMethod.phone.name}',
          );
        },
        onError: (message) {
          if (!mounted) return;
          setState(() {
            sending = false;
            errorMessage = message;
          });
        },
        onAutoVerified: (route) {
          if (!mounted) return;
          setState(() => sending = false);
          context.go(route);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        sending = false;
        errorMessage =
            'Could not start phone verification. Check your internet and try again.';
      });
    }
  }
}

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({required this.email, super.key});

  final String email;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool checking = false;
  bool resending = false;
  String? errorMessage;

  String get email {
    final routeEmail = widget.email.trim();
    if (routeEmail.isNotEmpty) return routeEmail;
    return FirebaseAuthService.instance.currentUser?.email ?? 'your email';
  }

  @override
  Widget build(BuildContext context) {
    return ApprovedAuthScaffold(
      onBack: _useAnotherEmail,
      footer: PrimaryButton(
        label: checking ? 'Checking…' : "I've verified my email",
        onPressed: checking || resending ? null : _checkVerification,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppBrand(height: 70),
          const SizedBox(height: 34),
          Text(
            'Verify your email',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 12),
          Text(
            'Open the verification link sent to $email, then return here.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primaryBorder),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.mark_email_read_outlined, color: AppColors.primary),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'The link may take a minute to arrive. Check Spam or Promotions if it is not in your inbox.',
                  ),
                ),
              ],
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(errorMessage!, style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: checking || resending ? null : _resendVerification,
              icon: const Icon(Icons.refresh),
              label: Text(resending ? 'Sending…' : 'Resend verification email'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: checking || resending ? null : _useAnotherEmail,
              child: const Text('Use another email'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkVerification() async {
    setState(() {
      checking = true;
      errorMessage = null;
    });
    try {
      final result = await FirebaseAuthService.instance
          .confirmEmailVerification();
      if (mounted) context.go(result.route);
    } on FirebaseAuthFailure catch (error) {
      if (!mounted) return;
      setState(() {
        checking = false;
        errorMessage = error.message;
      });
    }
  }

  Future<void> _resendVerification() async {
    setState(() {
      resending = true;
      errorMessage = null;
    });
    try {
      await FirebaseAuthService.instance.resendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification email sent. Check your inbox and Spam.'),
        ),
      );
    } on FirebaseAuthFailure catch (error) {
      if (mounted) setState(() => errorMessage = error.message);
    } finally {
      if (mounted) setState(() => resending = false);
    }
  }

  Future<void> _useAnotherEmail() async {
    await FirebaseAuthService.instance.signOut();
    if (mounted) context.go('/login');
  }
}

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    required this.destination,
    required this.method,
    this.challengeId,
    this.profileEmailVerification = false,
    this.profilePhoneVerification = false,
    this.authService,
    super.key,
  });

  final String destination;
  final LoginMethod method;
  final String? challengeId;
  final bool profileEmailVerification;
  final bool profilePhoneVerification;
  final FirebaseAuthService? authService;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final otpController = TextEditingController();
  Timer? resendTimer;
  bool verifying = false;
  bool resending = false;
  int secondsLeft = 30;
  String? errorMessage;
  String? emailChallengeId;
  FirebaseAuthService get auth =>
      widget.authService ?? FirebaseAuthService.instance;
  String get editRoute =>
      widget.profileEmailVerification || widget.profilePhoneVerification
      ? '/profile-setup'
      : '/login';

  @override
  void initState() {
    super.initState();
    emailChallengeId = widget.challengeId;
    otpController.addListener(_clearOtpError);
    _startCountdown();
  }

  @override
  void dispose() {
    resendTimer?.cancel();
    otpController
      ..removeListener(_clearOtpError)
      ..dispose();
    super.dispose();
  }

  void _clearOtpError() {
    if (errorMessage != null && !verifying && mounted) {
      setState(() => errorMessage = null);
    }
  }

  void _startCountdown() {
    resendTimer?.cancel();
    setState(() => secondsLeft = widget.method == LoginMethod.email ? 60 : 30);
    resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (secondsLeft <= 1) {
        timer.cancel();
        setState(() => secondsLeft = 0);
      } else {
        setState(() => secondsLeft--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final digits = widget.destination.replaceAll(RegExp(r'\D'), '');
    final destinationLabel =
        widget.method == LoginMethod.phone && digits.length == 10
        ? '+91 ${digits.substring(0, 5)} ${digits.substring(5)}'
        : widget.destination;

    return ApprovedAuthScaffold(
      showBack: false,
      onBack: () => context.go(editRoute),
      footer: PrimaryButton(
        label: verifying ? 'Checking…' : 'Verify',
        icon: Icons.check,
        onPressed: otpController.text.length == 6 && !verifying && !resending
            ? _verify
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AuthArtboardHeader(),
          const SizedBox(height: 32),
          Text(
            'Enter the OTP',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                'Sent to $destinationLabel',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
              ),
              IconButton(
                onPressed: verifying || resending
                    ? null
                    : () => context.go(editRoute),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primarySoft,
                  minimumSize: const Size(32, 32),
                  padding: const EdgeInsets.all(8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                tooltip: 'Edit phone or email',
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (widget.method == LoginMethod.email) ...[
            Text(
              'Check your inbox and Spam. The code expires in 5 minutes.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
          ],
          ApprovedOtpInput(
            controller: otpController,
            enabled: !verifying && !resending,
            error: errorMessage,
            onComplete: (_) => _verify(),
          ),
          const SizedBox(height: 20),
          if (secondsLeft > 0)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Send again in ${secondsLeft ~/ 60}:${(secondsLeft % 60).toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted,
                  fontSize: 14,
                ),
              ),
            )
          else
            TextButton(
              onPressed: resending || verifying ? null : _resend,
              child: Text(resending ? 'Sending…' : 'Send again'),
            ),
        ],
      ),
    );
  }

  Future<void> _verify() async {
    if (verifying || resending || otpController.text.length != 6) return;
    setState(() {
      verifying = true;
      errorMessage = null;
    });
    try {
      final result = widget.method == LoginMethod.email
          ? widget.profileEmailVerification
                ? await auth.verifyProfileEmailOtp(
                    email: widget.destination,
                    code: otpController.text,
                    challengeId: emailChallengeId ?? '',
                  )
                : await auth.verifyEmailOtp(
                    email: widget.destination,
                    code: otpController.text,
                    challengeId: emailChallengeId ?? '',
                  )
          : await auth.verifyPhoneOtp(
              otpController.text,
              linkToCurrentUser: widget.profilePhoneVerification,
            );
      if (mounted) context.go(result.route);
    } on FirebaseAuthFailure catch (error) {
      if (mounted) {
        setState(() {
          verifying = false;
          errorMessage = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          verifying = false;
          errorMessage =
              'Could not complete sign-in. Check your connection and try again.';
        });
      }
    }
  }

  Future<void> _resend() async {
    if (verifying || resending) return;
    setState(() {
      resending = true;
      errorMessage = null;
    });
    try {
      if (widget.method == LoginMethod.email) {
        final challengeId = widget.profileEmailVerification
            ? await auth.requestProfileEmailOtp(widget.destination)
            : await auth.requestEmailOtp(widget.destination);
        if (!mounted) return;
        emailChallengeId = challengeId;
        otpController.clear();
        setState(() => resending = false);
        _startCountdown();
        return;
      }
      await auth.requestPhoneOtp(
        phoneNumber: widget.destination,
        linkToCurrentUser: widget.profilePhoneVerification,
        resend: true,
        onCodeSent: () {
          if (!mounted) return;
          otpController.clear();
          setState(() => resending = false);
          _startCountdown();
        },
        onError: (message) {
          if (!mounted) return;
          setState(() {
            resending = false;
            errorMessage = message;
          });
        },
        onAutoVerified: (route) {
          if (!mounted) return;
          setState(() => resending = false);
          context.go(route);
        },
      );
    } on FirebaseAuthFailure catch (error) {
      if (mounted) {
        setState(() {
          resending = false;
          errorMessage = error.message;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        resending = false;
        errorMessage =
            'Could not resend the OTP. Check your internet and retry.';
      });
    }
  }
}

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    this.authService,
    this.initialName,
    this.initialEmail,
    this.verifiedEmail,
    this.requiresPhoneVerification = false,
    this.emailOtpEnabled = AuthCapabilities.emailOtpEnabled,
    super.key,
  });

  final FirebaseAuthService? authService;
  final String? initialName;
  final String? initialEmail;
  final String? verifiedEmail;
  final bool requiresPhoneVerification;
  final bool emailOtpEnabled;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  String? errorMessage;
  bool sending = false;
  FirebaseAuthService get auth =>
      widget.authService ?? FirebaseAuthService.instance;

  @override
  void initState() {
    super.initState();
    nameController.text = widget.initialName ?? '';
    emailController.text = widget.initialEmail ?? widget.verifiedEmail ?? '';
  }

  bool get needsPhone => widget.requiresPhoneVerification;

  Future<void> _continue() async {
    if (sending || formKey.currentState?.validate() != true) return;
    setState(() {
      sending = true;
      errorMessage = null;
    });
    try {
      final email = !widget.emailOtpEnabled && widget.verifiedEmail == null
          ? ''
          : emailController.text.trim().toLowerCase();
      auth.savePendingProfile(name: nameController.text, email: email);
      final user = auth.currentUser;
      if (needsPhone) {
        await auth.requestPhoneOtp(
          phoneNumber: phoneController.text,
          linkToCurrentUser: true,
          onCodeSent: () {
            if (!mounted) return;
            context.go(
              Uri(
                path: '/otp',
                queryParameters: {
                  'method': 'phone',
                  'purpose': 'profile-phone',
                  'destination': phoneController.text.trim(),
                },
              ).toString(),
            );
          },
          onError: (message) {
            if (!mounted) return;
            setState(() {
              sending = false;
              errorMessage = message;
            });
          },
          onAutoVerified: (_) {
            if (mounted) context.go('/roles');
          },
        );
        return;
      }
      if (email.isEmpty && !widget.emailOtpEnabled) {
        if (profileIdentityError(
              email: '',
              verifiedEmail: user?.email,
              emailVerified: user?.emailVerified == true,
              phone: user?.phoneNumber,
            ) !=
            null) {
          throw const FirebaseAuthFailure(
            'Log in with your verified phone again.',
          );
        }
        if (mounted) context.go('/roles');
        return;
      }
      if (user?.emailVerified == true && user?.email?.toLowerCase() == email) {
        if (mounted) context.go('/roles');
        return;
      }
      final challenge = await auth.requestProfileEmailOtp(email);
      if (mounted) {
        context.go(
          Uri(
            path: '/otp',
            queryParameters: {
              'method': 'email',
              'purpose': 'profile-email',
              'destination': email,
              'challengeId': challenge,
            },
          ).toString(),
        );
      }
    } on FirebaseAuthFailure catch (error) {
      if (mounted) {
        setState(() {
          sending = false;
          errorMessage = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          sending = false;
          errorMessage =
              'Could not send your email code. Check your connection and try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ApprovedAuthScaffold(
      showBack: false,
      bodyPadding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      footer: PrimaryButton(
        label: sending
            ? 'Sending…'
            : needsPhone
            ? 'Send OTP to phone'
            : !widget.emailOtpEnabled
            ? 'Continue'
            : widget.verifiedEmail != null &&
                  widget.verifiedEmail ==
                      emailController.text.trim().toLowerCase()
            ? 'Continue'
            : 'Send OTP to email',
        onPressed: sending ? null : _continue,
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AuthArtboardHeader(),
            const SizedBox(height: 36),
            Text(
              'Welcome! What is your name?',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 6),
            Text(
              'As on your Aadhaar card.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: nameController,
              enabled: !sending,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              scrollPadding: const EdgeInsets.only(bottom: 180),
              decoration: const InputDecoration(
                labelText: 'Full name *',
                hintText: 'Type your name',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
              validator: (value) => (value?.trim().length ?? 0) < 2
                  ? 'Enter your full name'
                  : null,
            ),
            const SizedBox(height: 14),
            if (needsPhone) ...[
              TextFormField(
                controller: phoneController,
                enabled: !sending,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Mobile number *',
                  prefixText: '+91 ',
                  helperText:
                      'Verify to use phone and email for the same account.',
                  prefixIcon: Icon(Icons.phone_outlined, size: 20),
                ),
                validator: (value) =>
                    RegExp(r'^[6-9]\d{9}$').hasMatch(value?.trim() ?? '')
                    ? null
                    : 'Enter a valid 10-digit mobile number',
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: emailController,
              enabled: !sending && widget.emailOtpEnabled && !needsPhone,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              scrollPadding: const EdgeInsets.only(bottom: 180),
              decoration: InputDecoration(
                labelText: widget.emailOtpEnabled
                    ? 'Email *'
                    : 'Email · setup deferred',
                helperText: widget.emailOtpEnabled
                    ? null
                    : 'Phone login stays available. Email is not marked verified.',
                hintText: 'name@email.com',
                prefixIcon: Icon(Icons.mail_outline, size: 20),
              ),
              validator: (value) => !widget.emailOtpEnabled
                  ? null
                  : !RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    ).hasMatch(value?.trim() ?? '')
                  ? 'Enter a valid email address'
                  : null,
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                style: const TextStyle(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum UserRole { broker, owner, tenant }

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  UserRole selectedRole = UserRole.broker;
  bool saving = false;
  String? errorMessage;

  Future<void> _continue() async {
    setState(() {
      saving = true;
      errorMessage = null;
    });
    try {
      final route = await FirebaseAuthService.instance.createProfile(
        selectedRole.name,
      );
      if (mounted) context.go(route);
    } on FirebaseAuthFailure catch (error) {
      if (mounted) {
        setState(() {
          saving = false;
          errorMessage = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          errorMessage = 'Could not save your role. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ApprovedAuthScaffold(
    showBack: false,
    bodyPadding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
    footer: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (errorMessage != null) ...[
          Text(
            errorMessage!,
            style: const TextStyle(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
        ],
        PrimaryButton(
          label: saving ? 'Setting up…' : 'Continue',
          onPressed: saving ? null : _continue,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: saving ? null : () => context.go('/login'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.muted,
            padding: const EdgeInsets.all(6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          child: const Text('Used TrustKeyper before? Log in'),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AuthArtboardHeader(),
        const SizedBox(height: 36),
        Text('Who are you?', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 6),
        const Text(
          'Pick one. You can add another later.',
          style: TextStyle(
            fontSize: 17,
            height: 24 / 17,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 20),
        _RoleCard(
          icon: 'broker',
          title: 'Broker',
          subtitle: 'I make rent agreements for others',
          background: AppColors.primarySoft,
          color: AppColors.primaryDark,
          selected: selectedRole == UserRole.broker,
          onTap: saving
              ? null
              : () => setState(() => selectedRole = UserRole.broker),
        ),
        const SizedBox(height: 20),
        _RoleCard(
          icon: 'owner',
          title: 'Property owner',
          subtitle: 'I own a house and give it on rent',
          background: const Color(0xFFE7F8EF),
          color: const Color(0xFF2FA866),
          selected: selectedRole == UserRole.owner,
          onTap: saving
              ? null
              : () => setState(() => selectedRole = UserRole.owner),
        ),
        const SizedBox(height: 20),
        _RoleCard(
          icon: 'tenant',
          title: 'Tenant',
          subtitle: 'I live in a rented house',
          background: const Color(0xFFF1EAFF),
          color: const Color(0xFF7A4DFF),
          selected: selectedRole == UserRole.tenant,
          onTap: saving
              ? null
              : () => setState(() => selectedRole = UserRole.tenant),
        ),
      ],
    ),
  );
}

class AccountPausedScreen extends StatelessWidget {
  const AccountPausedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ApprovedAuthScaffold(
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AuthArtboardHeader(),
          const SizedBox(height: 48),
          const CircleAvatar(
            radius: 36,
            backgroundColor: AppColors.warningSoft,
            foregroundColor: AppColors.warning,
            child: Icon(Icons.pause_circle_outline, size: 34),
          ),
          const SizedBox(height: 24),
          Text(
            'Your account is paused',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Please call us to know more and open it again.',
            style: TextStyle(
              fontSize: 17,
              height: 24 / 17,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Call us',
            icon: Icons.phone_outlined,
            onPressed: () => launchUrl(Uri.parse('tel:+918088516875')),
          ),
        ],
      ),
    );
  }
}

class BrokerApprovalScreen extends StatelessWidget {
  const BrokerApprovalScreen({
    super.key,
    this.phoneVerified = false,
    this.emailVerified = false,
  });
  final bool phoneVerified;
  final bool emailVerified;

  @override
  Widget build(BuildContext context) {
    return KeyboardSafeScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AuthArtboardHeader(),
          const SizedBox(height: 48),
          Text(
            'We are checking your details',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 12),
          Text(
            'Brokers are checked by our team. Usually within 24 hours.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 32),
          _ApprovalStep(
            icon: phoneVerified && emailVerified
                ? Icons.check_circle_outline
                : Icons.pending_outlined,
            title: phoneVerified && emailVerified
                ? 'Phone and email verified'
                : 'Phone and email verification',
            subtitle: phoneVerified && emailVerified
                ? 'Done'
                : phoneVerified
                ? 'Email verification is still needed'
                : 'Verification is still needed',
            complete: phoneVerified && emailVerified,
          ),
          const _ApprovalStep(
            icon: Icons.manage_search_outlined,
            title: 'Team review',
            subtitle: 'Our team may call you',
          ),
          const _ApprovalStep(
            icon: Icons.description_outlined,
            title: 'Start making agreements',
            subtitle: 'We will tell you on WhatsApp',
            showConnector: false,
          ),
          const SizedBox(height: 36),
          PrimaryButton(
            label: 'Look around the app',
            onPressed: () => context.go('/broker?approval=pending'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse('tel:+918088516875')),
              icon: const Icon(Icons.phone_outlined),
              label: const Text('Call us'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalStep extends StatelessWidget {
  const _ApprovalStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.complete = false,
    this.showConnector = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool complete;
  final bool showConnector;

  @override
  Widget build(BuildContext context) {
    final color = complete ? AppColors.success : AppColors.primary;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                if (showConnector)
                  Expanded(child: Container(width: 1, color: AppColors.border)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthArtboardHeader extends StatelessWidget {
  const _AuthArtboardHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const AppBrand(height: 34),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'English is currently available. More languages are pending.',
              ),
            ),
          ),
          icon: const Icon(Icons.language, size: 16),
          label: const Text(
            'English',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.body,
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ],
    );
  }
}

class AccountRoleScreen extends StatefulWidget {
  const AccountRoleScreen({this.gateway, this.onSelected, super.key});
  final AccountRoleGateway? gateway;
  final ValueChanged<String>? onSelected;
  @override
  State<AccountRoleScreen> createState() => _AccountRoleScreenState();
}

class _AccountRoleScreenState extends State<AccountRoleScreen> {
  late final gateway = widget.gateway ?? FirebaseAccountRoleGateway();
  StreamSubscription<User?>? authentication;
  int generation = 0;
  AccountRoles? account;
  String? selected;
  String? error;
  bool busy = false;
  bool adding = false;
  @override
  void initState() {
    super.initState();
    if (widget.gateway != null) {
      _load();
    } else {
      authentication = FirebaseAuth.instance.authStateChanges().listen((user) {
        generation++;
        setState(() {
          account = null;
          selected = null;
          adding = false;
          busy = false;
          error = user == null ? 'Sign in again to choose your role.' : null;
        });
        if (user != null) _load();
      });
    }
  }

  @override
  void dispose() {
    generation++;
    authentication?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final current = ++generation;
    try {
      final result = await gateway.read();
      if (mounted && current == generation) {
        setState(() {
          account = result;
          selected = result.roles.firstOrNull;
          error = null;
        });
      }
    } catch (failure) {
      if (mounted && current == generation) {
        setState(() {
          account = null;
          selected = null;
          adding = false;
          error = _message(failure);
        });
      }
    }
  }

  String _message(Object failure) => failure is FirebaseFunctionsException
      ? failure.message ?? 'Could not load your roles. Retry.'
      : 'Could not load your roles. Retry.';
  Future<void> _open() async {
    if (selected == null || busy) return;
    final current = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final route = adding
          ? await gateway.add(selected!)
          : await gateway.select(selected!);
      if (!mounted || current != generation) return;
      if (widget.onSelected != null) {
        widget.onSelected!(route);
      } else {
        context.go(route);
      }
    } catch (failure) {
      if (mounted && current == generation) {
        setState(() => error = _message(failure));
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = adding
        ? [
            'broker',
            'owner',
            'tenant',
          ].where((role) => !account!.roles.contains(role)).toList()
        : account?.roles ?? <String>[];
    const names = {
      'broker': 'Broker',
      'owner': 'Property owner',
      'tenant': 'Tenant',
    };
    return ApprovedAuthScaffold(
      showBack: false,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: AppColors.error)),
            TextButton(
              onPressed: busy ? null : _load,
              child: const Text('Retry'),
            ),
            const SizedBox(height: 8),
          ],
          PrimaryButton(
            label: busy
                ? 'Opening…'
                : adding
                ? 'Add ${names[selected]?.toLowerCase() ?? 'role'}'
                : 'Continue as ${names[selected]?.toLowerCase() ?? 'your role'}',
            onPressed: busy || selected == null ? null : _open,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AuthArtboardHeader(),
          const SizedBox(height: 36),
          Text(
            adding
                ? 'Add another role'
                : 'Welcome back${account?.name.isNotEmpty == true ? ', ${account!.name}' : ''}',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 6),
          Text(
            adding
                ? 'This does not link new homes or approve a broker.'
                : account == null
                ? 'Loading your roles…'
                : 'You have ${account!.roles.length} roles. Which one now?',
            style: const TextStyle(
              fontSize: 17,
              height: 24 / 17,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 20),
          if (account == null && error == null)
            const Center(child: CircularProgressIndicator()),
          for (final role in available) ...[
            _RoleCard(
              icon: role,
              title: names[role]!,
              subtitle: role == 'broker'
                  ? account?.brokerApproved == true
                        ? 'Your agreements and brokerage'
                        : 'Approval needed before making agreements'
                  : role == 'owner'
                  ? 'Your linked properties'
                  : 'Your linked home and rent',
              selected: selected == role,
              onTap: busy ? null : () => setState(() => selected = role),
              background: role == 'broker'
                  ? AppColors.primarySoft
                  : role == 'owner'
                  ? AppColors.successSoft
                  : const Color(0xFFF1EAFF),
              color: role == 'broker'
                  ? AppColors.primaryDark
                  : role == 'owner'
                  ? const Color(0xFF2FA866)
                  : const Color(0xFF7A4DFF),
            ),
            const SizedBox(height: 20),
          ],
          const Center(
            child: Text(
              'You can switch any time from Profile.',
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ),
          if (account != null && account!.roles.length < 3)
            Center(
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        adding = !adding;
                        selected = adding
                            ? ['broker', 'owner', 'tenant'].firstWhere(
                                (role) => !account!.roles.contains(role),
                              )
                            : account!.roles.firstOrNull;
                      }),
                child: Text(adding ? 'Back to my roles' : 'Add another role'),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.background,
    required this.color,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: title,
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: EdgeInsets.all(selected ? 20 : 19),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/design/role-$icon.svg',
                      width: 30,
                      height: 30,
                      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          height: 24 / 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.heading,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 20 / 14.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.primary : Colors.white,
                    border: selected
                        ? null
                        : Border.all(color: const Color(0xFF9AA8BA), width: 2),
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
