import 'dart:typed_data';
import 'dart:ui' as image_codec;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/agreement_draft.dart';
import '../data/private_documents.dart';
import '../data/private_pdf_reference.dart';
import '../../document_requests/data/document_request_repository.dart';
import '../../document_requests/presentation/broker_document_links.dart';
import '../../document_requests/presentation/broker_paper_dialog.dart';

Future<DocumentFile?> pickPrivateDocument({bool camera = false}) async {
  String name;
  int? size;
  Stream<List<int>> source;
  if (camera) {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2200,
      imageQuality: 85,
    );
    if (file == null) return null;
    name = file.name;
    size = await file.length();
    source = file.openRead();
  } else {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (file == null) return null;
    name = file.name;
    size = await file.length();
    source = file.readAsByteStream();
  }
  if (size != null && size > DocumentFile.maximumBytes) {
    throw const DocumentFailure('Choose a readable file up to 10 MB.');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in source) {
    if (bytes.length + chunk.length > DocumentFile.maximumBytes) {
      throw const DocumentFailure('Choose a readable file up to 10 MB.');
    }
    bytes.add(chunk);
  }
  return DocumentFile(name: name, bytes: bytes.takeBytes());
}

Future<bool> reviewPrivateDocument(
  BuildContext context,
  DocumentFile file, {
  required bool upload,
  bool selectionOnly = false,
  String? reviewTitle,
  String? instructions,
  String? confirmationLabel,
}) async {
  file.validate();
  if (file.contentType.startsWith('image/')) {
    try {
      final codec = await image_codec.instantiateImageCodec(
        file.bytes,
        targetWidth: 1000,
      );
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } catch (_) {
      throw const DocumentFailure(
        'This image cannot be opened. Choose a readable JPG or PNG.',
      );
    }
  }
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        builder: (_) => _DocumentReviewDialog(
          file: file,
          upload: upload,
          selectionOnly: selectionOnly,
          reviewTitle: reviewTitle,
          instructions: instructions,
          confirmationLabel: confirmationLabel,
        ),
      ) ??
      false;
}

class PrivateDocumentsScreen extends StatefulWidget {
  const PrivateDocumentsScreen({
    required this.draft,
    this.documents,
    this.previousDocuments,
    this.pickFile,
    this.takePhoto,
    this.onlyPartyId,
    this.embedded = false,
    this.readOnly = false,
    this.enabled = true,
    this.onBusyChanged,
    this.requests,
    this.beforeRequest,
    this.onEditPerson,
    this.onCompletionChanged,
    this.documentNow,
    super.key,
  });
  final AgreementDraft draft;
  final PrivateDocuments? documents;
  final PrivateDocuments? previousDocuments;
  final Future<DocumentFile?> Function()? pickFile;
  final Future<DocumentFile?> Function()? takePhoto;
  final String? onlyPartyId;
  final bool embedded;
  final bool readOnly;
  final bool enabled;
  final ValueChanged<bool>? onBusyChanged;
  final DocumentRequests? requests;
  final Future<bool> Function()? beforeRequest;
  final VoidCallback? onEditPerson;
  final ValueChanged<bool>? onCompletionChanged;
  final DateTime Function()? documentNow;
  @override
  State<PrivateDocumentsScreen> createState() => _PrivateDocumentsScreenState();
}

