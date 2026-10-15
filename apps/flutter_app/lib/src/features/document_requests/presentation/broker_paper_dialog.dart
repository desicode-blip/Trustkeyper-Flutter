import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../broker/data/private_documents.dart';
import '../data/document_request_repository.dart';
import 'document_request_widgets.dart';

class BrokerPaperDialog extends StatefulWidget {
  const BrokerPaperDialog({
    required this.paper,
    required this.metadata,
    required this.previous,
    required this.upload,
    required this.view,
    required this.remove,
    required this.failure,
    super.key,
  });
  final RequestedPaper paper;
  final PrivateDocument? Function(DocumentKind) metadata, previous;
  final Future<void> Function(DocumentKind, bool, bool) upload;
  final Future<void> Function(DocumentKind) view, remove;
  final String? Function() failure;
  @override
  State<BrokerPaperDialog> createState() => _BrokerPaperDialogState();
}

class _BrokerPaperDialogState extends State<BrokerPaperDialog> {
  bool busy = false;
  late bool choosing = widget.paper.slots.every(
    (kind) => widget.metadata(kind) == null,
  );
  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _choose(bool camera) async {
    setState(() => choosing = false);
    final kind = widget.paper.slots.firstWhere(
      (kind) => widget.metadata(kind) == null,
      orElse: () => widget.paper.slots.first,
    );
    await _run(() => widget.upload(kind, camera, false));
  }

  Widget _choice(String glyph, String title, String subtitle, bool camera) =>
      Expanded(
        child: InkWell(
          onTap: busy ? null : () => _choose(camera),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 168,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              border: Border.all(color: AppColors.border, width: 1.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: DocumentGlyph(glyph, size: 30, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _page(DocumentKind kind) {
    final file = widget.metadata(kind);
    final label = kind == DocumentKind.aadhaarFront
        ? 'Front'
        : kind == DocumentKind.aadhaarBack
        ? 'Back'
        : widget.paper.label;
    return Expanded(
      child: InkWell(
        onTap: busy
            ? null
            : () => _run(
                () => file == null
                    ? widget.upload(kind, true, false)
                    : widget.view(kind),
              ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: file == null
                ? AppColors.surfaceMuted
                : AppColors.successSoft,
            border: Border.all(
              color: file == null ? AppColors.primaryBorder : AppColors.success,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: file == null
                    ? AppColors.primary
                    : AppColors.success,
                child: file == null
                    ? const DocumentGlyph('camera', color: Colors.white)
                    : const Icon(Icons.check, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                file == null ? label : '$label added',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: file == null
                      ? AppColors.primaryDark
                      : AppColors.success,
                ),
              ),
              if (file == null)
                const Text(
                  'Tap to take photo',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.paper.slots.every(
      (kind) => widget.metadata(kind) != null,
    );
    return PopScope(
      canPop: !busy,
      child: Dialog(
        alignment: const Alignment(0, -.1),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primarySoft,
                      child: DocumentGlyph(widget.paper.name),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Add ${widget.paper.label}',
                        style: const TextStyle(
                          fontSize: 22,
                          height: 28 / 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.heading,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close document',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (busy) ...[
                  const LinearProgressIndicator(value: 0),
                  const SizedBox(height: 12),
                ],
                if (choosing)
                  Row(
                    children: [
                      _choice('camera', 'Click photo', 'Use camera', true),
                      const SizedBox(width: 12),
                      _choice('upload', 'Upload', 'From phone', false),
                    ],
                  )
                else ...[
                  if (widget.paper == RequestedPaper.aadhaar)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Take photo of both sides',
                        style: TextStyle(fontSize: 15, color: AppColors.muted),
                      ),
                    ),
                  Row(
                    children: [
                      for (final kind in widget.paper.slots) ...[
                        if (kind != widget.paper.slots.first)
                          const SizedBox(width: 12),
                        _page(kind),
                      ],
                    ],
                  ),
                  for (final kind in widget.paper.slots) ...[
                    if (widget.metadata(kind) != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.metadata(kind)!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: busy
                                ? null
                                : () => _run(() => widget.view(kind)),
                            icon: const Icon(Icons.visibility_outlined),
                            tooltip: 'View ${kind.label}',
                          ),
                          IconButton(
                            onPressed: busy
                                ? null
                                : () => _run(
                                    () => widget.upload(kind, false, false),
                                  ),
                            icon: const Icon(Icons.sync),
                            tooltip: 'Change ${kind.label}',
                          ),
                          IconButton(
                            onPressed: busy
                                ? null
                                : () => _run(() => widget.remove(kind)),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: AppColors.error,
                            ),
                            tooltip: 'Delete ${kind.label}',
                          ),
                        ],
                      )
                    else ...[
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () =>
                                  _run(() => widget.upload(kind, false, false)),
                        icon: const DocumentGlyph('file', size: 16),
                        label: Text('Choose file for ${kind.label}'),
                      ),
                      if (widget.previous(kind) != null)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => _run(
                                  () => widget.upload(kind, false, true),
                                ),
                          child: Text('Review previous ${kind.label}'),
                        ),
                    ],
                  ],
                  const DocumentNote(
                    'Private copy uploaded for this draft. Identity and bank verification are separate.',
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: busy || !ready
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Save', style: TextStyle(fontSize: 17)),
                    ),
                  ),
                ],
                if (widget.failure() != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      widget.failure()!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
