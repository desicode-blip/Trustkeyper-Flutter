import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../document_requests/presentation/document_request_widgets.dart';

class PaperPartyTabs extends StatefulWidget {
  const PaperPartyTabs({
    required this.owner,
    required this.count,
    required this.selected,
    required this.onSelected,
    super.key,
  });
  final bool owner;
  final int count, selected;
  final ValueChanged<int>? onSelected;
  @override
  State<PaperPartyTabs> createState() => _PaperPartyTabsState();
}

class _PaperPartyTabsState extends State<PaperPartyTabs> {
  final ScrollController controller = ScrollController();
  double? centeredOffset;

  TextStyle labelStyle(bool selected) => TextStyle(
    fontSize: selected ? 18 : 14,
    letterSpacing: 0,
    height: selected ? 22 / 18 : 18 / 14,
    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    color: selected ? Colors.white : const Color(0xFF8391A5),
  );

  double chipWidth(BuildContext context, int index) {
    final selected = index == widget.selected;
    final painter = TextPainter(
      text: TextSpan(
        text: '${widget.owner ? 'Owner' : 'Tenant'} ${index + 1}',
        style: DefaultTextStyle.of(context).style.merge(labelStyle(selected)),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final naturalWidth = painter.width.ceilToDouble() + (selected ? 78 : 48);
    painter.dispose();
    final minimum = selected
        ? (widget.owner ? 144.0 : 156.0)
        : (widget.owner ? 100.0 : 110.0);
    return naturalWidth < minimum ? minimum : naturalWidth;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final widths = List.generate(
          widget.count,
          (index) => chipWidth(context, index),
        );
        final totalWidth =
            widths.fold<double>(0, (total, width) => total + width) +
            (widget.count - 1) * 10;
        final fitsNarrowScreen =
            constraints.maxWidth < 350 && totalWidth <= constraints.maxWidth;
        final offset = fitsNarrowScreen
            ? 0.0
            : widths
                  .take(widget.selected)
                  .fold<double>(0, (total, width) => total + width + 10);
        if (centeredOffset != offset) {
          centeredOffset = offset;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !controller.hasClients) return;
            controller.jumpTo(
              offset.clamp(0.0, controller.position.maxScrollExtent),
            );
          });
        }
        return SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.symmetric(
            horizontal:
                ((constraints.maxWidth -
                            (fitsNarrowScreen
                                ? totalWidth
                                : widths[widget.selected])) /
                        2)
                    .clamp(0.0, double.infinity),
          ),
          child: Row(
            children: [
              for (var index = 0; index < widget.count; index++) ...[
                if (index > 0) const SizedBox(width: 10),
                Semantics(
                  button: true,
                  selected: index == widget.selected,
                  enabled: widget.onSelected != null,
                  label:
                      '${widget.owner ? 'Owner' : 'Tenant'} ${index + 1}${index == widget.selected ? ' of ${widget.count}' : ''}',
                  excludeSemantics: true,
                  onTap: widget.onSelected == null
                      ? null
                      : () => widget.onSelected!(index),
                  child: InkWell(
                    onTap: widget.onSelected == null
                        ? null
                        : () => widget.onSelected!(index),
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      width: widths[index],
                      height: index == widget.selected ? 56 : 36,
                      padding: index == widget.selected
                          ? const EdgeInsets.fromLTRB(8, 0, 20, 0)
                          : const EdgeInsets.fromLTRB(6, 6, 12, 6),
                      decoration: BoxDecoration(
                        color: index == widget.selected
                            ? AppColors.primary
                            : const Color(0xFFF1F4F8),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: index == widget.selected
                            ? [
                                const BoxShadow(
                                  color: Color(0x473160FF),
                                  blurRadius: 16,
                                  offset: Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: index == widget.selected ? 20 : 12,
                            backgroundColor: Colors.white,
                            child: DocumentGlyph(
                              'person',
                              size: index == widget.selected ? 22 : 14,
                              color: index == widget.selected
                                  ? AppColors.primaryDark
                                  : const Color(0xFFA7B3C3),
                            ),
                          ),
                          SizedBox(width: index == widget.selected ? 10 : 6),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${widget.owner ? 'Owner' : 'Tenant'} ${index + 1}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: labelStyle(index == widget.selected),
                                ),
                                if (index == widget.selected)
                                  Text(
                                    'of ${widget.count}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 16 / 13,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
