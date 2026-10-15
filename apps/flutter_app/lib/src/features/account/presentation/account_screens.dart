import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/presentation/approved_auth_widgets.dart';
import '../../auth/data/firebase_auth_service.dart' show FirebaseAuthFailure;
import '../../../core/widgets/session_bound_screen.dart';
import '../data/account_gateway.dart';
import 'account_detail_field.dart';

String accountError(Object error) => error is FirebaseAuthFailure
    ? error.message
    : error is FirebaseFunctionsException
    ? error.message ?? 'Please try again.'
    : error is TimeoutException
    ? 'This is taking too long. Check your connection and retry.'
    : 'This request could not be confirmed. Please retry.';

class AccountGlyph extends StatelessWidget {
  const AccountGlyph(
    this.name, {
    this.color = AppColors.primaryDark,
    this.size = 22,
    super.key,
  });
  final String name;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) {
    final paths = switch (name) {
      'person' =>
        '<circle cx="12" cy="8" r="4"/><path d="M5 21v-2a7 7 0 0 1 14 0v2"/>',
      'phone' =>
        '<path d="M22 16.9v3a2 2 0 0 1-2.2 2A19.8 19.8 0 0 1 11.2 19a19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1 1 .3 1.9.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.5c.8.4 1.7.6 2.7.7a2 2 0 0 1 1.9 2.2Z"/>',
      'email' =>
        '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m2 6 10 7 10-7"/>',
      'city' =>
        '<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/>',
      'id' =>
        '<rect x="2" y="4" width="20" height="16" rx="2"/><circle cx="8" cy="10" r="2"/><path d="M5 17a3 3 0 0 1 6 0m4-8h4m-4 4h4"/>',
      'bank' => '<path d="m3 9 9-6 9 6H3Zm0 12h18M6 12v6m6-6v6m6-6v6"/>',
      'globe' =>
        '<circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><ellipse cx="12" cy="12" rx="4" ry="10"/>',
      'help' =>
        '<circle cx="12" cy="12" r="10"/><path d="M9 9a3 3 0 0 1 6 0c0 2-3 2-3 4m0 4h.01"/>',
      'logout' =>
        '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4m7 14 5-5-5-5M21 12H9"/>',
      'trash' =>
        '<path d="M3 6h18m-16 0 1 14h12l1-14M9 6V3h6v3m-5 4v7m4-7v7"/>',
      'file' =>
        '<path d="M14 2H5v20h14V7l-5-5Zm0 0v5h5M8 11h8m-8 4h8m-8 4h5"/>',
      'property' =>
        '<rect x="4" y="2" width="16" height="20" rx="1"/><path d="M4 17h16"/>',
      'money' =>
        '<rect x="4" y="2" width="16" height="20" rx="1"/><path d="M12 5v14m3-11c-4-4-8 2-3 4s1 8-3 4"/>',
      _ => '<circle cx="12" cy="12" r="10"/>',
    };
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#${color.toARGB32().toRadixString(16).substring(2)}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">$paths</svg>',
      width: size,
      height: size,
    );
  }
}

class AccountHeader extends StatelessWidget {
  const AccountHeader(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          style: IconButton.styleFrom(
            shape: const CircleBorder(),
            side: const BorderSide(color: AppColors.border),
            shadowColor: AppColors.heading.withValues(alpha: .1),
            elevation: 2,
            backgroundColor: Colors.white,
            fixedSize: const Size(48, 48),
          ),
          icon: const Icon(Icons.chevron_left, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AppColors.heading,
            ),
          ),
        ),
      ],
    ),
  );
}

