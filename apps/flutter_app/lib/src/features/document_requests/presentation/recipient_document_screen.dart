import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../broker/data/private_documents.dart';
import '../../broker/presentation/private_documents_screen.dart';
import '../data/document_request_repository.dart';
import '../data/recipient_document_gateway.dart';
import 'recipient_document_layout.dart';

class RecipientDocumentScreen extends StatefulWidget {
  const RecipientDocumentScreen({
    required this.token,
    this.gateway,
    this.pickFile,
    this.reviewFile,
    this.networkTimeout = const Duration(seconds: 45),
    super.key,
  });
  final String token;
  final RecipientDocumentGateway? gateway;
  final Future<DocumentFile?> Function(bool camera)? pickFile;
  final Future<bool> Function(DocumentFile file)? reviewFile;
  final Duration networkTimeout;
  @override
  State<RecipientDocumentScreen> createState() =>
      _RecipientDocumentScreenState();
}

class _RecipientDocumentScreenState extends State<RecipientDocumentScreen> {
  RecipientDocumentGateway? gateway;
  DocumentRequestInfo? info;
  final code = TextEditingController();
  final files = <DocumentKind, DocumentFile>{};
  Timer? timer;
  int generation = 0;
  int loadSequence = 0;
  int cooldown = 0;
  bool loading = true;
  bool busy = false;
  bool otpSent = false;
  bool choosingFile = false;
  Completer<DocumentFile?>? selectionCancelled;
  double? progress;
  String? error;
  Map<String, dynamic>? bankDetails;
  Map<String, dynamic>? linkedInDetails;
  StreamSubscription<String?>? identitySubscription;
  String? recipientUid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RecipientDocumentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token ||
        oldWidget.gateway != widget.gateway) {
      generation++;
      _clearSelection();
      identitySubscription?.cancel();
      identitySubscription = null;
      timer?.cancel();
      gateway = null;
      info = null;
      files.clear();
      bankDetails = null;
      linkedInDetails = null;
      code.clear();
      otpSent = false;
      cooldown = 0;
      busy = false;
      _load();
    }
  }

  @override
  void dispose() {
    generation++;
    _clearSelection();
    timer?.cancel();
    identitySubscription?.cancel();
    code.dispose();
    super.dispose();
  }

  bool _current(int request) => mounted && request == generation;
  void _clearSelection() {
    if (selectionCancelled?.isCompleted == false) {
      selectionCancelled!.complete(null);
    }
    selectionCancelled = null;
    choosingFile = false;
  }

  String _message(Object failure) {
    if (failure is TimeoutException) {
      return 'This is taking too long. Check your connection and try again. Your selected details have not been sent.';
    }
    if (failure is DocumentFailure) return failure.message;
    if (failure is FirebaseAuthException) {
      return switch (failure.code) {
        'invalid-verification-code' => 'That code is incorrect. Try again.',
        'session-expired' => 'That code expired. Request a new code.',
        'too-many-requests' => 'Too many attempts. Wait before trying again.',
        _ => 'Phone verification failed. Check your connection and retry.',
      };
    }
    if (failure is FirebaseFunctionsException) {
      return switch (failure.code) {
        'failed-precondition' =>
          'This link is old, expired, or changed. Ask the broker for a new link.',
        'permission-denied' =>
          'Verify the phone number on this request. Contact the broker if it is incorrect.',
        'invalid-argument' =>
          failure.message ?? 'Add every requested page before sending.',
        _ => 'Could not confirm this request. Check your connection and retry.',
      };
    }
    return 'Could not complete this action. Check your connection and retry.';
  }

  Future<void> _load() async {
    final request = generation;
    final sequence = ++loadSequence;
    bool current() => _current(request) && sequence == loadSequence;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (!RegExp(r'^[a-f0-9]{64}\.[\w-]{43}$').hasMatch(widget.token)) {
        throw const DocumentFailure(
          'This link is incomplete or unavailable. Ask the broker for a new link.',
        );
      }
      final service =
          gateway ??
          widget.gateway ??
          await FirebaseRecipientDocumentGateway.create().timeout(
            widget.networkTimeout,
          );
      final result = await service
          .read(widget.token)
          .timeout(widget.networkTimeout);
      if (!current()) return;
      gateway = service;
      if (service is RecipientVerificationSession &&
          identitySubscription == null) {
        final session = service as RecipientVerificationSession;
        recipientUid = session.currentUid;
        identitySubscription = session.identities.distinct().listen((uid) {
          if (!mounted || uid == recipientUid) return;
          recipientUid = uid;
          final waitingForOtp = otpSent;
          generation++;
          _clearSelection();
          timer?.cancel();
          final route = ModalRoute.of(context);
          if (route?.isActive == true) {
            Navigator.of(context).popUntil((candidate) => candidate == route);
          }
          setState(() {
            files.clear();
            bankDetails = null;
            linkedInDetails = null;
            info = null;
            code.clear();
            otpSent = uid != null && waitingForOtp;
            busy = false;
            progress = null;
            cooldown = 0;
          });
          _load();
        });
      }
      setState(() {
        info = result;
        if (result.status == 'added') files.clear();
      });
    } catch (failure) {
      if (current()) {
        setState(() {
          error = _message(failure);
        });
      }
    } finally {
      if (current()) setState(() => loading = false);
    }
  }

  Future<void> _run(Future<void> Function(int request) action) async {
    if (busy || loading) return;
    final request = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action(request);
    } catch (failure) {
      if (_current(request)) setState(() => error = _message(failure));
    } finally {
      if (_current(request)) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  void _startCooldown() {
    timer?.cancel();
    setState(() => cooldown = 60);
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || cooldown <= 1) {
        timer.cancel();
        if (mounted) setState(() => cooldown = 0);
      } else {
        setState(() => cooldown--);
      }
    });
  }

  Future<void> _requestOtp() => _run((request) async {
    final result = await gateway!.requestOtp(info!.phone);
    if (!_current(request)) return;
    code.clear();
    setState(() => otpSent = !result);
    _startCooldown();
    if (result) await _load();
  });
  Future<void> _verify() => _run((request) async {
    if (code.text.length != 6) {
      throw const DocumentFailure('Enter the six-digit code.');
    }
    await gateway!.verifyOtp(code.text).timeout(widget.networkTimeout);
    if (_current(request)) {
      code.clear();
      await _load();
    }
  });
  Future<void> _pick(DocumentKind kind, bool camera) => _run((request) async {
    if (info?.verified != true) {
      throw const DocumentFailure(
        'Verify your phone before adding a document.',
      );
    }
    setState(() => choosingFile = true);
    final cancellation = Completer<DocumentFile?>();
    selectionCancelled = cancellation;
    DocumentFile? file;
    try {
      file = await Future.any([
        widget.pickFile?.call(camera) ?? pickPrivateDocument(camera: camera),
        cancellation.future,
      ]).timeout(const Duration(minutes: 2));
    } finally {
      if (selectionCancelled == cancellation) selectionCancelled = null;
      if (_current(request)) setState(() => choosingFile = false);
    }
    if (file == null || !mounted || request != generation) return;
    final selectedFile = file;
    selectedFile.validate();
    final accepted =
        await (widget.reviewFile?.call(selectedFile) ??
            reviewPrivateDocument(
              context,
              selectedFile,
              upload: true,
              selectionOnly: true,
            ));
    if (accepted && _current(request)) {
      setState(() {
        files[kind] = selectedFile;
        if (kind == DocumentKind.bankProof) bankDetails = null;
      });
    }
  });
  Future<void> _remove(DocumentKind kind) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${kind.label}?'),
        content: const Text('This selected file has not been sent yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted && !busy) {
      setState(() => files.remove(kind));
    }
  }

  Future<void> _submit() => _run((request) async {
    await _requireProof();
    final selected = Map<DocumentKind, DocumentFile>.from(files);
    if (!info!.slots.every(
      (kind) =>
          selected.containsKey(kind) ||
          kind == DocumentKind.bankProof && bankDetails != null,
    )) {
      throw const DocumentFailure('Add every requested page before sending.');
    }
    try {
      final result = await gateway!.submit(
        widget.token,
        selected,
        (value) {
          if (_current(request)) setState(() => progress = value);
        },
        bankDetails: bankDetails,
        linkedInDetails: linkedInDetails,
      );
      if (result.status != 'added' || !result.verified) {
        throw const DocumentFailure(
          'The submission is not confirmed. Retry sending.',
        );
      }
      if (_current(request)) {
        setState(() {
          info = result;
          files.clear();
        });
      }
    } catch (failure) {
      if (_current(request)) {
        try {
          final result = await gateway!
              .read(widget.token)
              .timeout(widget.networkTimeout);
          if (_current(request) &&
              result.status == 'added' &&
              result.verified) {
            setState(() {
              info = result;
              files.clear();
            });
            return;
          }
        } catch (_) {}
      }
      rethrow;
    }
  });
  Future<void> _signOut() => _run((request) async {
    await gateway!.signOut();
    if (_current(request)) {
      files.clear();
      bankDetails = null;
      linkedInDetails = null;
      otpSent = false;
      await _load();
    }
  });
  @override
  Widget build(BuildContext context) => RecipientDocumentLayout(
    key: ValueKey(widget.token),
    info: info,
    loading: loading,
    busy: busy,
    progress: progress,
    error: error,
    otpSent: otpSent,
    cooldown: cooldown,
    code: code,
    files: files,
    bankDetails: bankDetails,
    linkedInDetails: linkedInDetails,
    onRequestOtp: _requestOtp,
    onVerify: _verify,
    onReload: _load,
    onSignOut: _signOut,
    onSubmit: _submit,
    onPick: _pick,
    onRemove: _remove,
    onView: (kind) => _run((request) async {
      if (info?.verified != true) {
        throw const DocumentFailure(
          'Verify your phone before viewing a document.',
        );
      }
      final file = files[kind];
      if (file != null && context.mounted) {
        await reviewPrivateDocument(context, file, upload: false);
      }
    }),
    onBank: (value) => setState(() {
      bankDetails = value;
      files.remove(DocumentKind.bankProof);
    }),
    onLinkedIn: (value) async {
      setState(() => linkedInDetails = value);
      if (info?.paper == RequestedPaper.linkedin) await _submit();
    },
    onCancelSelection: choosingFile
        ? () {
            _clearSelection();
            generation++;
            setState(() {
              choosingFile = false;
              busy = false;
              progress = null;
            });
          }
        : null,
  );

  Future<void> _requireProof() async {
    final current = await gateway!
        .read(widget.token)
        .timeout(widget.networkTimeout);
    if (!mounted) throw const DocumentFailure('Reopen this link.');
    if (!current.verified || current.version != info?.version) {
      setState(() {
        files.clear();
        bankDetails = null;
        info = current;
      });
      throw const DocumentFailure(
        'Your verification changed. Reopen this link.',
      );
    }
  }
}
