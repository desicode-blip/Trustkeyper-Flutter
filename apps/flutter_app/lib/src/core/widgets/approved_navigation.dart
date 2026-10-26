import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';

class ApprovedBrokerNavigation extends StatelessWidget {
  const ApprovedBrokerNavigation({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  static const labels = [
    'Home',
    'Agreements',
    'Records',
    'Payments',
    'Profile',
  ];

  @override
  Widget build(BuildContext context) {
    // Floating pill: 76px tall, 12px side margin, 8px inner padding. The
    // selected item is its own soft-blue pill, inset from the outer border.
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        height: 76,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(38),
          border: Border.all(color: const Color(0xFFEEF2F8)),
          boxShadow: [
            BoxShadow(
              color: AppColors.heading.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(labels.length, (index) {
            final selected = index == selectedIndex;
            final color = selected ? AppColors.primaryDark : AppColors.muted;
            return Semantics(
              selected: selected,
              button: true,
              child: Material(
                color: selected ? AppColors.primarySoft : Colors.transparent,
                borderRadius: BorderRadius.circular(26),
                child: InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: () => onSelected(index),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: selected ? 14 : 8,
                      vertical: 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          'assets/design/nav-${labels[index].toLowerCase()}.svg',
                          width: 24,
                          height: 24,
                          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          labels[index],
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 12,
                            height: 16 / 12,
                            color: color,
                            fontWeight: selected
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
