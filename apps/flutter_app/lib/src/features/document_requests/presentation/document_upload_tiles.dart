import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../broker/data/private_documents.dart';

class DocumentUploadTiles extends StatelessWidget {
  const DocumentUploadTiles({
    required this.slots,
    required this.files,
    required this.busy,
    required this.onPick,
    required this.onRemove,
    super.key,
  });
  final List<DocumentKind> slots;
  final Map<DocumentKind, DocumentFile> files;
  final bool busy;
  final void Function(DocumentKind kind, bool camera) onPick;
  final ValueChanged<DocumentKind> onRemove;

  Future<void> _choose(BuildContext context, DocumentKind kind) async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add ${kind.label}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Take photo'),
                subtitle: const Text('Opens your phone camera'),
                onTap: () => Navigator.pop(context, true),
              ),
              ListTile(
                leading: const Icon(
                  Icons.upload_file_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Choose photo or PDF'),
                subtitle: const Text('From your files · up to 10 MB'),
                onTap: () => Navigator.pop(context, false),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
    if (camera != null && context.mounted && !busy) onPick(kind, camera);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Take a photo or choose a file for each required page.',
        style: TextStyle(fontSize: 13, color: AppColors.muted),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 280 ? 1 : slots.length;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final kind in slots)
                SizedBox(
                  width: (constraints.maxWidth - 12 * (columns - 1)) / columns,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        color: files[kind] == null
                            ? AppColors.surfaceMuted
                            : AppColors.successSoft,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: busy ? null : () => _choose(context, kind),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 154),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: files[kind] == null
                                    ? AppColors.border
                                    : AppColors.success,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  backgroundColor: files[kind] == null
                                      ? AppColors.primary
                                      : AppColors.success,
                                  child: Icon(
                                    files[kind] == null
                                        ? Icons.camera_alt_outlined
                                        : Icons.check,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  kind.label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  files[kind] == null
                                      ? 'Tap to add'
                                      : 'Selected · Not sent',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: files[kind] == null
                                        ? AppColors.muted
                                        : AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (files[kind] != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          files[kind]!.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: busy ? null : () => onRemove(kind),
                          icon: const Icon(Icons.delete_outline, size: 17),
                          label: const Text('Remove selected file'),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}
