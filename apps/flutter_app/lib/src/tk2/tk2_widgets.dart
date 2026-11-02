import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/app_colors.dart';
import 'tk2_store.dart';

// Shared pieces for TrustKeeper 2: calm cards, soft pills, gentle motion.

const tk2Green = Color(0xFF2FA866);

/// Fades and slides a child in, a little later for each index (list entry).
class Tk2Appear extends StatelessWidget {
  const Tk2Appear({required this.child, this.index = 0, super.key});
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 380 + 70 * index.clamp(0, 6)),
    curve: Curves.easeOutCubic,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child),
    ),
    child: child,
  );
}

/// Small rounded label.
class Tk2Pill extends StatelessWidget {
  const Tk2Pill(this.text, {this.kind = 'mute', this.icon, super.key});
  final String text;

  /// ok · wait · need · info · mute · dark
  final String kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (kind) {
      'ok' => (AppColors.successSoft, AppColors.success),
      'wait' => (AppColors.warningSoft, AppColors.warning),
      'need' => (AppColors.errorSoft, AppColors.error),
      'info' => (AppColors.primarySoft, AppColors.primaryDark),
      'dark' => (const Color(0xCC172231), Colors.white),
      _ => (const Color(0xFFEEF1F5), AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
          ),
        ],
      ),
    );
  }
}

/// The property photo, or a soft illustration when there is none.
class Tk2Photo extends StatelessWidget {
  const Tk2Photo({required this.listing, this.height = 170, this.index = 0, this.radius = 20, super.key});
  final Tk2Listing listing;
  final double height;
  final int index;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = index < listing.photos.length ? listing.photos[index] : null;
    final file = path == null ? null : File(path);
    Widget fallback() => Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF0FF), Color(0xFFDCE5F6)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.home_work_outlined, size: 32, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 8),
            Text(listing.property.rooms, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
          ],
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: file != null && file.existsSync()
            ? Image.file(file, fit: BoxFit.cover, errorBuilder: (context, error, stack) => fallback())
            : fallback(),
      ),
    );
  }
}

/// WhatsApp logo (from the shared design assets).
Widget tk2WhatsAppLogo({double size = 20}) => SvgPicture.asset('assets/design/whatsapp.svg', width: size, height: size);

String tk2Initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String tk2Day(DateTime d, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(d);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

String tk2Time(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'am' : 'pm'}';
}

String tk2Date(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return 'Now';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// One clear property card for the home shelf.
class Tk2PropertyCard extends StatelessWidget {
  const Tk2PropertyCard({required this.listing, required this.onOpen, required this.onShare, required this.onCustomerView, this.visits = 0, super.key});
  final Tk2Listing listing;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onCustomerView;
  final int visits;

  @override
  Widget build(BuildContext context) {
    final p = listing.property;
    final facts = [
      p.rooms,
      if (p.furnishing.isNotEmpty) p.furnishing == 'Empty' ? 'Unfurnished' : '${p.furnishing}-furnished',
      if (p.sizeSqFt != null) '${p.sizeSqFt!.toStringAsFixed(0)} sq ft',
    ];
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Hero(tag: 'photo-${listing.id}', child: Tk2Photo(listing: listing)),
                  if (listing.sample) const Positioned(left: 10, top: 10, child: Tk2Pill('Example', kind: 'dark')),
                  if (visits > 0)
                    Positioned(right: 10, top: 10, child: Tk2Pill('$visits visit${visits == 1 ? '' : 's'}', kind: 'ok', icon: Icons.event_available)),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 14, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(listing.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, height: 24 / 19, fontWeight: FontWeight.w700, color: AppColors.heading)),
                    if (p.address.trim().isNotEmpty && p.address.trim() != listing.name) ...[
                      const SizedBox(height: 2),
                      Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, color: AppColors.muted)),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(listing.hasRent ? Tk2Store.money(listing.rent) : 'Add rent', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: listing.hasRent ? AppColors.heading : AppColors.primaryDark)),
                        if (listing.hasRent) const Padding(padding: EdgeInsets.only(left: 4, bottom: 2), child: Text('/ month', style: TextStyle(fontSize: 14, color: AppColors.muted))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final f in facts) Tk2Pill(f)]),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: FilledButton.icon(
                              onPressed: onShare,
                              icon: tk2WhatsAppLogo(size: 18),
                              label: const Text('Share'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.successSoft,
                                foregroundColor: AppColors.success,
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton.icon(
                              onPressed: onCustomerView,
                              icon: const Icon(Icons.visibility_outlined, size: 18),
                              label: const Text('Customer view'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryDark,
                                side: const BorderSide(color: AppColors.border),
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
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
      ),
    );
  }
}

/// A green tick that pops in (success screens).
class Tk2SuccessTick extends StatelessWidget {
  const Tk2SuccessTick({super.key});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.6, end: 1),
    duration: const Duration(milliseconds: 420),
    curve: Curves.elasticOut,
    builder: (context, v, child) => Transform.scale(scale: v, child: child),
    child: Container(
      width: 104,
      height: 104,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.successSoft, shape: BoxShape.circle),
      child: Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(color: tk2Green, shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 40, color: Colors.white),
      ),
    ),
  );
}

/// Page heading used by TrustKeeper 2 screens.
class Tk2Title extends StatelessWidget {
  const Tk2Title(this.title, {this.subtitle, super.key});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 28, height: 34 / 28, fontWeight: FontWeight.w700, color: AppColors.heading)),
      if (subtitle != null) ...[
        const SizedBox(height: 6),
        Text(subtitle!, style: const TextStyle(fontSize: 16.5, height: 23 / 16.5, color: AppColors.muted)),
      ],
    ],
  );
}
