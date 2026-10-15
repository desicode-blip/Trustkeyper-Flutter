import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/approved_auth_widgets.dart';

class BrokerAgreementStepsScreen extends StatelessWidget {
  const BrokerAgreementStepsScreen({super.key});

  @override
  Widget build(BuildContext context) => ApprovedAuthScaffold(
    showBack: false,
    header: Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _HeaderAction(
            label: 'Go back',
            asset: 'back',
            size: 22,
            onPressed: () => context.pop(),
          ),
          _HeaderAction(
            label: 'Call TrustKeyper for help',
            asset: 'call',
            size: 20,
            onPressed: () => launchUrl(Uri.parse('tel:+918088516875')),
          ),
        ],
      ),
    ),
    bodyPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    footerBorder: false,
    footer: Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: () => context.push('/broker/property'),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Flexible(
              child: Text("Let's start", textAlign: TextAlign.center),
            ),
            const SizedBox(width: 10),
            _StepsIcon('next', color: Colors.white, size: 22),
          ],
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            Positioned(
              right: 12,
              top: -2,
              child: Transform.rotate(
                angle: math.pi / 15,
                child: _StepsIcon(
                  'sparkle',
                  color: const Color(0xFFFFB020),
                  size: 26,
                ),
              ),
            ),
            Positioned(
              right: 54,
              top: 36,
              child: Opacity(
                opacity: 0.6,
                child: _StepsIcon(
                  'sparkle',
                  color: const Color(0xFF7A4DFF),
                  size: 14,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 300),
                    child: const Text(
                      "Let's make a rent agreement!",
                      style: TextStyle(
                        fontSize: 30,
                        height: 36 / 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _IntroBadge(
                        label: '5 easy steps',
                        asset: 'check',
                        color: AppColors.primaryDark,
                        background: AppColors.primarySoft,
                      ),
                      _IntroBadge(
                        label: 'About 10 min',
                        asset: 'clock',
                        color: Color(0xFFB45309),
                        background: Color(0xFFFFF1E3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const _StepTimeline(),
      ],
    ),
  );
}

class _StepsIcon extends StatelessWidget {
  const _StepsIcon(this.asset, {required this.color, required this.size});
  final String asset;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/design/steps-$asset.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.label,
    required this.asset,
    required this.size,
    required this.onPressed,
  });
  final String label;
  final String asset;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: AppColors.heading.withValues(alpha: 0.1),
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: _StepsIcon(asset, color: AppColors.heading, size: size),
          ),
        ),
      ),
    ),
  );
}

class _IntroBadge extends StatelessWidget {
  const _IntroBadge({
    required this.label,
    required this.asset,
    required this.color,
    required this.background,
  });
  final String label;
  final String asset;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 32),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepsIcon(asset, color: color, size: 15),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

class _StepTimeline extends StatelessWidget {
  const _StepTimeline();
  static const steps = [
    (
      'Property Details',
      'Pick or add the house',
      'property',
      AppColors.primary,
      AppColors.primarySoft,
    ),
    (
      'Owner & Tenant Details',
      'Names and numbers',
      'people',
      Color(0xFF7A4DFF),
      Color(0xFFF1EAFF),
    ),
    (
      'Documents',
      'Aadhaar, PAN, bank',
      'documents',
      Color(0xFFD86A10),
      Color(0xFFFFF1E3),
    ),
    (
      'Rent Details',
      'Rent, deposit, dates',
      'rent',
      Color(0xFF0F8A72),
      Color(0xFFE3F7F3),
    ),
    (
      'Brokerage details',
      '',
      'brokerage',
      Color(0xFFC93B78),
      Color(0xFFFDEBF3),
    ),
  ];
  static const titleStyle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 18,
    height: 22 / 18,
    fontWeight: FontWeight.w700,
    color: AppColors.heading,
  );
  static const subtitleStyle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 14.5,
    height: 18 / 14.5,
    color: AppColors.muted,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final textWidth = constraints.maxWidth - 98;
      double measuredHeight(String label, TextStyle style) {
        if (label.isEmpty) return 0;
        final painter = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: textWidth);
        final height = painter.height;
        painter.dispose();
        return height;
      }

      var pitch = 92.0;
      for (final step in steps) {
        pitch = math.max(
          pitch,
          measuredHeight(step.$1, titleStyle) +
              measuredHeight(step.$2, subtitleStyle) +
              16,
        );
      }
      final finishTop = pitch * 4 + 110;
      final finishHeight = math.max(96.0, 62 + scaler.scale(34));
      return SizedBox(
        height: finishTop + finishHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(painter: _TimelinePainter(pitch: pitch)),
              ),
            ),
            for (var index = 0; index < steps.length; index++) ...[
              Positioned(
                top: pitch * index,
                left: index.isEven ? 14 : null,
                right: index.isOdd ? 14 : null,
                child: _StageIcon(index: index),
              ),
              Positioned(
                top: pitch * index + 6,
                left: index.isEven ? 84 : 14,
                right: index.isOdd ? 84 : 14,
                child: Column(
                  crossAxisAlignment: index.isEven
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.end,
                  children: [
                    Text(
                      steps[index].$1,
                      style: titleStyle,
                      textAlign: index.isEven
                          ? TextAlign.left
                          : TextAlign.right,
                    ),
                    if (steps[index].$2.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        steps[index].$2,
                        style: subtitleStyle,
                        textAlign: index.isEven
                            ? TextAlign.left
                            : TextAlign.right,
                      ),
                    ],
                  ],
                ),
              ),
            ],
            Positioned(
              left: 0,
              right: 0,
              top: finishTop,
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: AppColors.heading,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.white, spreadRadius: 5),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const _StepsIcon(
                      'review',
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Then review & send',
                    style: TextStyle(
                      fontSize: 16,
                      height: 19 / 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Check & send to sign',
                    style: TextStyle(
                      fontSize: 14,
                      height: 17 / 14,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _StageIcon extends StatelessWidget {
  const _StageIcon({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final step = _StepTimeline.steps[index];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: step.$5,
            shape: BoxShape.circle,
            boxShadow: const [BoxShadow(color: Colors.white, spreadRadius: 5)],
          ),
          alignment: Alignment.center,
          child: _StepsIcon(step.$3, color: step.$4, size: 26),
        ),
        Positioned(
          right: -4,
          top: -4,
          child: ExcludeSemantics(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: step.$4,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(color: Colors.white, spreadRadius: 3),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({required this.pitch});
  final double pitch;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(44, 30);
    for (var index = 0; index < 4; index++) {
      final start = Offset(
        index.isEven ? 44 : size.width - 44,
        index * pitch + 30,
      );
      final end = Offset(
        index.isEven ? size.width - 44 : 44,
        (index + 1) * pitch + 30,
      );
      path.cubicTo(
        start.dx,
        start.dy + pitch / 2,
        end.dx,
        end.dy - pitch / 2,
        end.dx,
        end.dy,
      );
    }
    final lastTop = pitch * 4 + 30;
    path.cubicTo(
      44,
      lastTop + 53,
      size.width / 2,
      lastTop + 53,
      size.width / 2,
      lastTop + 106,
    );
    final paint = Paint()
      ..color = const Color(0xFFC9D6F2)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 10) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 1, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) =>
      oldDelegate.pitch != pitch;
}
