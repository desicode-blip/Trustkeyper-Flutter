import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_brand.dart';
import 'login_method.dart';

class ApprovedLoginHero extends StatelessWidget {
  const ApprovedLoginHero({super.key, this.onBack});

  /// Shows the standard back button at the top-left when provided.
  final VoidCallback? onBack;

  // left, width, height, wall colour, door colour (design units out of 440).
  static const _buildings = [
    (14.0, 78.0, 84.0, 0xFF9DB8FF, 0xFF5F82E8),
    (104.0, 92.0, 118.0, 0xFF8FDDB0, 0xFF3FA574),
    (232.0, 82.0, 96.0, 0xFFFFC48A, 0xFFE58A3A),
    (326.0, 100.0, 76.0, 0xFFC3AEFF, 0xFF8A66F0),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFD9E6FF), Color(0xFFFFF1E0)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final unit = constraints.maxWidth / 440;
          return Stack(
            children: [
              Positioned(
                right: 30 * unit,
                top: 16,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFD36B),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              for (final cloud in [(40.0, 22.0, 54.0), (300.0, 52.0, 44.0)])
                Positioned(
                  left: cloud.$1 * unit,
                  top: cloud.$2,
                  child: Container(
                    width: cloud.$3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              for (final b in _buildings)
                Positioned(
                  left: b.$1 * unit,
                  width: b.$2 * unit,
                  height: b.$3,
                  bottom: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Color(b.$4),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            for (var i = 0; i < 4; i++)
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 18,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Color(b.$5),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 6,
                child: ColoredBox(color: Color(0xFF7FD1A5)),
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
              if (onBack != null)
                Positioned(
                  left: 24,
                  top: 14,
                  child: ApprovedBackButton(onPressed: onBack!),
                ),
            ],
          );
        },
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
    this.dialCode = '+91',
    this.onDialCodeChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? error;

  /// Country calling code, e.g. "+91". Any code can be picked or typed.
  final String dialCode;
  final ValueChanged<String>? onDialCodeChanged;

  @override
  State<ApprovedPhoneField> createState() => _ApprovedPhoneFieldState();
}

/// A country for the phone field.
class PhoneCountry {
  const PhoneCountry(this.name, this.code, this.flag);
  final String name;
  final String code;
  final String flag;

  static const all = [
    PhoneCountry('India', '+91', '🇮🇳'),
    PhoneCountry('United Arab Emirates', '+971', '🇦🇪'),
    PhoneCountry('United States', '+1', '🇺🇸'),
    PhoneCountry('United Kingdom', '+44', '🇬🇧'),
    PhoneCountry('Canada', '+1', '🇨🇦'),
    PhoneCountry('Australia', '+61', '🇦🇺'),
    PhoneCountry('Singapore', '+65', '🇸🇬'),
    PhoneCountry('Saudi Arabia', '+966', '🇸🇦'),
    PhoneCountry('Qatar', '+974', '🇶🇦'),
    PhoneCountry('Kuwait', '+965', '🇰🇼'),
    PhoneCountry('Oman', '+968', '🇴🇲'),
    PhoneCountry('Bahrain', '+973', '🇧🇭'),
    PhoneCountry('Germany', '+49', '🇩🇪'),
    PhoneCountry('France', '+33', '🇫🇷'),
    PhoneCountry('Netherlands', '+31', '🇳🇱'),
    PhoneCountry('Ireland', '+353', '🇮🇪'),
    PhoneCountry('Switzerland', '+41', '🇨🇭'),
    PhoneCountry('Sweden', '+46', '🇸🇪'),
    PhoneCountry('Italy', '+39', '🇮🇹'),
    PhoneCountry('Spain', '+34', '🇪🇸'),
    PhoneCountry('New Zealand', '+64', '🇳🇿'),
    PhoneCountry('Malaysia', '+60', '🇲🇾'),
    PhoneCountry('Japan', '+81', '🇯🇵'),
    PhoneCountry('Hong Kong', '+852', '🇭🇰'),
    PhoneCountry('South Africa', '+27', '🇿🇦'),
    PhoneCountry('Kenya', '+254', '🇰🇪'),
    PhoneCountry('Nepal', '+977', '🇳🇵'),
    PhoneCountry('Sri Lanka', '+94', '🇱🇰'),
    PhoneCountry('Bangladesh', '+880', '🇧🇩'),
  ];

  static String flagFor(String code) =>
      all.where((c) => c.code == code).firstOrNull?.flag ?? '🌐';

  /// India needs 10 digits; other countries 6 to 14.
  static bool valid(String code, String digits) =>
      code == '+91' ? digits.length == 10 : digits.length >= 6 && digits.length <= 14;

  /// "+91 98765 43210" style, for showing and saving.
  static String format(String code, String digits) => code == '+91' && digits.length == 10
      ? '+91 ${digits.substring(0, 5)} ${digits.substring(5)}'
      : '$code $digits';
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
    final phone = selected == LoginMethod.phone;
    // Only the white thumb slides; nothing else on the screen moves.
    return Container(
      key: const ValueKey('auth-method-selector'),
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: const ShapeDecoration(
        color: AppColors.surfaceMuted,
        shape: StadiumBorder(),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: phone ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.heading.withValues(alpha: 0.10),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              _MethodButton(
                icon: Icons.phone_outlined,
                label: 'Phone',
                selected: phone,
                onPressed: enabled ? () => onChanged(LoginMethod.phone) : null,
              ),
              _MethodButton(
                icon: Icons.mail_outline,
                label: 'Email',
                selected: !phone,
                onPressed: enabled ? () => onChanged(LoginMethod.email) : null,
              ),
            ],
          ),
        ],
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
    final color = selected ? AppColors.primaryDark : AppColors.muted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          key: ValueKey('auth-method-${label.toLowerCase()}'),
          borderRadius: BorderRadius.circular(22),
          onTap: onPressed,
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Swaps the phone and email fields with a quick fade; the rest stays still.
class AuthFieldSwitcher extends StatelessWidget {
  const AuthFieldSwitcher({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
    alignment: Alignment.topCenter,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Only the new field is shown; it fades in.
      layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
      child: child,
    ),
  );
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
  late String dial = widget.dialCode;

  @override
  void didUpdateWidget(covariant ApprovedPhoneField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dialCode != widget.dialCode) dial = widget.dialCode;
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => _CountrySheet(current: dial),
    );
    if (picked == null || !mounted) return;
    setState(() => dial = picked);
    // Re-format what is typed for the new country.
    final digits = widget.controller.text.replaceAll(RegExp(r'\D'), '');
    widget.controller.text = _PhoneFormatter(dial).format(digits);
    widget.onDialCodeChanged?.call(picked);
  }

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
            Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppColors.border),
              ),
              child: InkWell(
                key: const ValueKey('phone-country'),
                borderRadius: BorderRadius.circular(10),
                onTap: widget.enabled ? _pickCountry : null,
                child: Container(
                  height: 60,
                  padding: const EdgeInsets.only(left: 12, right: 6),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(PhoneCountry.flagFor(dial), style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(dial, style: const TextStyle(fontSize: 18, color: AppColors.heading)),
                      const Icon(Icons.arrow_drop_down, color: AppColors.muted),
                    ],
                  ),
                ),
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
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [_PhoneFormatter(dial)],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: AppColors.heading,
                  ),
                  decoration: InputDecoration(
                    hintText: dial == '+91' ? '00000 00000' : 'Phone number',
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

/// Country list with search; any other code can be typed at the top.
class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.current});
  final String current;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  final query = TextEditingController();

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = query.text.trim().toLowerCase();
    final typedCode = RegExp(r'^\+?\d{1,4}$').hasMatch(q) ? '+${q.replaceAll('+', '')}' : null;
    final list = PhoneCountry.all
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.code.contains(q.replaceAll('+', '')))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text('Country code', style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: query,
                autofocus: false,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search country or type a code',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (typedCode != null && !PhoneCountry.all.any((c) => c.code == typedCode))
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      leading: const Text('🌐', style: TextStyle(fontSize: 22)),
                      title: Text('Use $typedCode'),
                      onTap: () => Navigator.pop(context, typedCode),
                    ),
                  for (final c in list)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                      title: Text(c.name, style: const TextStyle(fontSize: 16, color: AppColors.heading)),
                      trailing: Text(
                        c.code,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.code == widget.current ? AppColors.primary : AppColors.muted,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, c.code),
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

/// India: "98765 43210" (10 digits). Others: digits only, up to 14.
class _PhoneFormatter extends TextInputFormatter {
  const _PhoneFormatter(this.dial);
  final String dial;

  String format(String raw) {
    final max = dial == '+91' ? 10 : 14;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final cut = digits.substring(0, digits.length.clamp(0, max));
    if (dial != '+91' || cut.length <= 5) return cut;
    return '${cut.substring(0, 5)} ${cut.substring(5)}';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = format(newValue.text);
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