class _PrivateDocumentsScreenState extends State<PrivateDocumentsScreen> {
  late final PrivateDocuments documents;
  late final List<AgreementParty> parties;
  DocumentRequests? requests;
  RequestedPaper? expandedPaper;
  final metadata = <DocumentKind, PrivateDocument?>{};
  final previousMetadata = <DocumentKind, PrivateDocument?>{};
  int selected = 0;
  bool loading = true;
  bool busy = false;
  double? progress;
  String? error;
  @override
  void initState() {
    super.initState();
    parties = [...widget.draft.owners, ...widget.draft.tenants]
        .where(
          (party) =>
              widget.onlyPartyId == null || party.id == widget.onlyPartyId,
        )
        .toList();
    documents =
        widget.documents ??
        PrivateDocuments.firebase(
          draftId: widget.draft.id,
          revision: widget.draft.revision,
          partyIds: parties.map((party) => party.id).toSet(),
        );
    requests =
        widget.requests ??
        (widget.documents == null ? FirebaseDocumentRequests() : null);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      metadata.clear();
      previousMetadata.clear();
    });
    try {
      final values = await Future.wait([
        ...DocumentKind.values.map(
          (kind) => documents.metadata(parties[selected].id, kind),
        ),
        if (widget.previousDocuments != null)
          ...DocumentKind.values.map(
            (kind) =>
                widget.previousDocuments!.metadata(parties[selected].id, kind),
          ),
      ]);
      if (!mounted) return;
      setState(() {
        for (var index = 0; index < DocumentKind.values.length; index++) {
          metadata[DocumentKind.values[index]] = values[index];
          previousMetadata[DocumentKind.values[index]] =
              widget.previousDocuments == null
              ? null
              : values[index + DocumentKind.values.length];
        }
      });
    } catch (failure) {
      _failure(failure);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _failure(Object failure) {
    if (mounted) {
      setState(
        () => error = failure is DocumentFailure
            ? failure.message
            : 'Document operation failed. Check your connection and access, then retry.',
      );
    }
  }

  Future<DocumentFile?> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (file == null) return null;
    return _readFile(file.name, await file.length(), file.readAsByteStream());
  }

  Future<DocumentFile?> _camera() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2200,
      imageQuality: 85,
    );
    if (file == null) return null;
    return _readFile(file.name, await file.length(), file.openRead());
  }

  Future<DocumentFile> _readFile(
    String name,
    int? size,
    Stream<List<int>> source,
  ) async {
    if (size != null && size > DocumentFile.maximumBytes) {
      throw const DocumentFailure('Choose a readable file up to 10 MB.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in source) {
      if (bytes.length + chunk.length > DocumentFile.maximumBytes) {
        throw const DocumentFailure('Choose a readable file up to 10 MB.');
      }
      bytes.add(chunk);
    }
    return DocumentFile(name: name, bytes: bytes.takeBytes());
  }

  Future<bool> _preview(DocumentFile file, {required bool upload}) async {
    return reviewPrivateDocument(context, file, upload: upload);
  }

  Future<void> _upload(
    DocumentKind kind, {
    bool camera = false,
    bool previous = false,
  }) async {
    widget.onBusyChanged?.call(true);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = previous
          ? await widget.previousDocuments!.read(parties[selected].id, kind)
          : await (camera
                ? (widget.takePhoto ?? _camera)
                : (widget.pickFile ?? _pick))();
      if (file == null || !mounted) return;
      if (!await _preview(file, upload: true) || !mounted) return;
      if (metadata[kind] != null) {
        final replace = await _confirm(
          'Replace ${kind.label}?',
          'The current private copy in this slot will be overwritten.',
        );
        if (!replace || !mounted) return;
      }
      setState(() => progress = 0);
      await documents.upload(parties[selected].id, kind, file, (value) {
        if (mounted) setState(() => progress = value);
      });
      if (requests != null) {
        final paper = RequestedPaper.individual.firstWhere(
          (paper) => paper.slots.contains(kind),
        );
        final links = await requests!
            .watch(widget.draft.id, widget.draft.revision)
            .first
            .timeout(const Duration(seconds: 30));
        for (final link in links.where(
          (link) =>
              link.data['partyId'] == parties[selected].id &&
              link.phone == parties[selected].phone &&
              link.name == parties[selected].name &&
              link.paper.papers.contains(paper) &&
              !link.closedPapers.containsKey(paper.name),
        )) {
          await requests!.record(link, 'paper_taken_over', paper: paper);
        }
      }
      await _load();
    } catch (failure) {
      _failure(failure);
    } finally {
      if (mounted) {
        widget.onBusyChanged?.call(false);
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _view(DocumentKind kind) async {
    widget.onBusyChanged?.call(true);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await documents.read(parties[selected].id, kind);
      if (mounted) await _preview(file, upload: false);
    } catch (failure) {
      _failure(failure);
    } finally {
      if (mounted) {
        widget.onBusyChanged?.call(false);
        setState(() => busy = false);
      }
    }
  }

  Future<void> _remove(DocumentKind kind) async {
    widget.onBusyChanged?.call(true);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!await _confirm(
            'Delete ${kind.label}?',
            'This removes the private copy for this draft revision.',
          ) ||
          !mounted) {
        return;
      }
      await documents.remove(parties[selected].id, kind);
      await _load();
    } catch (failure) {
      _failure(failure);
    } finally {
      if (mounted) {
        widget.onBusyChanged?.call(false);
        setState(() => busy = false);
      }
    }
  }

  Future<void> _addPaper(RequestedPaper paper) async {
    if (busy || loading || !widget.enabled) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x80172231),
      builder: (_) => BrokerPaperDialog(
        paper: paper,
        metadata: (kind) => metadata[kind],
        previous: (kind) => previousMetadata[kind],
        upload: (kind, camera, previous) =>
            _upload(kind, camera: camera, previous: previous),
        view: _view,
        remove: _remove,
        failure: () => error,
      ),
    );
  }

  Future<void> _viewPaper(RequestedPaper paper) async {
    if (paper.slots.length == 1) {
      await _view(paper.slots.single);
      return;
    }
    final kind = await showDialog<DocumentKind>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(paper.label),
        children: [
          for (final slot in paper.slots)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, slot),
              child: Text('See ${slot.label}'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (kind != null && mounted) await _view(kind);
  }

  Future<void> _removePaper(RequestedPaper paper) async {
    for (final kind in paper.slots) {
      if (metadata[kind] != null) {
        await documents.remove(parties[selected].id, kind);
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final content = [
      if (!widget.embedded)
        const Text(
          'JPG, PNG or PDF · Up to 10 MB each. Upload a file or take a photo. Uploaded copies remain private and are not identity or bank verification.',
        ),
      if (!widget.embedded) const SizedBox(height: 16),
      if (widget.onlyPartyId == null)
        DropdownButtonFormField<int>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Person'),
          items: [
            for (var index = 0; index < parties.length; index++)
              DropdownMenuItem(
                value: index,
                child: Text(
                  '${widget.draft.owners.any((owner) => owner.id == parties[index].id) ? "Owner" : "Tenant"}: ${parties[index].name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: busy || loading || !widget.enabled
              ? null
              : (value) {
                  if (value != null) {
                    selected = value;
                    expandedPaper = null;
                    _load();
                  }
                },
        ),
      if (!widget.embedded) const SizedBox(height: 12),
      if (!widget.embedded)
        Text(
          'Document scope: revision ${widget.draft.revision}. An unchanged person can review and reuse a previous copy. Changed identities require new documents.',
        ),
      if (loading)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (error != null) ...[
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        TextButton(
          onPressed: busy || loading || !widget.enabled ? null : _load,
          child: const Text('Retry loading'),
        ),
      ],
      if (progress != null) ...[
        LinearProgressIndicator(value: progress),
        Text('Uploading ${(progress! * 100).round()}%'),
      ],
      if (requests != null)
        BrokerDocumentLinks(
          now: widget.documentNow,
          key: ValueKey('links/${parties[selected].id}'),
          requests: requests!,
          readOnly: widget.readOnly,
          draftId: widget.draft.id,
          revision: widget.draft.revision,
          party: parties[selected],
          includeLinkedIn: widget.draft.tenants.any(
            (party) => party.id == parties[selected].id,
          ),
          enabled: !busy && !loading && widget.enabled,
          uploadedKinds: metadata.entries
              .where((entry) => entry.value != null)
              .map((entry) => entry.key)
              .toSet(),
          beforeRequest: widget.beforeRequest,
          onEditPerson: widget.onEditPerson,
          onBusyChanged: (value) {
            if (mounted) setState(() => busy = value);
            widget.onBusyChanged?.call(value);
          },
          onAdd: _addPaper,
          onViewLocal: _viewPaper,
          onRemoveLocal: _removePaper,
          onCompletionChanged: widget.onCompletionChanged,
        ),
      if (requests != null && expandedPaper != null)
        TextButton(
          onPressed: busy ? null : () => setState(() => expandedPaper = null),
          child: const Text('Close document controls'),
        ),
      if (!loading && error == null)
        for (final kind
            in requests == null
                ? DocumentKind.values
                : expandedPaper?.slots ?? <DocumentKind>[])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    metadata[kind] == null
                        ? previousMetadata[kind] == null
                              ? 'Not uploaded'
                              : 'Previous revision available · Review before reuse'
                        : '${metadata[kind]!.name}\nUploaded · Not verified',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (metadata[kind] == null &&
                          previousMetadata[kind] != null)
                        TextButton(
                          onPressed: busy || loading || !widget.enabled
                              ? null
                              : () => _upload(kind, previous: true),
                          child: const Text('Review previous copy'),
                        ),
                      TextButton(
                        onPressed: busy || loading || !widget.enabled
                            ? null
                            : () => _upload(kind),
                        child: Text(
                          metadata[kind] == null ? 'Add document' : 'Replace',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: busy || loading || !widget.enabled
                            ? null
                            : () => _upload(kind, camera: true),
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text('Take photo'),
                      ),
                      if (metadata[kind] != null) ...[
                        TextButton(
                          onPressed: busy || loading || !widget.enabled
                              ? null
                              : () => _view(kind),
                          child: const Text('View'),
                        ),
                        TextButton(
                          onPressed: busy || loading || !widget.enabled
                              ? null
                              : () => _remove(kind),
                          child: const Text('Delete'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
      if (!widget.embedded)
        const Text(
          'Uploads are not identity or bank verification. Send link lets this person add the requested paper on mobile web after phone OTP.',
        ),
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: content,
      );
    }
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Private documents')),
        body: ListView(padding: const EdgeInsets.all(20), children: content),
      ),
    );
  }
}

class _DocumentReviewDialog extends StatefulWidget {
  const _DocumentReviewDialog({
    required this.file,
    required this.upload,
    required this.selectionOnly,
    this.reviewTitle,
    this.instructions,
    this.confirmationLabel,
  });
  final DocumentFile file;
  final bool upload;
  final bool selectionOnly;
  final String? reviewTitle;
  final String? instructions;
  final String? confirmationLabel;

  @override
  State<_DocumentReviewDialog> createState() => _DocumentReviewDialogState();
}

class _DocumentReviewDialogState extends State<_DocumentReviewDialog> {
  late bool readable = widget.file.contentType.startsWith('image/');
  late final PdfDocumentRef? pdf = readable
      ? null
      : privatePdfReference(widget.file);
  late final pdfParams = PdfViewerParams(
    onViewerReady: (document, controller) {
      if (mounted && !readable && document.pages.isNotEmpty) {
        setState(() => readable = true);
      }
    },
    errorBannerBuilder: (context, error, stackTrace, documentRef) =>
        const Center(
          child: Text(
            'This PDF cannot be opened. Choose a readable, unlocked PDF.',
          ),
        ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.reviewTitle ??
          (widget.selectionOnly
              ? 'Review selected file'
              : widget.upload
              ? 'Review before uploading'
              : 'Private document'),
    ),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.file.name),
            const SizedBox(height: 12),
            if (widget.file.contentType.startsWith('image/'))
              Image.memory(widget.file.bytes, height: 260, fit: BoxFit.contain)
            else
              SizedBox(height: 400, child: PdfViewer(pdf!, params: pdfParams)),
            const SizedBox(height: 12),
            Text(
              widget.instructions ??
                  (widget.selectionOnly
                      ? 'Review every page. Nothing is sent until you press Send to broker. Sending a document does not verify identity or bank details.'
                      : 'Review every page. Private broker copy only: uploading does not verify identity or send this file to anyone.'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Close'),
      ),
      if (widget.upload)
        FilledButton(
          onPressed: readable ? () => Navigator.pop(context, true) : null,
          child: Text(
            widget.confirmationLabel ??
                (widget.selectionOnly
                    ? 'Use this file'
                    : 'Upload private copy'),
          ),
        ),
    ],
  );
}
