import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/theme/app_colors.dart';

class DocumentGlyph extends StatelessWidget {
  const DocumentGlyph(
    this.name, {
    this.color = AppColors.primaryDark,
    this.size = 22,
    super.key,
  });
  final String name;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) {
    final paths = switch (name) {
      'globe' =>
        '<circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10Z"/>',
      'mobile' =>
        '<rect x="5" y="2" width="14" height="20" rx="2"/><path d="M12 18h.01"/>',
      'shield' =>
        '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1Z"/><path d="m9 12 2 2 4-4"/>',
      'building' =>
        '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M9 22v-4h6v4M8 6h.01M16 6h.01M12 6h.01M12 10h.01M12 14h.01M16 10h.01M16 14h.01M8 10h.01M8 14h.01"/>',
      'folder' =>
        '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
      'person' =>
        '<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
      'aadhaar' =>
        '<rect x="2" y="5" width="20" height="14" rx="2"/><circle cx="8" cy="12" r="2"/><path d="M14 10h4M14 14h4"/>',
      'pan' =>
        '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/>',
      'bank' =>
        '<path d="M3 22h18M6 18v-7M10 18v-7M14 18v-7M18 18v-7M12 2 20 7H4z"/>',
      'warning' =>
        '<circle cx="12" cy="12" r="10"/><path d="M12 8v4M12 16h.01"/>',
      'check' => '<path d="M20 6 9 17l-5-5"/>',
      'eye' =>
        '<path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>',
      'sync' =>
        '<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8M21 3v5h-5M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16M8 16H3v5"/>',
      'trash' =>
        '<path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
      'clock' => '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
      'bell' =>
        '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
      'send' => '<path d="m22 2-7 20-4-9-9-4 20-7ZM22 2 11 13"/>',
      'camera' =>
        '<path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3Z"/><circle cx="12" cy="13" r="3"/>',
      'file' =>
        '<path d="m21.4 11.6-9.2 9.2a6 6 0 0 1-8.5-8.5l10-10a4 4 0 0 1 5.7 5.7l-10 10a2 2 0 0 1-2.9-2.9L16 6"/>',
      'pencil' =>
        '<path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/>',
      'linkedin' =>
        '<rect x="2" y="2" width="20" height="20" rx="3"/><path d="M7 10v7M7 7h.01M11 17v-7M11 13a3 3 0 0 1 6 0v4"/>',
      'upload' =>
        '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4m14-7-5-5-5 5M12 3v12"/>',
      'whatsapp' => '<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>',
      'sms' =>
        '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2Z"/>',
      'email' =>
        '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-10 6L2 7"/>',
      _ => '<path d="M9 18 3 12l6-6M3 12h18"/>',
    };
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">$paths</svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

class DocumentRoundAction extends StatelessWidget {
  const DocumentRoundAction({
    required this.glyph,
    required this.label,
    required this.onTap,
    this.green = false,
    this.red = false,
    this.cooling = false,
    this.width = 60,
    super.key,
  });
  final String glyph;
  final String label;
  final VoidCallback? onTap;
  final bool green;
  final bool red;
  final bool cooling;
  final double width;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    enabled: onTap != null,
    onTap: onTap,
    child: ExcludeSemantics(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  tooltip: label,
                  onPressed: onTap,
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: cooling
                        ? const Color(0xFFF1F4F8)
                        : red
                        ? AppColors.errorSoft
                        : green
                        ? AppColors.successSoft
                        : AppColors.primarySoft,
                  ),
                  icon: DocumentGlyph(
                    glyph,
                    size: 20,
                    color: cooling
                        ? const Color(0xFF9AA7B8)
                        : red
                        ? AppColors.error
                        : green
                        ? AppColors.success
                        : AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.muted,
                  height: 15 / 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class DocumentDashedBorder extends StatelessWidget {
  const DocumentDashedBorder({
    required this.child,
    this.enabled = true,
    super.key,
  });
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: enabled ? _DocumentBorderPainter() : null,
    child: child,
  );
}

class _DocumentBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      );
    final paint = Paint()
      ..color = const Color(0xFF9FB3D9)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 7) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + 4).clamp(0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DocumentNote extends StatelessWidget {
  const DocumentNote(this.text, {this.icon = Icons.lock_outline, super.key});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.muted, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.muted,
              height: 19 / 14,
            ),
          ),
        ),
      ],
    ),
  );
}
