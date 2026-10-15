import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

class TkPage extends StatelessWidget {
  const TkPage({
    required this.child,
    this.title,
    this.subtitle,
    this.step,
    this.onBack,
    this.showHelp = false,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(24, 12, 24, 24),
    this.scrollController,
    this.titleStyle,
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final String? step;
  final VoidCallback? onBack;
  final bool showHelp;
  final Widget? bottom;
  final EdgeInsets padding;
  final ScrollController? scrollController;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            if (step != null || onBack != null || showHelp)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    if (onBack != null)
                      IconButton(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'Go back',
                      )
                    else
                      const SizedBox(width: 48),
                    if (step != null)
                      Expanded(
                        child: Text(
                          step!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    if (showHelp)
                      IconButton.filledTonal(
                        onPressed: () => showHelpSheet(context),
                        icon: const Icon(Icons.call_outlined),
                        tooltip: 'Call TrustKeyper for help',
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                controller: scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: padding,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style:
                          titleStyle ??
                          Theme.of(context).textTheme.displaySmall,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                  child,
                  SizedBox(height: bottom == null ? 12 : 96),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: bottom,
              ),
            ),
    );
  }

  static void showHelpSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Call TrustKeyper',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            const Text('We are available every day, 9 am to 8 pm.'),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.call_outlined)),
              title: const Text('+91 80885 16875'),
              subtitle: const Text('Tap to call'),
              onTap: () async {
                final uri = Uri.parse('tel:+918088516875');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.chat_outlined)),
              title: const Text('WhatsApp TrustKeyper'),
              subtitle: const Text('Open support chat'),
              onTap: () async {
                final uri = Uri.parse('https://wa.me/918088516875');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class TkProgress extends StatelessWidget {
  const TkProgress({required this.value, super.key});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 6,
        backgroundColor: AppColors.primaryBorder,
        color: AppColors.primary,
      ),
    );
  }
}

class TkPrimaryButton extends StatelessWidget {
  const TkPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class TkChoiceCard extends StatelessWidget {
  const TkChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.onTap,
    this.selected = false,
    this.color,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback? onTap;
  final bool selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.primary : AppColors.heading;
    return Material(
      color: color ?? (selected ? AppColors.primarySoft : AppColors.background),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(icon, color: AppColors.primaryDark),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (badge != null) TkPill(label: badge!),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(subtitle),
                  ],
                ),
              ),
              if (onTap != null)
                const Padding(
                  padding: EdgeInsets.only(top: 13),
                  child: Icon(Icons.chevron_right_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TkPill extends StatelessWidget {
  const TkPill({
    required this.label,
    this.color = AppColors.primarySoft,
    this.foreground = AppColors.primaryDark,
    super.key,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class TkStatusRow extends StatelessWidget {
  const TkStatusRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.done = false,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: done ? AppColors.successSoft : AppColors.primarySoft,
        child: Icon(
          done ? Icons.check_rounded : icon,
          color: done ? AppColors.success : AppColors.primaryDark,
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(detail),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
    );
  }
}

class TkAmount extends StatelessWidget {
  const TkAmount({
    required this.label,
    required this.amount,
    required this.words,
    super.key,
  });

  final String label;
  final String amount;
  final String words;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(
            amount,
            style: const TextStyle(
              color: AppColors.heading,
              fontWeight: FontWeight.w700,
              fontSize: 26,
            ),
          ),
          const SizedBox(height: 2),
          Text(words, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}
