import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_brand.dart';
import 'login_method.dart';

class ApprovedLoginHero extends StatelessWidget {
  const ApprovedLoginHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primarySoft, AppColors.surfaceMuted],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            for (final building in [
              (20.0, 70.0, 70.0, 0xFFC9D6F2),
              (110.0, 90.0, 110.0, 0xFFB6C7EE),
              (230.0, 80.0, 90.0, 0xFFC9D6F2),
              (330.0, 70.0, 70.0, 0xFFB6C7EE),
            ])
              Positioned(
                left: building.$1 * constraints.maxWidth / 440,
                width: building.$2 * constraints.maxWidth / 440,
                height: building.$3,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Color(building.$4),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 18,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Color(0xFF8EA6E6),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 6,
              child: ColoredBox(color: Color(0xFFB6C7EE)),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 34,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.heading.withValues(alpha: 0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const AppBrand(height: 40),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ApprovedAuthScaffold extends StatelessWidget {
  const ApprovedAuthScaffold({
    required this.child,
    super.key,
    this.footer,
    this.onBack,
    this.showBack = true,
    this.header,
    this.scrollable = true,
    this.footerBorder = true,
    this.footerPadding = const EdgeInsets.fromLTRB(24, 14, 24, 28),
    this.bodyPadding = const EdgeInsets.fromLTRB(24, 20, 24, 16),
  });

  final Widget child;
  final Widget? footer;
  final VoidCallback? onBack;
  final bool showBack;
  final Widget? header;
  final bool scrollable;
  final bool footerBorder;
  final EdgeInsets footerPadding;
  final EdgeInsets bodyPadding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            ?header,
            if (showBack && onBack != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                  child: ApprovedBackButton(onPressed: onBack!),
                ),
              ),
            Expanded(
              child: scrollable
                  ? SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Padding(padding: bodyPadding, child: child),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: child,
                    ),
            ),
            if (footer != null)
              Container(
                padding: footerPadding,
                decoration: BoxDecoration(
                  border: footerBorder
                      ? const Border(top: BorderSide(color: Color(0xFFEDF1F6)))
                      : null,
                ),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

class ApprovedBackButton extends StatelessWidget {
  const ApprovedBackButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      elevation: 1,
      shadowColor: AppColors.heading.withValues(alpha: 0.08),
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.chevron_left, color: AppColors.heading, size: 26),
        ),
      ),
    );
  }
}

class ApprovedPhoneField extends StatefulWidget {
  const ApprovedPhoneField({
    required this.controller,
    super.key,
    this.enabled = true,
    this.error,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? error;

  @override
  State<ApprovedPhoneField> createState() => _ApprovedPhoneFieldState();
}

class ApprovedEmailField extends StatelessWidget {
  const ApprovedEmailField({
    required this.controller,
    super.key,
    this.enabled = true,
    this.error,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.email],
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'Email address',
        hintText: 'you@example.com',
        prefixIcon: const Icon(Icons.mail_outline),
        errorText: error,
      ),
    );
  }
}

class AuthMethodSelector extends StatelessWidget {
  const AuthMethodSelector({
    required this.selected,
    required this.onChanged,
    super.key,
    this.enabled = true,
  });

  final LoginMethod selected;
  final ValueChanged<LoginMethod> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('auth-method-selector'),
      color: AppColors.surfaceMuted,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _MethodButton(
                icon: Icons.phone_outlined,
                label: 'Phone',
                selected: selected == LoginMethod.phone,
                onPressed: enabled ? () => onChanged(LoginMethod.phone) : null,
              ),
              const SizedBox(width: 2),
              _MethodButton(
                icon: Icons.mail_outline,
                label: 'Email',
                selected: selected == LoginMethod.email,
                onPressed: enabled ? () => onChanged(LoginMethod.email) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? AppColors.background : AppColors.surfaceMuted,
        elevation: selected ? 1 : 0,
        shadowColor: AppColors.heading.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Ink(
            key: ValueKey('auth-method-${label.toLowerCase()}'),
            color: selected ? AppColors.background : AppColors.surfaceMuted,
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppColors.primaryDark : AppColors.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppColors.primaryDark : AppColors.muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LoginLegalNotice extends StatelessWidget {
  const LoginLegalNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 13.5,
        color: AppColors.muted,
        height: 18 / 13.5,
      ),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          children: [
            const Text('By continuing, you agree to TrustKeyper '),
            _LegalLink(
              label: 'Terms',
              uri: Uri.parse('https://trustkeyper.com/terms'),
            ),
            const Text(' and '),
            _LegalLink(
              label: 'Privacy',
              uri: Uri.parse('https://trustkeyper.com/privacy'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedPhoneFieldState extends State<ApprovedPhoneField> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.error != null
        ? AppColors.error
        : focused
        ? AppColors.primary
        : AppColors.border;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 96,
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '+91',
                style: TextStyle(fontSize: 18, color: AppColors.heading),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Focus(
                onFocusChange: (value) => setState(() => focused = value),
                child: TextField(
                  controller: widget.controller,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: const [_IndianPhoneFormatter()],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: AppColors.heading,
                  ),
                  decoration: InputDecoration(
                    hintText: '00000 00000',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: borderColor, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.error!,
            style: const TextStyle(color: AppColors.error, fontSize: 15),
          ),
        ],
      ],
    );
  }
}

class _IndianPhoneFormatter extends TextInputFormatter {
  const _IndianPhoneFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text
        .replaceAll(RegExp(r'\D'), '')
        .substring(
          0,
          newValue.text.replaceAll(RegExp(r'\D'), '').length.clamp(0, 10),
        );
    final formatted = digits.length <= 5
        ? digits
        : '${digits.substring(0, 5)} ${digits.substring(5)}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class ApprovedOtpInput extends StatefulWidget {
  const ApprovedOtpInput({
    required this.controller,
    super.key,
    this.error,
    this.enabled = true,
    this.onComplete,
  });

  final TextEditingController controller;
  final String? error;
  final bool enabled;
  final ValueChanged<String>? onComplete;

  @override
  State<ApprovedOtpInput> createState() => _ApprovedOtpInputState();
}

class _ApprovedOtpInputState extends State<ApprovedOtpInput> {
  final focusNode = FocusNode();
  bool focused = false;
  String? completedCode;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    focusNode.addListener(_focusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    focusNode
      ..removeListener(_focusChanged)
      ..dispose();
    super.dispose();
  }

  void _focusChanged() => setState(() => focused = focusNode.hasFocus);

  void _changed() {
    setState(() {});
    final code = widget.controller.text;
    if (code.length == 6 && completedCode != code) {
      completedCode = code;
      widget.onComplete?.call(code);
    } else if (code.length < 6) {
      completedCode = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: focusNode.requestFocus,
          child: Stack(
            children: [
              Row(
                children: List.generate(6, (index) {
                  final digit = index < code.length ? code[index] : '';
                  final isCurrent = focused && index == code.length.clamp(0, 5);
                  final hasError = widget.error != null;
                  return Expanded(
                    child: Container(
                      key: ValueKey('otp-digit-$index'),
                      height: 60,
                      margin: EdgeInsets.only(right: index == 5 ? 0 : 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hasError
                            ? AppColors.errorSoft
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasError
                              ? AppColors.error
                              : isCurrent
                              ? AppColors.primary
                              : AppColors.border,
                          width: hasError || isCurrent ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        digit,
                        style: const TextStyle(
                          color: AppColors.heading,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0.01,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: focusNode,
                    enabled: widget.enabled,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              widget.error!,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.uri});

  final String label;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
