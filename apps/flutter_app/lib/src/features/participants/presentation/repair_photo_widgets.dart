import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../broker/data/private_documents.dart';
import '../data/participant_repository.dart';
import '../data/participant_workspace.dart';

class RepairPhotoSelection extends StatelessWidget {
  const RepairPhotoSelection({
    required this.photos,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    super.key,
  });
  final List<DocumentFile> photos;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (photos.length < 4)
        Material(
          color: AppColors.surfaceMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          child: ListTile(
            minTileHeight: 76,
            enabled: enabled,
            onTap: enabled ? onAdd : null,
            leading: const CircleAvatar(
              backgroundColor: AppColors.primary,
              child: Icon(Icons.camera_alt_outlined, color: Colors.white),
            ),
            title: const Text(
              'Add a photo',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Helps us fix it faster',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
      for (var index = 0; index < photos.length; index++)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  photos[index].bytes,
                  width: 72,
                  height: 72,
                  cacheWidth: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stack) => const SizedBox(
                    width: 72,
                    height: 72,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Photo ${index + 1} of 4\nSelected · Not sent'),
              ),
              IconButton(
                tooltip: 'Remove photo ${index + 1}',
                onPressed: enabled ? () => onRemove(index) : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
    ],
  );
}

class ParticipantIssueDetailScreen extends StatelessWidget {
  const ParticipantIssueDetailScreen({
    required this.issue,
    this.reader,
    super.key,
  });
  final ParticipantRecord issue;
  final IssuePhotoReader? reader;

  @override
  Widget build(BuildContext context) {
    final photos = issue.data['photos'];
    final createdAt = recordDate(issue.data['createdAt']);
    return Scaffold(
      appBar: AppBar(title: const Text('Issue details')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                issue.text('title', 'Reported problem'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                issue.text('propertyAddress', 'Linked home'),
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              Text(
                issue.text('status', 'open').replaceAll('_', ' '),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (createdAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Sent ${DateFormat('d MMM yyyy · h:mm a').format(createdAt.toLocal())}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              SelectableText(
                issue.text('description', 'No description recorded.'),
              ),
              const SizedBox(height: 24),
              if (photos is List && photos.isNotEmpty) ...[
                const Text(
                  'Reported photos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final photo in photos.whereType<Map>())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: PrivateRepairPhoto(
                      issueId: issue.id,
                      path: photo['path'] is String
                          ? photo['path'] as String
                          : '',
                      reader: reader,
                    ),
                  ),
                const Text(
                  'Photos are submitted evidence, not verified capture dates or completed repairs.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ] else
                const Text(
                  'No photos were included with this report.',
                  style: TextStyle(color: AppColors.muted),
                ),
              const SizedBox(height: 24),
              Text(
                'Reference: ${issue.id}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PrivateRepairPhoto extends StatefulWidget {
  const PrivateRepairPhoto({
    required this.issueId,
    required this.path,
    this.reader,
    super.key,
  });
  final String issueId;
  final String path;
  final IssuePhotoReader? reader;
  @override
  State<PrivateRepairPhoto> createState() => _PrivateRepairPhotoState();
}

class _PrivateRepairPhotoState extends State<PrivateRepairPhoto> {
  late Future<Uint8List>? photo = widget.reader?.readPhoto(
    widget.issueId,
    widget.path,
  );
  @override
  void didUpdateWidget(PrivateRepairPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.issueId != widget.issueId ||
        oldWidget.reader != widget.reader) {
      photo = widget.reader?.readPhoto(widget.issueId, widget.path);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: photo,
    builder: (context, snapshot) {
      if (photo == null || snapshot.hasError) {
        return Column(
          children: [
            const Text('Could not open this private photo.'),
            if (widget.reader != null)
              TextButton(
                onPressed: () => setState(() {
                  photo = widget.reader!.readPhoto(widget.issueId, widget.path);
                }),
                child: const Text('Retry photo'),
              ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final bytes = snapshot.data!;
      return InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: InteractiveViewer(
                    child: Image.memory(
                      bytes,
                      cacheWidth: 1200,
                      errorBuilder: (_, error, stack) =>
                          const Text('This photo cannot be decoded.'),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            bytes,
            height: 190,
            width: double.infinity,
            cacheWidth: 1000,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stack) => const SizedBox(
              height: 120,
              child: Center(child: Text('This photo cannot be decoded.')),
            ),
          ),
        ),
      );
    },
  );
}
