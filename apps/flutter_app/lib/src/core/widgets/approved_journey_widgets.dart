import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../../features/auth/presentation/approved_auth_widgets.dart';

class ApprovedJourneyHeading extends StatelessWidget {
  const ApprovedJourneyHeading({
    required this.title,
    required this.subtitle,
    required this.onBack,
    super.key,
  });
  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (onBack != null) ...[
            ApprovedBackButton(onPressed: onBack!),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.heading,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        subtitle,
        style: const TextStyle(fontSize: 16, color: AppColors.muted),
      ),
      const SizedBox(height: 22),
    ],
  );
}

class ApprovedJourneyAction extends StatelessWidget {
  const ApprovedJourneyAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.purple = false,
    super.key,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool purple;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: purple
                      ? const Color(0xFFF0E9FF)
                      : AppColors.primarySoft,
                ),
                child: Icon(
                  icon,
                  color: purple ? const Color(0xFF8054FF) : AppColors.primary,
                  size: 30,
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
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
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
              const Icon(
                Icons.chevron_right,
                color: AppColors.primary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ApprovedJourneyHelp extends StatelessWidget {
  const ApprovedJourneyHelp({required this.onPressed, super.key});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    onPressed: onPressed,
    icon: const Icon(Icons.phone_outlined, size: 22),
    style: IconButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.heading,
      minimumSize: const Size(48, 48),
      side: const BorderSide(color: AppColors.border),
    ),
    tooltip: 'Request a call from TrustKeyper',
  );
}
