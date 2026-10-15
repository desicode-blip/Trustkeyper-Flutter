import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/approved_auth_widgets.dart';

export 'broker_agreement_steps_screen.dart';

class BrokerStartScreen extends StatelessWidget {
  const BrokerStartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ApprovedAuthScaffold(
      onBack: () => context.pop(),
      bodyPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      footerBorder: false,
      footerPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      footer: Material(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => launchUrl(Uri.parse('tel:+918088516875')),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.phone_outlined,
                    color: AppColors.primaryDark,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Not sure? '),
                        TextSpan(
                          text: 'Call us',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        TextSpan(text: ' – we will help'),
                      ],
                    ),
                    style: TextStyle(fontSize: 16, color: AppColors.body),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What do you want to do?',
            style: TextStyle(
              fontSize: 28,
              height: 34 / 28,
              fontWeight: FontWeight.w700,
              color: AppColors.heading,
            ),
          ),
          const SizedBox(height: 16),
          _AgreementChoice(
            title: 'New agreement',
            subtitle: 'A new tenant is coming to the house',
            badge: 'About 10 minutes',
            asset: 'new-agreement',
            color: AppColors.primaryDark,
            background: AppColors.primarySoft,
            badgeIcon: Icons.schedule,
            onPressed: () => context.push('/broker/agreement/steps'),
          ),
          const SizedBox(height: 16),
          _AgreementChoice(
            title: 'Renew agreement',
            subtitle: 'Same house, same tenant – add more time',
            badge: 'Old details filled for you',
            asset: 'renew-agreement',
            color: const Color(0xFF2FA866),
            background: AppColors.successSoft,
            badgeIcon: Icons.check,
            onPressed: () => context.push('/broker/renew'),
          ),
          const SizedBox(height: 16),
          _AgreementChoice(
            title: 'Only get it signed',
            subtitle: 'You already have the agreement paper',
            badge: 'We arrange stamp paper',
            asset: 'sign-agreement',
            color: const Color(0xFF7A4DFF),
            background: const Color(0xFFF1EAFF),
            badgeIcon: Icons.description_outlined,
            onPressed: () => context.push('/broker/sign-only'),
          ),
        ],
      ),
    );
  }
}

class _AgreementChoice extends StatelessWidget {
  const _AgreementChoice({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.asset,
    required this.color,
    required this.background,
    required this.badgeIcon,
    required this.onPressed,
  });
  final String title;
  final String subtitle;
  final String badge;
  final String asset;
  final Color color;
  final Color background;
  final IconData badgeIcon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  'assets/design/$asset.svg',
                  width: 34,
                  height: 34,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
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
                        fontSize: 21,
                        height: 26 / 21,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 22 / 16,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: asset == 'new-agreement'
                            ? const Color(0xFFEDF1F6)
                            : asset == 'sign-agreement'
                            ? AppColors.primarySoft
                            : background,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(
                            badgeIcon,
                            size: 14,
                            color: asset == 'new-agreement'
                                ? AppColors.muted
                                : asset == 'sign-agreement'
                                ? AppColors.primaryDark
                                : AppColors.success,
                          ),
                          Text(
                            badge,
                            style: TextStyle(
                              fontSize: 13,
                              height: 16 / 13,
                              fontWeight: FontWeight.w600,
                              color: asset == 'new-agreement'
                                  ? AppColors.muted
                                  : asset == 'sign-agreement'
                                  ? AppColors.primaryDark
                                  : AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.chevron_right, color: color, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
