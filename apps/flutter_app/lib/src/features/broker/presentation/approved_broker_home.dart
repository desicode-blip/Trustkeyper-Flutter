import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_brand.dart';
import '../data/broker_repository.dart';
import '../data/broker_updates_repository.dart';
import 'broker_updates_screen.dart';

class ApprovedBrokerHome extends StatelessWidget {
  const ApprovedBrokerHome({
    required this.profile,
    required this.approvalPending,
    required this.onOpenProfile,
    this.updates,
    this.savedDrafts,
    super.key,
  });

  final BrokerProfile profile;
  final bool approvalPending;
  final VoidCallback onOpenProfile;
  final BrokerUpdatesRepository? updates;
  final Widget? savedDrafts;

  void _create(BuildContext context, String route) {
    if (!approvalPending) {
      context.push(route);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Agreement creation unlocks after broker approval.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('broker-home'),
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
    children: [
      Row(
        children: [
          SizedBox.square(
            dimension: 48,
            child: IconButton(
              tooltip: 'Profile',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primarySoft,
                shape: const CircleBorder(),
              ),
              onPressed: onOpenProfile,
              icon: const _HomeIcon('profile', size: 22),
            ),
          ),
          const Expanded(child: Center(child: AppBrand(height: 40))),
          SizedBox.square(
            dimension: 48,
            child: BrokerUpdatesBell(repository: updates),
          ),
        ],
      ),
      const SizedBox(height: 28),
      // Long names shrink instead of wrapping.
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          profile.greetingName == 'there'
              ? 'Namaste'
              : 'Namaste, ${profile.greetingName}',
          maxLines: 1,
          style: const TextStyle(
            color: AppColors.heading,
            fontSize: 30,
            height: 36 / 30,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 28),
      Material(
        color: approvalPending ? AppColors.muted : AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: approvalPending ? null : () => _create(context, '/broker/start'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 18, 22),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    approvalPending
                        ? 'Waiting for approval'
                        : 'Make rent agreement',
                    style: const TextStyle(
                      fontSize: 20,
                      height: 26 / 20,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!approvalPending)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: _HomeIcon('next', size: 20, color: AppColors.primary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _HomeTile(
              icon: 'house',
              label: 'Onboard property',
              onPressed: () => _create(context, '/broker/property'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _HomeTile(
              icon: 'tenants',
              label: 'Add tenant',
              onPressed: () => _create(context, '/broker/start'),
            ),
          ),
        ],
      ),
      ?savedDrafts,
      // With saved drafts the bank prompt lives inside the Continue panel.
      if (!profile.hasBankAccount && savedDrafts == null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            border: Border.all(color: const Color(0xFFF3C98B)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const _HomeCircle(
                'bank',
                background: Colors.white,
                color: Color(0xFF8A4500),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add your bank',
                      style: TextStyle(
                        fontSize: 17,
                        height: 22 / 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.heading,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'So we can send your fees',
                      style: TextStyle(
                        fontSize: 15,
                        height: 20 / 15,
                        color: Color(0xFF8A4500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => context.push('/broker/bank'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF8A4500),
                  side: const BorderSide(color: Color(0xFF8A4500)),
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text(
                  'Add',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      Material(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => launchUrl(Uri.parse('tel:+918088516875')),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                _HomeCircle(
                  'call',
                  size: 40,
                  iconSize: 20,
                  background: Colors.white,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Stuck? '),
                        TextSpan(
                          text: 'Call us',
                          style: TextStyle(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(text: ' – we will help'),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      height: 20 / 16,
                      color: AppColors.body,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                _HomeIcon('next', color: AppColors.muted, size: 20),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _HomeIcon extends StatelessWidget {
  const _HomeIcon(
    this.name, {
    this.color = AppColors.primaryDark,
    this.size = 24,
  });
  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/design/home-$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

class _HomeCircle extends StatelessWidget {
  const _HomeCircle(
    this.icon, {
    this.size = 48,
    this.iconSize = 24,
    this.background = AppColors.primarySoft,
    this.color = AppColors.primaryDark,
  });
  final String icon;
  final double size;
  final double iconSize;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    child: Center(
      child: _HomeIcon(icon, size: iconSize, color: color),
    ),
  );
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final String icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.border),
      borderRadius: BorderRadius.circular(18),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            _HomeIcon(icon, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  height: 22 / 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.heading,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
