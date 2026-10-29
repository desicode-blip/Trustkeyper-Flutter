import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../broker/presentation/onboarding_widgets.dart' show OnbWaitSpinner;
import '../../broker/data/agreement_draft.dart';
import '../../broker/data/private_documents.dart';
import '../../broker/presentation/private_documents_screen.dart';
import '../data/broker_paper_state.dart';
import '../data/document_request_repository.dart';
import 'broker_document_confirm.dart';
import 'document_link_dialog.dart';
import 'document_request_widgets.dart';
import 'linkedin_profile_fields.dart';

class BrokerDocumentLinks extends StatefulWidget {
  const BrokerDocumentLinks({
    required this.requests,
    required this.draftId,
    required this.revision,
    required this.party,
    required this.onAdd,
    this.onViewLocal,
    this.onRemoveLocal,
    this.onCompletionChanged,
    this.beforeRequest,
    this.onBusyChanged,
    this.onEditPerson,
    this.openMessage,
    this.now,
    this.enabled = true,
    this.readOnly = false,
    this.includeLinkedIn = false,
    this.uploadedKinds = const {},
    super.key,
  });
  final DocumentRequests requests;
  final String draftId;
  final int revision;
  final AgreementParty party;
  final ValueChanged<RequestedPaper> onAdd;
  final Future<void> Function(RequestedPaper)? onViewLocal, onRemoveLocal;
  final ValueChanged<bool>? onCompletionChanged;
  final Future<bool> Function()? beforeRequest;
  final ValueChanged<bool>? onBusyChanged;
  final VoidCallback? onEditPerson;
  final Future<bool> Function(Uri)? openMessage;
  final DateTime Function()? now;
  final bool enabled;
  final bool readOnly;
  final bool includeLinkedIn;
  final Set<DocumentKind> uploadedKinds;
  @override
  State<BrokerDocumentLinks> createState() => _BrokerDocumentLinksState();
}

