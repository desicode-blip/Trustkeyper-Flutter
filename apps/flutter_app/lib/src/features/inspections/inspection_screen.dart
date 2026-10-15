import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../broker/data/private_documents.dart';
import '../broker/presentation/private_documents_screen.dart';
import '../participants/data/participant_workspace.dart';
import 'inspection_gateway.dart';

String inspectionRoomIcon(String room) {
  final paths = switch (room) {
    'Living room' =>
      '<path d="M20 9V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v3"/><path d="M2 11v5a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-5a2 2 0 0 0-4 0v2H6v-2a2 2 0 0 0-4 0Z"/>',
    'Kitchen' =>
      '<path d="M6 13.9A4 4 0 0 1 7 6a5 5 0 0 1 10 0 4 4 0 0 1 1 7.9V21H6z"/><path d="M6 17h12"/>',
    'Balcony / utility' =>
      '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    'Fixtures & fittings' =>
      '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
    _ when room.startsWith('Washroom') =>
      '<path d="M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z"/>',
    _ =>
      '<path d="M2 4v16"/><path d="M2 8h18a2 2 0 0 1 2 2v10"/><path d="M2 17h20"/><path d="M6 8v9"/>',
  };
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#172231" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">$paths</svg>';
}

Future<DocumentFile> stampInspectionPhoto(
  DocumentFile original,
  Map<String, dynamic> grant,
) async {
  original.validate();
  if (!original.contentType.startsWith('image/')) {
    throw StateError('Take a camera photo.');
  }
  final codec = await ui.instantiateImageCodec(
    original.bytes,
    targetWidth: 1600,
  );
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final width = image.width.toDouble();
      final height = image.height.toDouble();
      canvas.drawImage(image, Offset.zero, Paint());
      canvas.drawRect(
        Rect.fromLTWH(0, height - 104, width, 104),
        Paint()..color = const Color(0xD9152440),
      );
      final date = DateTime.fromMillisecondsSinceEpoch(
        grant['startedAtMs'] as int,
      ).toLocal();
      final painter = TextPainter(
        text: TextSpan(
          text:
              '${DateFormat('d MMM yyyy · h:mm a').format(date)}\n${grant['actorName']} (${grant['actorRole']})',
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 27,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      );
      painter.layout(maxWidth: width - 40);
      painter.paint(canvas, Offset(20, height - 92));
      final picture = recorder.endRecording();
      final stamped = await picture.toImage(image.width, image.height);
      try {
        final bytes = await stamped.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) {
          throw StateError('The camera photo could not be prepared.');
        }
        final file = DocumentFile(
          name: 'Property photo.png',
          bytes: bytes.buffer.asUint8List(),
        );
        file.validate();
        return file;
      } finally {
        stamped.dispose();
        picture.dispose();
        painter.dispose();
      }
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

class InspectionScreen extends StatefulWidget {
  const InspectionScreen({
    required this.propertyId,
    this.agreementId,
    this.role,
    this.gateway,
    this.camera,
    this.offline = false,
    super.key,
  });
  final String propertyId;
  final String? agreementId;
  final String? role;
  final InspectionGateway? gateway;
  final Future<DocumentFile?> Function()? camera;
  final bool offline;
  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  late final gateway = widget.gateway ?? FirebaseInspectionGateway();
  StreamSubscription<InspectionList>? subscription;
  InspectionList? data;
  String? error;
  bool capturing = false;
  bool busy = false;
  bool privatePreviewOpen = false;
  int accessGeneration = 0;
  String room = 'Living room';
  final title = TextEditingController();
  final note = TextEditingController();
  Map<String, dynamic>? pending;
  Map<String, dynamic>? grant;
  DocumentFile? photo;
  static const rooms = [
    'Living room',
    'Kitchen',
    'Bedroom 1',
    'Bedroom 2',
    'Washroom 1',
    'Washroom 2',
    'Balcony / utility',
    'Fixtures & fittings',
  ];
  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    subscription?.cancel();
    subscription = gateway
        .watch(widget.propertyId, widget.agreementId, widget.role)
        .listen(
          (value) {
            if (mounted) {
              setState(() {
                data = value;
                error = null;
              });
            }
          },
          onError: (Object failure) {
            ++accessGeneration;
            if (mounted && privatePreviewOpen) {
              Navigator.maybePop(context);
              privatePreviewOpen = false;
            }
            if (mounted) {
              setState(() {
                data = null;
                pending = null;
                grant = null;
                photo = null;
                capturing = false;
                error =
                    'Photo checks could not be opened. Recheck your login and retry.';
              });
            }
          },
        );
  }

  @override
  void dispose() {
    ++accessGeneration;
    subscription?.cancel();
    title.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (busy || data?.canCapture != true) return;
    final generation = accessGeneration;
    bool allowed() =>
        mounted && generation == accessGeneration && data?.canCapture == true;
    if (pending == null) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$room · item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Item',
                  hintText: 'For example, sink tap',
                ),
              ),
              TextField(
                controller: note,
                maxLength: 1000,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (title.text.trim().length >= 2) Navigator.pop(context, true);
              },
              child: const Text('Open camera'),
            ),
          ],
        ),
      );
      if (!allowed() || accepted != true) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    pending ??= {
      'propertyId': widget.propertyId,
      if (widget.agreementId != null) 'agreementId': widget.agreementId,
      'room': room,
      'title': title.text.trim(),
      'note': note.text.trim(),
      'role': data!.role,
      'source': 'camera',
      'operationId': newRepairReportId(),
    };
    try {
      final currentGrant = grant ?? await gateway.begin(pending!);
      if (!allowed()) return;
      grant = currentGrant;
      if (photo == null) {
        final captured =
            await (widget.camera?.call() ?? pickPrivateDocument(camera: true));
        if (!allowed()) return;
        if (captured == null) {
          pending = null;
          grant = null;
          return;
        }
        final stamped = await stampInspectionPhoto(captured, currentGrant);
        if (!mounted || !allowed()) return;
        photo = stamped;
        privatePreviewOpen = true;
        final accepted = await reviewPrivateDocument(
          context,
          photo!,
          upload: true,
          reviewTitle: 'Check your photo',
          instructions: 'Keep the whole item visible and the photo clear.',
        );
        privatePreviewOpen = false;
        if (!allowed()) return;
        if (!accepted) {
          photo = null;
          grant = null;
          pending = null;
          return;
        }
      }
      await gateway.save(grant!, photo!);
      if (!allowed()) return;
      setState(() {
        pending = null;
        grant = null;
        photo = null;
        capturing = false;
        title.clear();
        note.clear();
      });
    } catch (failure) {
      if (mounted && generation == accessGeneration) {
        setState(
          () => error =
              failure is FirebaseFunctionsException &&
                  failure.code != 'internal'
              ? failure.message ?? 'Reopen photo checks and try again.'
              : failure is StateError
              ? failure.message.toString()
              : 'The photo was not saved. Keep this screen open and retry the same photo.',
        );
      }
    } finally {
      privatePreviewOpen = false;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> check) async {
    final generation = accessGeneration;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await gateway.photo(
        widget.propertyId,
        check['id'] as String,
      );
      if (!mounted || generation != accessGeneration || data == null) return;
      privatePreviewOpen = true;
      await reviewPrivateDocument(
        context,
        file,
        upload: false,
        reviewTitle: '${check['room']} · ${check['title']}',
      );
      privatePreviewOpen = false;
      if (mounted &&
          generation == accessGeneration &&
          data?.role == 'admin' &&
          check['issueId'] == null) {
        await _review(check);
      }
    } catch (failure) {
      if (mounted && generation == accessGeneration) {
        setState(
          () => error =
              'This private photo could not be opened. Refresh and retry.',
        );
      }
    } finally {
      privatePreviewOpen = false;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _review(Map<String, dynamic> check) async {
    final reason = TextEditingController();
    try {
      final status = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review photo'),
          content: TextField(
            controller: reason,
            decoration: const InputDecoration(
              labelText: 'Reason if a repair is needed',
            ),
            maxLength: 1000,
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'approved'),
              child: const Text('All good'),
            ),
            TextButton(
              onPressed: () {
                if (reason.text.trim().length >= 10) {
                  Navigator.pop(context, 'flagged');
                }
              },
              child: const Text('Needs repair'),
            ),
          ],
        ),
      );
      if (status == null) return;
      await gateway.review({
        'propertyId': widget.propertyId,
        'checkId': check['id'],
        'version': check['version'],
        'status': status,
        'note': reason.text.trim(),
        'operationId': newRepairReportId(),
      });
    } finally {
      reason.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = data;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 72,
        leadingWidth: 74,
        leading: Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Center(
            child: IconButton.outlined(
              onPressed: busy
                  ? null
                  : () {
                      if (capturing) {
                        setState(() {
                          capturing = false;
                          pending = null;
                          grant = null;
                          photo = null;
                        });
                      } else {
                        Navigator.maybePop(context);
                      }
                    },
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Back',
              style: IconButton.styleFrom(
                fixedSize: const Size(48, 48),
                side: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.heading,
        ),
        title: Text(capturing ? 'Which room?' : 'Photo checks'),
        actions: [
          if (!capturing)
            IconButton(
              onPressed: busy ? null : _listen,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh photo checks',
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: capturing ? 4 : 24,
            ),
            children: [
              if (widget.offline)
                const Text(
                  'OFFLINE DESIGN PREVIEW · no live photo record',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              if (current == null && error == null)
                const Center(child: CircularProgressIndicator()),
              if (current != null) ...[
                Text(
                  capturing
                      ? 'Tap a room, then take photos'
                      : '${current.address} · newest first',
                  style: const TextStyle(color: AppColors.muted, fontSize: 16),
                ),
                const SizedBox(height: 20),
                if (capturing) ...[
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio:
                        (MediaQuery.sizeOf(context).width.clamp(0, 500) - 56) /
                        168,
                    children: rooms
                        .map(
                          (value) => Semantics(
                            selected: room == value,
                            child: InkWell(
                              onTap: busy || pending != null
                                  ? null
                                  : () => setState(() => room = value),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: room == value
                                      ? AppColors.primary
                                      : const Color(0xFFF6F9FD),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SvgPicture.string(
                                      inspectionRoomIcon(value),
                                      width: 24,
                                      height: 24,
                                      colorFilter: ColorFilter.mode(
                                        room == value
                                            ? Colors.white
                                            : AppColors.heading,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      value,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: room == value
                                            ? Colors.white
                                            : AppColors.heading,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F9FD),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: AppColors.muted,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Only new camera photos. Date, time and your name go on each photo.',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ExpansionTile(
                    title: const Text(
                      'More rooms and capture information',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: rooms.contains(room) ? null : room,
                        decoration: const InputDecoration(
                          labelText: 'Another bedroom or washroom',
                        ),
                        items: [
                          for (var index = 3; index <= 9; index++) ...[
                            DropdownMenuItem(
                              value: 'Bedroom $index',
                              child: Text('Bedroom $index'),
                            ),
                            DropdownMenuItem(
                              value: 'Washroom $index',
                              child: Text('Washroom $index'),
                            ),
                          ],
                        ],
                        onChanged: busy || pending != null
                            ? null
                            : (value) {
                                if (value != null) setState(() => room = value);
                              },
                      ),
                      const Text(
                        'Server receipt time is recorded separately. This is not GPS or tamper-proof capture certification.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ] else ...[
                  if (current.canCapture)
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => setState(() => capturing = true),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Take photos now'),
                    ),
                  if (current.checks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 36),
                      child: Text(
                        'No photo checks yet. Take the first photo at the property.',
                      ),
                    ),
                  ...current.checks.map(
                    (check) => Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: InkWell(
                        onTap: busy ? null : () => _open(check),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.image_outlined,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '${check['title']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 17,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '${check['actorName']} · ${check['actorRole']}',
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${check['room']} · ${check['receivedAtMs'] is int ? DateFormat('d MMM yyyy · h:mm a').format(DateTime.fromMillisecondsSinceEpoch(check['receivedAtMs'] as int).toLocal()) : 'Date unavailable'}',
                                style: const TextStyle(color: AppColors.muted),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                switch (check['status']) {
                                  'approved' => 'All good',
                                  'flagged' => 'Needs repair',
                                  'repair_created' => 'Repair opened',
                                  _ => 'Awaiting review',
                                },
                                style: const TextStyle(
                                  color: AppColors.primary,
                                ),
                              ),
                              if ((check['note'] as String? ?? '').isNotEmpty)
                                Text(check['note'] as String),
                              if ((check['reviewNote'] as String? ?? '')
                                  .isNotEmpty)
                                Text('Support: ${check['reviewNote']}'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (current.checks.length >= 100)
                    const Text(
                      'Showing the latest 100 photo checks. Contact support for older records.',
                    ),
                ],
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: capturing
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                child: FilledButton.icon(
                  onPressed: busy || current?.canCapture != true
                      ? null
                      : _capture,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(
                    busy
                        ? 'Saving…'
                        : pending == null
                        ? 'Open camera'
                        : 'Retry same photo',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