class AccountProfilePanel extends StatelessWidget {
  const AccountProfilePanel({
    required this.name,
    required this.phone,
    required this.role,
    required this.gateway,
    this.email = '',
    this.bankName = '',
    this.bankLast4 = '',
    this.onUpdates,
    this.onSignedOut,
    this.onSwitchRole,
    this.onManagerSupport,
    this.onLogout,
    super.key,
  });
  final String name, phone, email, role, bankName, bankLast4;
  final AccountGateway? gateway;
  final VoidCallback? onUpdates, onSignedOut, onSwitchRole, onManagerSupport;
  final Future<void> Function()? onLogout;
  Future<void> _logout(BuildContext context) async {
    final account = gateway;
    final expectedUid = account is FirebaseAccountGateway
        ? account.auth.currentUser?.uid
        : null;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.errorSoft,
                child: AccountGlyph('logout', color: AppColors.error, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Log out?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'You will need your phone number and OTP to come back.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 17),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Yes, log out',
                onPressed: () => Navigator.pop(context, true),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No, stay'),
              ),
            ],
          ),
        ),
      ),
    );
    if (yes != true ||
        !context.mounted ||
        gateway == null && onLogout == null) {
      return;
    }
    if (account is FirebaseAccountGateway &&
        account.auth.currentUser?.uid != expectedUid) {
      return;
    }
    try {
      await (onLogout?.call() ?? gateway!.logout()).timeout(
        const Duration(seconds: 30),
      );
      if (context.mounted) onSignedOut?.call();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(accountError(error))));
      }
    }
  }

  void _open(BuildContext context, Widget child) {
    final account = gateway;
    final uid = account is FirebaseAccountGateway
        ? account.auth.currentUser?.uid
        : null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => account is FirebaseAccountGateway
            ? SessionBoundScreen(
                users: account.auth.authStateChanges().map((user) => user?.uid),
                initialUid: uid,
                expectedUid: uid,
                child: child,
              )
            : child,
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final account = gateway;
    if (account == null) return;
    final uid = account is FirebaseAccountGateway
        ? account.auth.currentUser?.uid
        : null;
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        final child = AccountDeletionDialog(gateway: account);
        return account is FirebaseAccountGateway
            ? SessionBoundScreen(
                users: account.auth.authStateChanges().map((user) => user?.uid),
                initialUid: uid,
                expectedUid: uid,
                child: child,
              )
            : child;
      },
    );
    if (draft == null || !context.mounted) return;
    _open(
      context,
      AccountClosureScreen(
        gateway: account,
        onSignedOut: onSignedOut,
        initialStep: 2,
        initialEligibility: Map<String, dynamic>.from(
          draft['eligibility'] as Map,
        ),
        initialReason: draft['reason'] as String,
        initialNote: draft['note'] as String,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase();
    Widget row(
      String icon,
      String title,
      String subtitle,
      VoidCallback? action, {
      Color color = AppColors.heading,
    }) => InkWell(
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.surfaceMuted,
              child: AccountGlyph(
                icon,
                color: color == AppColors.error ? color : AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
          ],
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Profile',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: AppColors.heading,
                ),
              ),
            ),
            if (onUpdates != null)
              IconButton(
                onPressed: onUpdates,
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Updates',
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.primarySoft,
              child: Text(
                initial.isEmpty ? role[0].toUpperCase() : initial,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.trim().isEmpty ? 'Your profile' : name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.heading,
                    ),
                  ),
                  Text(
                    phone.isNotEmpty ? phone : email,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '${role[0].toUpperCase()}${role.substring(1)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (onManagerSupport != null)
          row(
            'help',
            'Your TrustKeyper manager',
            'Call, WhatsApp, email or request a callback',
            onManagerSupport,
          ),
        if (onSwitchRole != null)
          row('person', 'Switch role', 'Broker, owner or tenant', onSwitchRole),
        row(
          'person',
          'My details',
          'Name, phone, email',
          gateway == null
              ? null
              : () => _open(
                  context,
                  AccountDetailsScreen(gateway: gateway!, role: role),
                ),
        ),
        const Divider(height: 1, color: AppColors.border),
        row(
          'bank',
          'Bank for my money',
          bankLast4.isEmpty ? 'Not added yet' : '$bankName · ending $bankLast4',
          gateway == null
              ? null
              : () => _open(context, AccountBankScreen(gateway: gateway!)),
        ),
        const Divider(height: 1, color: AppColors.border),
        row(
          'globe',
          'Language',
          'English',
          () => _open(context, const AccountLanguageScreen()),
        ),
        const Divider(height: 1, color: AppColors.border),
        row(
          'help',
          'Help',
          'Call or WhatsApp us',
          () => _open(context, const AccountHelpScreen()),
        ),
        const Divider(height: 1, color: AppColors.border),
        row(
          'logout',
          'Log out',
          '',
          gateway == null && onLogout == null ? null : () => _logout(context),
          color: AppColors.error,
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: gateway == null ? null : () => _delete(context),
            child: const Text(
              'Delete account',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.muted,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({
    required this.gateway,
    this.role = 'broker',
    super.key,
  });
  final AccountGateway gateway;
  final String role;
  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      city = TextEditingController(),
      rera = TextEditingController(),
      code = TextEditingController();
  AccountProfileData? data;
  bool loading = true, busy = false;
  String? error, emailError, challenge, challengeEmail;
  String? verifiedAddress;
  int generation = 0, cooldown = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    for (final field in [name, email, city, rera, code]) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(AccountDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway) {
      data = null;
      busy = false;
      emailError = null;
      verifiedAddress = null;
      challenge = null;
      challengeEmail = null;
      timer?.cancel();
      cooldown = 0;
      for (final controller in [name, email, city, rera, code]) {
        controller.clear();
      }
      _load();
    }
  }

  Future<void> _load() async {
    final active = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.gateway.read().timeout(
        const Duration(seconds: 45),
      );
      if (!mounted || active != generation) return;
      setState(() {
        data = result;
        name.text = result.text('displayName');
        email.text = result.text('email');
        city.text = result.text('city');
        rera.text = result.text('reraNumber');
        loading = false;
      });
    } catch (failure) {
      if (mounted && active == generation) {
        setState(() {
          error = accountError(failure);
          loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (busy || form.currentState?.validate() != true) return;
    final address = email.text.trim().toLowerCase();
    final currentEmail = verifiedAddress ?? data!.text('email').toLowerCase();
    final changedEmail =
        address.isNotEmpty &&
        (address != currentEmail ||
            verifiedAddress == null && !data!.flag('emailVerified'));
    if (changedEmail && challengeEmail != address) {
      await _send();
      return;
    }
    if (changedEmail && code.text.length != 6) {
      setState(() => emailError = 'Enter all six digits from your email.');
      return;
    }
    final active = ++generation;
    final input = {
      'displayName': name.text.trim(),
      'city': city.text.trim(),
      'reraNumber': rera.text.trim(),
      'email': address,
    };
    setState(() {
      busy = true;
      error = null;
      emailError = null;
    });
    try {
      if (changedEmail) {
        await widget.gateway
            .verifyEmail(address, challenge!, code.text)
            .timeout(const Duration(seconds: 45));
        if (!mounted || generation != active) return;
        verifiedAddress = address;
      }
      final saved = await widget.gateway
          .save(input)
          .timeout(const Duration(seconds: 45));
      if (!mounted || active != generation) return;
      setState(() {
        data = saved;
        busy = false;
        challenge = null;
        challengeEmail = null;
        code.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Your details are saved.')));
    } catch (failure) {
      if (mounted && active == generation) {
        setState(() {
          busy = false;
          if (changedEmail && verifiedAddress != address) {
            emailError = accountError(failure);
          } else {
            error = accountError(failure);
          }
        });
      }
    }
  }

  Future<void> _send() async {
    if (busy || cooldown > 0) return;
    final address = email.text.trim().toLowerCase(), active = ++generation;
    setState(() {
      busy = true;
      emailError = null;
      error = null;
    });
    try {
      final value = await widget.gateway
          .requestEmail(address)
          .timeout(const Duration(seconds: 45));
      if (!mounted ||
          active != generation ||
          email.text.trim().toLowerCase() != address) {
        return;
      }
      setState(() {
        challenge = value;
        challengeEmail = address;
        busy = false;
        cooldown = 60;
        code.clear();
      });
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || cooldown <= 1) {
          timer.cancel();
          if (mounted) setState(() => cooldown = 0);
        } else {
          setState(() => cooldown--);
        }
      });
    } catch (failure) {
      if (mounted && active == generation) {
        setState(() {
          busy = false;
          emailError = accountError(failure);
        });
      }
    }
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String icon, {
    String? Function(String?)? validator,
    int limit = 100,
    TextInputType? keyboard,
  }) => AccountDetailField(
    label: label,
    controller: controller,
    icon: AccountGlyph(icon, color: AppColors.muted, size: 20),
    hint: icon == 'id' ? 'Not needed' : null,
    changed: controller != email
        ? null
        : (value) {
            if (challengeEmail != null &&
                value.trim().toLowerCase() != challengeEmail) {
              setState(() {
                challenge = null;
                challengeEmail = null;
                emailError = null;
                cooldown = 0;
                code.clear();
              });
              timer?.cancel();
            }
          },
    enabled: !busy,
    limit: limit,
    keyboard: keyboard,
    validator: validator,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const AccountHeader('My details'),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : data == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error ?? 'Details unavailable.'),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : Form(
                    key: form,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        _field(
                          'Full name *',
                          name,
                          'person',
                          limit: 120,
                          validator: (value) => value?.trim().isNotEmpty == true
                              ? null
                              : 'Enter your full name.',
                        ),
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          constraints: const BoxConstraints(minHeight: 60),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const AccountGlyph(
                                'phone',
                                color: AppColors.muted,
                                size: 20,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Mobile number',
                                      style: TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 13,
                                        height: 1.3,
                                      ),
                                    ),
                                    Text(
                                      data!.text('phone').isEmpty
                                          ? 'Not linked'
                                          : data!.text('phone'),
                                      style: const TextStyle(
                                        fontSize: 17,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (data!.flag('phoneVerified'))
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.successSoft,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check,
                                        color: AppColors.success,
                                        size: 14,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Verified',
                                        style: TextStyle(
                                          color: AppColors.success,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _field(
                          'Email',
                          email,
                          'email',
                          limit: 254,
                          keyboard: TextInputType.emailAddress,
                          validator: (value) =>
                              value?.trim().isEmpty == true &&
                                  (verifiedAddress ?? data!.text('email'))
                                      .isNotEmpty
                              ? 'Your verified login email cannot be removed here.'
                              : value == null ||
                                    value.trim().isEmpty ||
                                    RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                    ).hasMatch(value.trim())
                              ? null
                              : 'Enter a valid email address.',
                        ),
                        if (challenge != null) ...[
                          Text(
                            'Enter the code sent to $challengeEmail',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 10),
                          ApprovedOtpInput(
                            controller: code,
                            enabled: !busy,
                            error: emailError,
                          ),
                          TextButton(
                            onPressed: busy || cooldown > 0 ? null : _send,
                            child: Text(
                              cooldown > 0
                                  ? 'Send again in 0:${cooldown.toString().padLeft(2, '0')}'
                                  : 'Send again',
                            ),
                          ),
                        ],
                        if (emailError != null && challenge == null)
                          Text(
                            emailError!,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        _field('City', city, 'city'),
                        if (widget.role == 'broker')
                          _field('RERA number (if you have)', rera, 'id'),
                        if (error != null)
                          Text(
                            error!,
                            style: const TextStyle(color: AppColors.error),
                          ),
                      ],
                    ),
                  ),
          ),
          if (data != null)
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.maybePop(context),
                    child: const Text('‹ Back'),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: PrimaryButton(
                      label: challenge == null ? 'Save' : 'Verify and save',
                      loading: busy,
                      onPressed: busy ? null : _save,
                      icon: Icons.check,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class AccountHelpScreen extends StatelessWidget {
  const AccountHelpScreen({this.openLink, super.key});
  final Future<bool> Function(Uri)? openLink;
  Future<void> _contact(BuildContext context, Uri uri) async {
    try {
      final opened =
          await (openLink?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No app could open this contact. Call +91 80885 16875.',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this contact. Call +91 80885 16875.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const AccountHeader('Help'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                PrimaryButton(
                  label: 'Call us',
                  icon: Icons.call_outlined,
                  iconBeforeLabel: true,
                  onPressed: () =>
                      _contact(context, Uri.parse('tel:+918088516875')),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.successSoft,
                    foregroundColor: AppColors.success,
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  onPressed: () =>
                      _contact(context, Uri.https('wa.me', '/918088516875')),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('WhatsApp us'),
                ),
                const SizedBox(height: 14),
                const Text(
                  'We answer 9 am – 8 pm, every day',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
                const SizedBox(height: 18),
                const Text(
                  'ⓘ Common questions',
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
                const SizedBox(height: 14),
                for (final question in [
                  (
                    'How long does signing take?',
                    'The team checks the agreed details and arranges the signed legal copy. Track its real status under Agreements, or call us for the current estimate.',
                  ),
                  (
                    'When do I get my brokerage?',
                    'Brokerage is held until signing and is due after move-in under your agreed terms. A completed rent payment is not a brokerage payout. Check Payments or contact the team.',
                  ),
                  (
                    'Owner did not get the link',
                    'Open the saved agreement and the correct owner, check their phone or email, then send or resend the requested paper link. A new link replaces an expired one. WhatsApp and SMS open a composer; send the message there.',
                  ),
                  (
                    'How do I change an agreement?',
                    'Edit a draft before sending it. After sending, use the correction/review process and collect fresh approvals. A signed legal agreement must not be changed silently; ask the team to arrange an amendment.',
                  ),
                ])
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      question.$1,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          question.$2,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class AccountBankScreen extends StatefulWidget {
  const AccountBankScreen({required this.gateway, super.key});
  final AccountGateway gateway;
  @override
  State<AccountBankScreen> createState() => _AccountBankScreenState();
}

class _AccountBankScreenState extends State<AccountBankScreen> {
  late Future<AccountProfileData> details = widget.gateway.read().timeout(
    const Duration(seconds: 45),
  );
  @override
  void didUpdateWidget(AccountBankScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway) {
      details = widget.gateway.read().timeout(const Duration(seconds: 45));
    }
  }

  void _retry() {
    setState(() {
      details = widget.gateway.read().timeout(const Duration(seconds: 45));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const AccountHeader('Bank for my money'),
          Expanded(
            child: FutureBuilder<AccountProfileData>(
              key: ValueKey(details),
              future: details,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(accountError(snapshot.error!)),
                        TextButton(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primarySoft,
                      child: AccountGlyph('bank', size: 36),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      data.text('bankName').isEmpty
                          ? 'Bank not added'
                          : data.text('bankName'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (data.text('bankAccountLast4').isNotEmpty)
                      Text(
                        '•••• •••• ${data.text('bankAccountLast4')}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22),
                      ),
                    const SizedBox(height: 20),
                    const Text(
                      'Bank verification and changes will be enabled with the Razorpay integration. Existing details are not marked verified without provider confirmation.',
                      style: TextStyle(color: AppColors.muted, fontSize: 17),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class AccountLanguageScreen extends StatelessWidget {
  const AccountLanguageScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const AccountHeader('Language'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Pick the language you read best.',
                  style: TextStyle(fontSize: 17, color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                const ListTile(
                  leading: Icon(Icons.check_circle, color: AppColors.primary),
                  title: Text('English'),
                  subtitle: Text('Currently available'),
                ),
                const ListTile(
                  title: Text('हिंदी · Hindi'),
                  subtitle: Text('Full translation is not yet available'),
                ),
                const ListTile(
                  title: Text('తెలుగు · Telugu'),
                  subtitle: Text('Full translation is not yet available'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class AccountClosureScreen extends StatefulWidget {
  const AccountClosureScreen({
    required this.gateway,
    this.onSignedOut,
    this.initialStep = 0,
    this.initialEligibility,
    this.initialReason = '',
    this.initialNote = '',
    super.key,
  });
  final AccountGateway gateway;
  final VoidCallback? onSignedOut;
  final int initialStep;
  final Map<String, dynamic>? initialEligibility;
  final String initialReason, initialNote;
  @override
  State<AccountClosureScreen> createState() => _AccountClosureScreenState();
}

class _AccountClosureScreenState extends State<AccountClosureScreen> {
  Map<String, dynamic>? eligibility;
  String? error;
  String reason = '';
  final note = TextEditingController();
  int step = 0, generation = 0;
  bool busy = false, understood = false, closed = false;
  @override
  void initState() {
    super.initState();
    step = widget.initialStep;
    reason = widget.initialReason;
    note.text = widget.initialNote;
    eligibility = widget.initialEligibility;
    if (eligibility == null) _read();
  }

  @override
  void dispose() {
    generation++;
    note.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final active = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.gateway.closure().timeout(
        const Duration(seconds: 45),
      );
      if (mounted && active == generation) {
        setState(() {
          eligibility = data;
          closed = data['status'] == 'closed';
          busy = false;
        });
      }
    } catch (failure) {
      if (mounted && active == generation) {
        setState(() {
          error = accountError(failure);
          busy = false;
        });
      }
    }
  }

  Future<void> _close() async {
    if (!understood || busy) return;
    final active = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.gateway
          .close(reason: reason, note: note.text.trim())
          .timeout(const Duration(seconds: 45));
      if (result['closed'] != true) {
        throw StateError('Closure was not confirmed.');
      }
      if (mounted && active == generation) {
        setState(() {
          closed = true;
          busy = false;
        });
      }
    } catch (failure) {
      if (mounted && active == generation) {
        setState(() {
          error = accountError(failure);
          busy = false;
        });
      }
    }
  }

  Future<void> _leave() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.gateway.logout().timeout(const Duration(seconds: 30));
      if (mounted) {
        setState(() => busy = false);
        if (widget.onSignedOut != null) {
          widget.onSignedOut!();
        } else {
          await Navigator.maybePop(context);
        }
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = accountError(failure);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canClose =
        eligibility?['canClose'] == true &&
        eligibility?['requiresLogin'] != true;
    final blockers = List<String>.from(eligibility?['blockers'] as List? ?? []);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (!closed)
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: IconButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.maybePop(context),
                      style: IconButton.styleFrom(
                        fixedSize: const Size(48, 48),
                        shape: const CircleBorder(),
                        side: const BorderSide(color: AppColors.border),
                        backgroundColor: Colors.white,
                        shadowColor: AppColors.heading.withValues(alpha: .1),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Step ${step + 1} of 3',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                  const SizedBox(width: 88),
                ],
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  closed
                      ? 20
                      : step == 2
                      ? 4
                      : 20,
                  24,
                  20,
                ),
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: closed
                        ? AppColors.successSoft
                        : step == 2
                        ? AppColors.error
                        : AppColors.errorSoft,
                    child: closed
                        ? const Icon(
                            Icons.check,
                            color: AppColors.success,
                            size: 42,
                          )
                        : step == 2
                        ? const Icon(
                            Icons.error_outline,
                            color: Colors.white,
                            size: 42,
                          )
                        : const AccountGlyph(
                            'trash',
                            color: AppColors.error,
                            size: 36,
                          ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    closed
                        ? 'Your account is closed'
                        : [
                            'Delete your account?',
                            'Are you really sure?',
                            'Last step',
                          ][step],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: closed ? AppColors.heading : AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    closed
                        ? 'Login and app access are disabled. Contact us within 7 days if this was a mistake.'
                        : 'Your access will be removed. Required legal and audit records are retained.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!closed && step == 1) ...[
                    const Text(
                      'Why are you leaving? (not needed)',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    RadioGroup<String>(
                      groupValue: reason,
                      onChanged: (value) {
                        if (!busy && value != null) {
                          setState(() => reason = value);
                        }
                      },
                      child: Column(
                        children: [
                          for (final option in [
                            ('stopped', 'I stopped this work'),
                            ('difficult', 'Too hard to use'),
                            ('another_app', 'I use another app'),
                            ('other', 'Other'),
                          ])
                            RadioListTile<String>(
                              value: option.$1,
                              title: Text(option.$2),
                            ),
                        ],
                      ),
                    ),
                    if (reason == 'other')
                      TextField(
                        controller: note,
                        maxLength: 500,
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'Tell us why (optional)',
                        ),
                      ),
                  ],
                  if (!closed && step == 2) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.errorSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFFB5B1)),
                      ),
                      child: Column(
                        children: [
                          for (final line in [
                            ('file', 'All your agreements'),
                            ('property', 'Your properties, owners and tenants'),
                            ('money', 'Your payment history'),
                            ('phone', 'Your login will be disabled'),
                          ])
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                children: [
                                  AccountGlyph(
                                    line.$1,
                                    size: 20,
                                    color: AppColors.error,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      line.$2,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: AppColors.heading,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.error,
                      value: understood,
                      onChanged: busy
                          ? null
                          : (value) =>
                                setState(() => understood = value == true),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'I understand. Close my account and disable access.',
                      ),
                    ),
                  ],
                  if (!closed && eligibility == null && busy)
                    const Center(child: CircularProgressIndicator()),
                  for (final blocker in blockers)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        blocker,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  if (eligibility?['requiresLogin'] == true)
                    const Text(
                      'For safety, log in again before closing your account.',
                      style: TextStyle(color: AppColors.error),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  if (!closed && (!canClose || error != null))
                    TextButton(
                      onPressed: busy ? null : _read,
                      child: const Text('Check again'),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  PrimaryButton(
                    backgroundColor: !closed && step == 2
                        ? AppColors.error
                        : null,
                    icon: !closed && step == 2 ? Icons.delete_outline : null,
                    iconBeforeLabel: true,
                    label: closed
                        ? 'Close'
                        : step == 2
                        ? 'Close account'
                        : 'Keep my account',
                    loading: busy,
                    onPressed: busy
                        ? null
                        : closed
                        ? _leave
                        : step == 2
                        ? canClose && understood
                              ? _close
                              : null
                        : () => Navigator.maybePop(context),
                  ),
                  if (!closed && step == 2) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: busy
                            ? null
                            : () {
                                if (widget.initialStep == 2) {
                                  Navigator.maybePop(context);
                                } else {
                                  setState(() => step = 1);
                                }
                              },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: const Text(
                          'No, go back',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (!closed && step < 2)
                    TextButton(
                      onPressed: busy || !canClose
                          ? null
                          : step < 2
                          ? () => setState(() => step++)
                          : () => setState(() => step = 1),
                      child: Text(
                        step < 2
                            ? step == 0
                                  ? 'Yes, delete'
                                  : 'Yes, I am sure'
                            : 'No, go back',
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountDeletionDialog extends StatefulWidget {
  const AccountDeletionDialog({required this.gateway, super.key});
  final AccountGateway gateway;
  @override
  State<AccountDeletionDialog> createState() => _AccountDeletionDialogState();
}

class _AccountDeletionDialogState extends State<AccountDeletionDialog> {
  Map<String, dynamic>? eligibility;
  int step = 0, generation = 0;
  bool busy = true;
  String reason = '';
  String? error;
  final note = TextEditingController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AccountDeletionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway) {
      eligibility = null;
      step = 0;
      reason = '';
      note.clear();
      _load();
    }
  }

  @override
  void dispose() {
    generation++;
    note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final active = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.gateway.closure().timeout(
        const Duration(seconds: 45),
      );
      if (mounted && active == generation) {
        setState(() {
          eligibility = result;
          busy = false;
        });
      }
    } catch (failure) {
      if (mounted && active == generation) {
        setState(() {
          error = accountError(failure);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        eligibility?['canClose'] == true &&
        eligibility?['requiresLogin'] != true;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Step ${step + 1} of 3',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.errorSoft,
              child: AccountGlyph('trash', color: AppColors.error, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              step == 0 ? 'Delete your account?' : 'Are you really sure?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppColors.heading,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'You will lose access to everything you made here. Required shared legal and audit records are retained.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 17),
            ),
            const SizedBox(height: 18),
            if (step == 0)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    for (final line in [
                      ('file', 'All your agreements'),
                      ('property', 'Your properties, owners and tenants'),
                      ('money', 'Your payment history'),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            AccountGlyph(
                              line.$1,
                              color: AppColors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                line.$2,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (step == 1) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Why are you leaving? (not needed)',
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
              ),
              RadioGroup<String>(
                groupValue: reason,
                onChanged: (value) {
                  if (!busy && value != null) setState(() => reason = value);
                },
                child: Column(
                  children: [
                    for (final option in [
                      ('stopped', 'I stopped this work'),
                      ('difficult', 'Too hard to use'),
                      ('another_app', 'I use another app'),
                      ('other', 'Other'),
                    ])
                      RadioListTile<String>(
                        value: option.$1,
                        title: Text(option.$2),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              if (reason == 'other')
                TextField(
                  controller: note,
                  enabled: !busy,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Tell us why (optional)',
                  ),
                ),
            ],
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            for (final blocker in List<String>.from(
              eligibility?['blockers'] as List? ?? [],
            ))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  blocker,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            if (eligibility?['requiresLogin'] == true)
              const Text(
                'For safety, log in again before closing your account.',
                style: TextStyle(color: AppColors.error),
              ),
            if (error != null)
              Text(error!, style: const TextStyle(color: AppColors.error)),
            if (error != null || !ready && !busy)
              TextButton(
                onPressed: busy ? null : _load,
                child: const Text('Check again'),
              ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: step == 0 ? 'Keep my account' : 'No, keep my account',
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: busy || !ready
                  ? null
                  : () {
                      if (step == 0) {
                        setState(() => step = 1);
                      } else {
                        Navigator.pop(context, {
                          'eligibility': eligibility!,
                          'reason': reason,
                          'note': note.text.trim(),
                        });
                      }
                    },
              child: Text(
                step == 0 ? 'Yes, delete' : 'Yes, I am sure',
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