class _BrokerDocumentLinksState extends State<BrokerDocumentLinks> {
  StreamSubscription<List<DocumentRequestInfo>>? subscription;
  Timer? clock, highlightTimer;
  List<DocumentRequestInfo> records = [];
  bool busy = false, loaded = false, loadFailed = false;
  bool? complete;
  RequestedPaper? highlighted;
  String? error;
  RequestedPaper? failedPaper;
  String? failedChannel;
  DateTime get currentTime => widget.now?.call() ?? DateTime.now();
  List<BrokerPaperState> get states => BrokerPaperState.resolve(
    records,
    widget.uploadedKinds,
    includeLinkedIn: widget.includeLinkedIn,
  );
  @override
  void initState() {
    super.initState();
    _listen();
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && records.isNotEmpty) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant BrokerDocumentLinks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requests != widget.requests ||
        oldWidget.draftId != widget.draftId ||
        oldWidget.revision != widget.revision ||
        oldWidget.party.id != widget.party.id ||
        oldWidget.party.name != widget.party.name ||
        oldWidget.party.phone != widget.party.phone ||
        oldWidget.party.email != widget.party.email) {
      records = [];
      loaded = false;
      complete = null;
      failedPaper = null;
      failedChannel = null;
      _listen();
    }
    _completion();
  }

  @override
  void dispose() {
    subscription?.cancel();
    clock?.cancel();
    highlightTimer?.cancel();
    super.dispose();
  }

  void _listen() {
    subscription?.cancel();
    subscription = widget.requests
        .watch(widget.draftId, widget.revision)
        .listen(
          (values) {
            if (!mounted) return;
            final previous = states;
            final wasLoaded = loaded;
            setState(() {
              records = values
                  .where(
                    (record) =>
                        record.data['partyId'] == widget.party.id &&
                        record.name == widget.party.name &&
                        record.phone == widget.party.phone,
                  )
                  .toList();
              loaded = true;
              loadFailed = false;
            });
            final current = states;
            _completion();
            if (!wasLoaded) return;
            final added = current
                .where(
                  (state) =>
                      state.received &&
                      previous.any(
                        (old) =>
                            old.paper == state.paper &&
                            (!old.received || old.signature != state.signature),
                      ),
                )
                .toList();
            if (added.isNotEmpty) {
              _toast(
                current.every((state) => state.done)
                    ? 'All documents added for ${widget.party.name.split(' ').first}'
                    : '${widget.party.name.split(' ').first} added ${added.first.paper.label}',
                paper: added.length == 1 ? added.first.paper : null,
              );
            }
          },
          onError: (Object _) {
            if (mounted) setState(() => loadFailed = true);
          },
        );
  }

  void _completion() {
    final value = states
        .where((state) => state.paper != RequestedPaper.linkedin)
        .every((state) => state.done);
    if (complete == value) return;
    complete = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && complete == value) widget.onCompletionChanged?.call(value);
    });
  }

  void _toast(String message, {RequestedPaper? paper, bool deleted = false}) {
    if (!mounted) return;
    highlightTimer?.cancel();
    setState(() => highlighted = paper);
    highlightTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => highlighted = null);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.heading,
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 118),
          padding: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: deleted
                    ? AppColors.error
                    : const Color(0xFF2FA866),
                child: DocumentGlyph(
                  deleted ? 'trash' : 'check',
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 20 / 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  void _busy(bool value) {
    if (!mounted) return;
    setState(() => busy = value);
    widget.onBusyChanged?.call(value);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    _busy(true);
    setState(() => error = null);
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : 'Could not update this document. Check your connection and retry.',
        );
      }
    } finally {
      _busy(false);
    }
  }

  Future<void> _send(
    RequestedPaper paper, {
    bool remind = false,
    String? via,
  }) async {
    final channel =
        via ??
        await showDialog<String>(
          context: context,
          barrierColor: const Color(0x80172231),
          builder: (_) => DocumentLinkDialog(
            paper: paper.label,
            name: widget.party.name,
            phone: widget.party.phone,
            email: widget.party.email,
            canEditEmail: widget.onEditPerson != null,
            remind: remind,
          ),
        );
    if (channel == null || !mounted) return;
    if (channel == 'Add email') {
      widget.onEditPerson?.call();
      return;
    }
    await _run(() async {
      if (widget.beforeRequest != null && !await widget.beforeRequest!()) {
        throw const DocumentFailure(
          'Save this person before sending their link.',
        );
      }
      if (!mounted) return;
      final link = await widget.requests.create(
        draftId: widget.draftId,
        revision: widget.revision,
        partyId: widget.party.id,
        paper: paper,
        remind: remind,
      );
      if (!mounted) return;
      final message =
          '${link.info.broker} asked for your ${paper.label} for ${link.info.address}. Open this private link and verify your phone. No app installation needed. ${link.url}';
      if (channel == 'Copy link') {
        await Clipboard.setData(ClipboardData(text: message));
        _toast(
          'Private link copied. Share it only with this person. No message has been sent.',
        );
        return;
      }
      final uri = switch (channel) {
        'Email' => Uri(
          scheme: 'mailto',
          path: widget.party.email,
          queryParameters: {
            'subject': 'Documents for your rent agreement',
            'body': message,
          },
        ),
        'WhatsApp' => Uri.https(
          'wa.me',
          '/${link.info.phone.replaceAll('+', '')}',
          {'text': message},
        ),
        _ => Uri(
          scheme: 'sms',
          path: link.info.phone,
          queryParameters: {'body': message},
        ),
      };
      bool opened;
      try {
        opened =
            await (widget.openMessage?.call(uri) ??
                launchUrl(uri, mode: LaunchMode.externalApplication));
      } catch (_) {
        opened = false;
      }
      if (!mounted) return;
      if (!opened) {
        setState(() {
          failedPaper = paper;
          failedChannel = channel;
        });
        return;
      }
      setState(() {
        failedPaper = null;
        failedChannel = null;
      });
      final sent = await confirmBrokerDocument(
        context,
        glyph: 'send',
        title: 'Did you send the message?',
        message:
            'Finish sending in $channel, then confirm here. Opening the message does not confirm delivery.',
        confirm: 'I sent it',
        cancel: 'Not yet',
      );
      if (!sent || !mounted) return;
      await widget.requests.record(link.info, 'shared', channel: channel);
      _toast(
        remind
            ? '${paper.label} link sent again'
            : switch (channel) {
                'Email' =>
                  '${paper.label} link emailed to ${widget.party.email}',
                'SMS' => '${paper.label} link sent by SMS',
                _ =>
                  '${paper.label} link sent to ${widget.party.name.split(' ').first}',
              },
        paper: paper == RequestedPaper.all ? null : paper,
      );
    });
  }

  Future<void> _add(BrokerPaperState state) async {
    if (state.paper == RequestedPaper.linkedin) {
      await _editLinkedIn(state);
      return;
    }
    if (state.waiting) {
      if (!await confirmBrokerDocument(
            context,
            glyph: 'camera',
            title: 'Add ${_shortName(state.paper)} yourself?',
            message:
                'Link is already sent to ${widget.party.name.split(' ').first}. If you add it, their ${_shortName(state.paper)} link will stop.',
            confirm: 'Yes, I will add',
            cancel: 'No, wait for ${widget.party.name.split(' ').first}',
          ) ||
          !mounted) {
        return;
      }
    }
    widget.onAdd(state.paper);
  }

  Future<void> _editLinkedIn(BrokerPaperState state) async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x80172231),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: LinkedInProfileFields(
            name: widget.party.name,
            initial:
                (state.request?.submission?['linkedInDetails'] as Map?)?['url']
                    as String? ??
                '',
            onSave: (details) async {
              _busy(true);
              try {
                if (widget.beforeRequest != null &&
                    !await widget.beforeRequest!()) {
                  throw const DocumentFailure(
                    'Save this tenant before adding their profile.',
                  );
                }
                final link = await widget.requests.create(
                  draftId: widget.draftId,
                  revision: widget.revision,
                  partyId: widget.party.id,
                  paper: RequestedPaper.linkedin,
                );
                await widget.requests.record(
                  link.info,
                  'linkedin_added',
                  linkedInDetails: details,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _toast(
                  details['skipped'] == true
                      ? 'LinkedIn skipped · can add later'
                      : 'LinkedIn profile added',
                  paper: RequestedPaper.linkedin,
                );
              } finally {
                _busy(false);
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BrokerPaperState state) async {
    final description = state.paper == RequestedPaper.bank
        ? 'details'
        : state.paper == RequestedPaper.linkedin
        ? 'profile'
        : 'photo';
    if (!await confirmBrokerDocument(
          context,
          glyph: 'trash',
          destructive: true,
          title: 'Delete ${_shortName(state.paper)} $description?',
          message:
              'It will be removed. You or ${widget.party.name.split(' ').first} must add it again.',
          confirm: 'Yes, delete',
          cancel: 'No, keep it',
        ) ||
        !mounted) {
      return;
    }
    await _run(() async {
      for (final request in records.where(
        (record) =>
            record.paper.papers.contains(state.paper) ||
            state.paper == RequestedPaper.linkedin &&
                record.paper == RequestedPaper.all &&
                record.submission?['linkedInDetails'] != null,
      )) {
        await widget.requests.record(
          request,
          'paper_deleted',
          paper: state.paper,
        );
      }
      await widget.onRemoveLocal?.call(state.paper);
      _toast(
        '${_shortName(state.paper)} $description deleted',
        paper: state.paper,
        deleted: true,
      );
    });
  }

  Future<void> _view(BrokerPaperState state) => _run(() async {
    if (state.paper == RequestedPaper.linkedin) {
      final profile = state.request?.submission?['linkedInDetails'] as Map;
      if (profile['skipped'] == true) return;
      final uri = Uri.parse(profile['url'] as String);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const DocumentFailure('Could not open this profile. Try again.');
      }
      return;
    }
    if (state.local) {
      await widget.onViewLocal?.call(state.paper);
      return;
    }
    final info = state.request!;
    final files = Map<String, dynamic>.from(
      info.submission?['files'] as Map? ?? {},
    );
    if (!mounted) return;
    final selection = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(state.paper.label),
        children: [
          for (final kind in state.paper.slots.where(
            (kind) => files.containsKey(kind.name),
          ))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, kind.name),
              child: Text('See ${kind.label}'),
            ),
          if (state.paper == RequestedPaper.bank &&
              info.submission?['bankDetails'] != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'bankDetails'),
              child: const Text('See bank details'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'unclear'),
            child: const Text('Ask for a clearer copy'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (!mounted || selection == null) return;
    if (selection == 'unclear') {
      if (info.paper == RequestedPaper.all) {
        await widget.requests.record(info, 'paper_deleted', paper: state.paper);
        _toast(
          'Send a new ${state.paper.label} link to request a clearer copy.',
          paper: state.paper,
        );
      } else {
        await widget.requests.record(
          info,
          'unclear',
          reason: 'Photo not clear. Please upload a readable copy.',
        );
      }
      return;
    }
    if (selection == 'bankDetails') {
      final bank = Map<String, dynamic>.from(
        info.submission!['bankDetails'] as Map,
      );
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Bank details'),
          content: Text(
            bank['method'] == 'upi'
                ? 'UPI ID: ${bank['upiId']}\nNot bank verified'
                : '${bank['name']}\n${bank['bank']}\nAccount: ${bank['accountNumber']}\nIFSC: ${bank['ifsc']}\nNot bank verified',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } else {
      final file = await widget.requests.readFile(
        Map<String, dynamic>.from(files[selection] as Map),
      );
      if (mounted) await reviewPrivateDocument(context, file, upload: false);
    }
  });
  Future<void> _options(RequestedPaper paper) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Copy ${paper.label} link'),
              onTap: () => Navigator.pop(sheetContext, 'copy'),
            ),
            ListTile(
              title: const Text('Send all documents link'),
              onTap: () => Navigator.pop(sheetContext, 'all'),
            ),
            ListTile(
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'copy') await _send(paper, via: 'Copy link');
    if (action == 'all') await _send(RequestedPaper.all);
  }

  int _cooldown(BrokerPaperState state) {
    if ((state.request?.data['shareCount'] as num? ?? 0) < 2) return 0;
    return (60 -
            (currentTime.millisecondsSinceEpoch - state.request!.sharedAtMs) ~/
                1000)
        .clamp(0, 60);
  }

  String _shortName(RequestedPaper paper) => switch (paper) {
    RequestedPaper.aadhaar => 'Aadhaar',
    RequestedPaper.pan => 'PAN',
    RequestedPaper.linkedin => 'LinkedIn',
    _ => 'Bank',
  };
  @override
  Widget build(BuildContext context) {
    final current = states;
    final available = !busy && widget.enabled && !loadFailed;
    if (widget.readOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!loaded && !loadFailed)
            const LinearProgressIndicator(minHeight: 2),
          if (loadFailed)
            TextButton(
              onPressed: busy ? null : _listen,
              child: const Text('Retry document statuses'),
            ),
          if (error != null)
            Text(error!, style: const TextStyle(color: AppColors.error)),
          for (final state in current)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  DocumentGlyph(
                    state.paper.name,
                    color: state.done ? AppColors.success : AppColors.muted,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      state.paper.label,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: state.done
                          ? AppColors.successSoft
                          : AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Waiting for the document: the same spinner as everywhere.
                        if (loaded &&
                            !loadFailed &&
                            !state.done &&
                            !state.skipped &&
                            state.waiting) ...[
                          const OnbWaitSpinner(
                            size: 12,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          !loaded || loadFailed
                              ? 'Not checked'
                              : state.done
                              ? 'Added'
                              : state.skipped
                              ? 'Skipped'
                              : state.waiting
                              ? 'Waiting'
                              : 'Not added',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: state.done
                                ? AppColors.success
                                : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: available && loaded && state.done
                        ? () => _view(state)
                        : null,
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                    tooltip: 'See ${state.paper.label}',
                  ),
                ],
              ),
            ),
        ],
      );
    }
    final allDone = current
        .where((state) => state.paper != RequestedPaper.linkedin)
        .every((state) => state.done);
    final allSent = current.every((state) => state.sent);
    final pending = current.where((state) => !state.done).length;
    final problems = current.where((state) => state.problem).length;
    final channels = current.map((state) => state.request?.channel).toSet();
    final sharedChannel = channels.length == 1 ? channels.single : null;
    final resends = current.where((state) => !state.done).toList();
    final canResend =
        available && resends.every((state) => _cooldown(state) == 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loadFailed) ...[
          const Text(
            'Could not load document statuses.',
            style: TextStyle(color: AppColors.error),
          ),
          TextButton(
            onPressed: busy ? null : _listen,
            child: const Text('Retry link statuses'),
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: const TextStyle(color: AppColors.error)),
          ),
        if (failedPaper != null)
          Container(
            margin: const EdgeInsets.only(top: 14, bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFDECEA),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const DocumentGlyph('warning', color: AppColors.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Link not sent',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.error,
                            ),
                          ),
                          Text(
                            'Could not open $failedChannel. Try another option.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: available
                          ? () => _send(failedPaper!, via: 'SMS')
                          : null,
                      icon: const DocumentGlyph('sms', size: 16),
                      label: const Text('Send by SMS'),
                    ),
                    TextButton.icon(
                      onPressed: available
                          ? () {
                              if (widget.party.email.trim().isEmpty) {
                                widget.onEditPerson?.call();
                              } else {
                                _send(failedPaper!, via: 'Email');
                              }
                            }
                          : null,
                      icon: const DocumentGlyph('email', size: 16),
                      label: const Text('Send by email'),
                    ),
                    if (widget.onEditPerson != null)
                      TextButton(
                        onPressed: available ? widget.onEditPerson : null,
                        child: const Text('Change number'),
                      ),
                  ],
                ),
              ],
            ),
          )
        else if (allSent && !allDone)
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(
                color: AppColors.successSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const DocumentGlyph(
                    'send',
                    size: 20,
                    color: Color(0xFF2FA866),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current.any(
                                (state) =>
                                    state.request?.paper == RequestedPaper.all,
                              )
                              ? 'Document link sent${sharedChannel == null ? '' : ' on $sharedChannel'}'
                              : '${current.length} links sent${sharedChannel == null ? '' : ' on $sharedChannel'}',
                          style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 20 / 15,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          problems > 0
                              ? '$problems documents have a problem'
                              : pending < current.length
                              ? '$pending ${pending == 1 ? 'document' : 'documents'} still waiting'
                              : 'One for each ${widget.includeLinkedIn ? 'detail' : 'document'} · ${BrokerPaperState.relativeTime(current.last.request!.sharedAtMs, currentTime)}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                            height: 18 / 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: canResend
                        ? () async {
                            final issued = <String>{};
                            for (final state in resends) {
                              final paper = state.request!.paper;
                              if (!issued.add(paper.name)) continue;
                              await _send(
                                paper,
                                remind: state.waiting,
                                via: sharedChannel,
                              );
                              if (!mounted) return;
                            }
                          }
                        : null,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppColors.success,
                      shape: const StadiumBorder(),
                    ),
                    icon: DocumentGlyph(
                      'sync',
                      size: 16,
                      color: canResend ? AppColors.success : AppColors.muted,
                    ),
                    label: const Text(
                      'Resend all',
                      style: TextStyle(
                        fontSize: 15,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w600,
                        height: 20 / 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (!allDone)
          const Divider(height: 32, color: Color(0xFFEDF1F6))
        else
          const SizedBox(height: 32),
        for (final state in current)
          _row(state, available: available, last: state == current.last),
      ],
    );
  }

  Widget _row(
    BrokerPaperState state, {
    required bool available,
    required bool last,
  }) {
    final cooling = _cooldown(state);
    final label = cooling > 0 && state.waiting
        ? 'Sent again · just now'
        : state.label(currentTime);
    final color = state.done
        ? const Color(0xFF2FA866)
        : state.problem || state.deleted
        ? AppColors.error
        : state.waiting
        ? const Color(0xFFFFA000)
        : AppColors.muted;
    final statusColor = state.done
        ? AppColors.success
        : state.problem || state.deleted
        ? AppColors.error
        : state.waiting
        ? AppColors.warning
        : AppColors.muted;
    return GestureDetector(
      onLongPress: available ? () => _options(state.paper) : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (highlighted == state.paper)
            Positioned(
              top: 0,
              bottom: 0,
              left: -4,
              right: -4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          Container(
            key: ValueKey('broker-paper-${state.paper.name}'),
            padding: const EdgeInsets.fromLTRB(0, 12, 4, 12),
            decoration: BoxDecoration(
              border: last || highlighted == state.paper
                  ? null
                  : const Border(bottom: BorderSide(color: Color(0xFFEDF1F6))),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 300;
                final actionWidth = constraints.maxWidth < 350 ? 44.0 : 60.0;
                final actions = [
                  if (state.done) ...[
                    DocumentRoundAction(
                      glyph: 'eye',
                      width: actionWidth,
                      label: 'See',
                      onTap: available ? () => _view(state) : null,
                    ),
                    const SizedBox(width: 8),
                    DocumentRoundAction(
                      glyph: 'sync',
                      width: actionWidth,
                      label: 'Change',
                      onTap: available ? () => _add(state) : null,
                    ),
                    const SizedBox(width: 8),
                    DocumentRoundAction(
                      glyph: 'trash',
                      width: actionWidth,
                      label: 'Delete',
                      red: true,
                      onTap: available ? () => _delete(state) : null,
                    ),
                  ] else if (state.waiting || state.problem) ...[
                    DocumentRoundAction(
                      glyph: cooling > 0
                          ? 'clock'
                          : state.request?.status == 'seen'
                          ? 'bell'
                          : state.problem
                          ? 'send'
                          : 'sync',
                      label: cooling > 0
                          ? '0:${cooling.toString().padLeft(2, '0')}'
                          : state.unclear
                          ? 'Ask again'
                          : state.expired
                          ? 'New link'
                          : state.request?.status == 'seen'
                          ? 'Remind'
                          : 'Resend',
                      green: true,
                      cooling: cooling > 0,
                      onTap: available && cooling == 0
                          ? () => _send(
                              state.paper,
                              remind:
                                  state.waiting &&
                                  state.request?.paper != RequestedPaper.all,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    DocumentRoundAction(
                      glyph: 'camera',
                      label: 'Add',
                      onTap: available ? () => _add(state) : null,
                    ),
                  ] else ...[
                    DocumentRoundAction(
                      glyph: 'camera',
                      label: 'Add',
                      onTap: available ? () => _add(state) : null,
                    ),
                    const SizedBox(width: 8),
                    DocumentRoundAction(
                      glyph: 'send',
                      label: 'Send link',
                      green: true,
                      onTap: available ? () => _send(state.paper) : null,
                    ),
                  ],
                ];
                final title = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.paper.label,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: AppColors.heading,
                        height: 22 / 17,
                      ),
                    ),
                    if (label.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (state.done ||
                                state.waiting ||
                                state.problem) ...[
                              DocumentGlyph(
                                state.done
                                    ? 'check'
                                    : state.problem
                                    ? 'warning'
                                    : state.request?.channel == 'Email'
                                    ? 'email'
                                    : state.request?.channel == 'SMS'
                                    ? 'sms'
                                    : state.request?.status == 'seen'
                                    ? 'check'
                                    : 'clock',
                                size: 14,
                                color: statusColor,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 18 / 13.5,
                                  color: statusColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                return Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: DocumentGlyph(
                        state.paper.name,
                        size: 24,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: compact && state.done
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                const SizedBox(height: 10),
                                Row(children: actions),
                              ],
                            )
                          : title,
                    ),
                    if (!(compact && state.done)) ...[
                      const SizedBox(width: 8),
                      ...actions,
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
