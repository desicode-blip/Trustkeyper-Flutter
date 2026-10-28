import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/agreement_filler.dart';
import '../data/agreement_templates.dart';
import '../data/property_onboarding.dart';

const _yellow = Color(0xFFFFE27A);
const _green = Color(0xFFBFEAD2);
const _grey = Color(0xFFE3E8EF);

/// The real agreement words (from the template) filled with what we know.
/// Yellow = told to us, green = just changed, grey = still empty.
class TemplatePaper extends StatelessWidget {
  const TemplatePaper({super.key, required this.item, required this.template, required this.changed, required this.fallback});

  final PropertyOnboarding item;
  final AgreementTemplate template;
  final Set<String> changed;

  /// Shown while loading, or if the template cannot be read.
  final Widget Function() fallback;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: AgreementFiller.load(template),
      builder: (context, snap) {
        if (snap.hasError) return fallback();
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        final filled = AgreementFiller.fill(snap.data!, item, template);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (filled.missing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showMissing(context, filled.missing),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFFF1F4F8), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18, color: AppColors.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${filled.missing.length} details are still empty (grey). We will ask for them.',
                            style: const TextStyle(fontSize: 13.5, height: 18 / 13.5, color: AppColors.muted),
                          ),
                        ),
                        const Text('See', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
                      ],
                    ),
                  ),
                ),
              ),
            for (final line in filled.lines) _line(line),
          ],
        );
      },
    );
  }

  TextStyle get _base => const TextStyle(fontSize: 14.5, height: 24 / 14.5, color: Color(0xFF3A4658));

  List<InlineSpan> _spans(List<AgSeg> segs) => [
    for (final s in segs)
      TextSpan(
        text: s.kind == SegKind.gap ? ' ${s.text} ' : s.text,
        style: switch (s.kind) {
          SegKind.plain => TextStyle(fontWeight: s.bold ? FontWeight.w700 : null, fontStyle: s.italic ? FontStyle.italic : null),
          SegKind.filled => TextStyle(
            backgroundColor: s.group != null && changed.contains(s.group) ? _green : _yellow,
            color: AppColors.heading,
            fontWeight: FontWeight.w600,
          ),
          SegKind.gap => const TextStyle(backgroundColor: _grey, color: AppColors.muted, fontSize: 12.5),
        },
      ),
  ];

  Widget _line(AgLine l) {
    switch (l.kind) {
      case AgLineKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text.rich(TextSpan(style: _base.copyWith(fontWeight: FontWeight.w700, color: AppColors.heading), children: _spans(l.segs))),
        );
      case AgLineKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 6),
          child: Text.rich(TextSpan(style: _base, children: [const TextSpan(text: '•  '), ..._spans(l.segs)])),
        );
      case AgLineKind.tableRow:
        return Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in l.cells)
                Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: Text.rich(TextSpan(style: _base.copyWith(fontSize: 13.5, height: 20 / 13.5), children: _spans(c))))),
            ],
          ),
        );
      case AgLineKind.para:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text.rich(TextSpan(style: _base, children: _spans(l.segs))),
        );
    }
  }

  void _showMissing(BuildContext context, List<String> missing) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.7),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            shrinkWrap: true,
            children: [
              const Text('Still empty', style: TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
              const SizedBox(height: 6),
              const Text('We do not ask for these yet. They stay grey until we have them.', style: TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.muted)),
              const SizedBox(height: 12),
              for (final m in missing)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('•  $m', style: const TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.heading))),
            ],
          ),
        ),
      ),
    );
  }
}
