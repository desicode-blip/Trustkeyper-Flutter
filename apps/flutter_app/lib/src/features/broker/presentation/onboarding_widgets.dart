import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/presentation/approved_auth_widgets.dart';
import '../data/property_onboarding.dart';

const kHelpPhone = 'tel:+918088516875';

/// One screen of the "Onboard property" journey: back button, title, simple
/// words, content that scrolls, and one big button at the bottom.
class OnbPage extends StatelessWidget {
  const OnbPage({
    required this.title,
    required this.children,
    this.subtitle,
    this.footer = const [],
    this.stepLabel,
    this.progress,
    this.progressTotal = 4,
    this.onBack,
    this.showBack = true,
    this.showCall = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> footer;
  final String? stepLabel;
  final int? progress;
  final int progressTotal;
  final VoidCallback? onBack;
  final bool showBack;
  final bool showCall;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  child: Row(
                    children: [
                      if (showBack) ...[
                        ApprovedBackButton(
                          onPressed:
                              onBack ??
                              () {
                                if (context.canPop()) {
                                  context.pop();
                                } else {
                                  context.go('/broker');
                                }
                              },
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 26,
                            height: 32 / 26,
                            fontWeight: FontWeight.w700,
                            color: AppColors.heading,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 23 / 16,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  children: children,
                ),
                // Soft shadow under the fixed heading: the list slides under it.
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: SizedBox(
                      height: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x1F101828), Color(0x00101828)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (footer.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: footer),
            ),
        ],
      ),
    ),
  );
}

/// Small coloured label: Approved, Waiting, Not clear...
class OnbPill extends StatelessWidget {
  const OnbPill(this.label, this.kind, {this.icon, super.key});
  final String label;

  /// ok · wait · need · info · mute
  final String kind;
  final IconData? icon;

  (Color, Color) get _colors => switch (kind) {
    'ok' => (AppColors.successSoft, AppColors.success),
    'wait' => (AppColors.warningSoft, AppColors.warning),
    'need' => (AppColors.errorSoft, AppColors.error),
    'info' => (AppColors.primarySoft, AppColors.primaryDark),
    _ => (const Color(0xFFEEF1F5), AppColors.muted),
  };

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Coloured message box.
class OnbBanner extends StatelessWidget {
  const OnbBanner(this.text, {this.kind = 'mute', this.icon, super.key});
  final String text;
  final String kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (kind) {
      'ok' => (AppColors.successSoft, AppColors.success),
      'wait' => (AppColors.warningSoft, AppColors.warning),
      'need' => (AppColors.errorSoft, AppColors.error),
      'info' => (AppColors.primarySoft, AppColors.primaryDark),
      _ => (AppColors.surfaceMuted, AppColors.body),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                height: 21 / 15,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A white row with a round icon, a title, small words and something on the right.
class OnbRow extends StatelessWidget {
  const OnbRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tone = 'info',
    this.chevron = true,
    super.key,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String tone;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      'ok' => (AppColors.successSoft, AppColors.success),
      'wait' => (AppColors.warningSoft, AppColors.warning),
      'need' => (AppColors.errorSoft, AppColors.error),
      'mute' => (const Color(0xFFEEF1F5), AppColors.muted),
      _ => (AppColors.primarySoft, AppColors.primaryDark),
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 22, color: foreground),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      height: 22 / 17,
                      fontWeight: FontWeight.w500,
                      color: AppColors.heading,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 19 / 14,
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (chevron && onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: AppColors.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// White box with a thin border that holds rows or key-value lines.
class OnbCard extends StatelessWidget {
  const OnbCard({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.color,
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

class OnbKeyValue extends StatelessWidget {
  const OnbKeyValue(this.label, this.value, {this.last = false, super.key});
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, color: AppColors.muted),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.heading,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The four stages: Papers · Agreement · Signing · Ready.
class OnbStageBar extends StatelessWidget {
  const OnbStageBar(this.current, {super.key});
  final int current;

  static const _names = ['Papers', 'Agreement', 'Signing', 'Ready'];

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            _Dot(index: i, current: current),
            if (i < 3)
              Expanded(
                child: Container(
                  height: 3,
                  color: i < current
                      ? const Color(0xFF2FA866)
                      : AppColors.border,
                ),
              ),
          ],
        ],
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 4; i++)
            SizedBox(
              width: 70,
              child: Text(
                _names[i],
                textAlign: i == 0
                    ? TextAlign.left
                    : i == 3
                    ? TextAlign.right
                    : TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: i == current ? AppColors.primaryDark : AppColors.muted,
                  fontWeight: i == current ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.index, required this.current});
  final int index;
  final int current;

  @override
  Widget build(BuildContext context) {
    final done = index < current;
    final now = index == current;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? const Color(0xFF2FA866)
            : now
            ? AppColors.primary
            : Colors.white,
        border: done || now
            ? null
            : Border.all(color: AppColors.border, width: 1.5),
      ),
      child: done
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: now ? Colors.white : AppColors.muted,
              ),
            ),
    );
  }
}

class OnbTextField extends StatelessWidget {
  const OnbTextField({
    required this.label,
    required this.controller,
    this.error,
    this.hint,
    this.keyboard,
    this.prefix,
    this.maxLines = 1,
    this.onChanged,
    this.formatters,
    this.capitalization = TextCapitalization.none,
    super.key,
  });
  final List<TextInputFormatter>? formatters;
  final TextCapitalization capitalization;
  final String label;
  final TextEditingController controller;
  final String? error;
  final String? hint;
  final TextInputType? keyboard;
  final String? prefix;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboard,
    inputFormatters: formatters,
    maxLines: maxLines,
    onChanged: onChanged,
    textCapitalization: capitalization,
    autocorrect: keyboard != TextInputType.emailAddress,
    style: const TextStyle(fontSize: 17, color: AppColors.heading),
    // Material floating label: sits inside the box, moves up when you type.
    decoration: InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: const TextStyle(fontSize: 17, color: AppColors.muted),
      floatingLabelStyle: const TextStyle(
        fontSize: 15,
        color: AppColors.primaryDark,
      ),
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF98A2B3)),
      prefixText: prefix,
      errorText: error,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    ),
  );
}

/// Outlined (second) button next to the main one.
class OnbSecondaryButton extends StatelessWidget {
  const OnbSecondaryButton({
    required this.label,
    required this.onPressed,
    this.danger = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? AppColors.error : AppColors.primaryDark,
        side: BorderSide(color: danger ? AppColors.error : AppColors.border),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    ),
  );
}

/// Asks "are you sure?" in a bottom sheet. Returns true when the broker says yes.
Future<bool> onbConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String yes,
  String no = 'Cancel',
  bool danger = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                height: 28 / 22,
                fontWeight: FontWeight.w700,
                color: AppColors.heading,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                height: 23 / 16,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: yes,
              backgroundColor: danger ? AppColors.error : null,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 10),
            OnbSecondaryButton(
              label: no,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

/// Big centred message (sent, done, waiting).
class OnbCentered extends StatelessWidget {
  const OnbCentered({
    required this.icon,
    required this.title,
    required this.message,
    this.kind = 'info',
    this.loading = false,
    super.key,
  });
  final IconData icon;
  final String title;
  final String message;
  final String kind;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (kind) {
      'ok' => (AppColors.successSoft, AppColors.success),
      'wait' => (AppColors.warningSoft, AppColors.warning),
      'need' => (AppColors.errorSoft, AppColors.error),
      _ => (AppColors.primarySoft, AppColors.primaryDark),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 48, 8, 0),
      child: Column(
        children: [
          loading
              ? const SizedBox.square(
                  dimension: 64,
                  child: CircularProgressIndicator(strokeWidth: 5),
                )
              : Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 44, color: foreground),
                ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              height: 32 / 26,
              fontWeight: FontWeight.w700,
              color: AppColors.heading,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              height: 25 / 17,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

String onbMoney(num value) {
  final text = value.round().toString();
  if (text.length <= 3) return '₹ $text';
  final last3 = text.substring(text.length - 3);
  var rest = text.substring(0, text.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '₹ ${groups.join(',')},$last3';
}

String paperStatusLabel(PaperStatus status) => switch (status) {
  PaperStatus.waiting => 'Waiting',
  PaperStatus.checking => 'Checking',
  PaperStatus.approved => 'Approved',
  PaperStatus.notClear => 'Send again',
  PaperStatus.needsYou => 'Please check',
  PaperStatus.notNeeded => 'Not needed',
};

String paperStatusKind(PaperStatus status) => switch (status) {
  PaperStatus.waiting => 'mute',
  PaperStatus.checking => 'info',
  PaperStatus.approved => 'ok',
  PaperStatus.notClear => 'need',
  PaperStatus.needsYou => 'wait',
  PaperStatus.notNeeded => 'mute',
};

IconData paperIcon(String key) => switch (key) {
  PaperKeys.aadhaar => Icons.badge_outlined,
  PaperKeys.phone => Icons.smartphone_outlined,
  PaperKeys.email => Icons.mail_outline,
  PaperKeys.tenantAgreement => Icons.description_outlined,
  PaperKeys.rentDeposit => Icons.currency_rupee,
  PaperKeys.bank => Icons.account_balance_outlined,
  PaperKeys.address => Icons.home_outlined,
  PaperKeys.keys => Icons.key_outlined,
  _ => Icons.description_outlined,
};
