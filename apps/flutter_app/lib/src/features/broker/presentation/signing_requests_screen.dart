import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../agreement_copies/agreement_copies.dart';
import '../data/agreement_imports.dart';
import '../data/private_documents.dart';
import 'private_documents_screen.dart';

class SigningRequestsScreen extends StatefulWidget {
  const SigningRequestsScreen({
    this.gateway,
    this.admin = false,
    this.highlightId,
    this.offline = false,
    super.key,
  });
  final AgreementImportGateway? gateway;
  final bool admin;
  final String? highlightId;
  final bool offline;
  @override
  State<SigningRequestsScreen> createState() => _SigningRequestsScreenState();
}

class _SigningRequestsScreenState extends State<SigningRequestsScreen> {
  late final gateway = widget.gateway ?? FirebaseAgreementImportGateway();
  List<SigningRequest>? requests;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      requests = null;
      error = null;
    });
    try {
      final values = await gateway.list();
      if (mounted) setState(() => requests = values);
    } catch (failure) {
      if (mounted) _failure(failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _failure(Object failure) => setState(
    () => error = failure is DocumentFailure
        ? failure.message
        : 'Signing requests could not be loaded. Check your account and connection.',
  );
  Future<void> _view(SigningRequest request, bool signed) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await gateway.read(request.id, signed: signed);
      if (!mounted) return;
      await reviewPrivateDocument(
        context,
        file,
        upload: false,
        selectionOnly: true,
        reviewTitle: signed ? 'Signed original' : 'Submitted agreement pages',
        instructions: signed
            ? 'This is the privately uploaded externally signed original. Check every page.'
            : 'These are the uploaded source pages. They are not a completed signed original.',
      );
    } catch (failure) {
      if (mounted) _failure(failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _manage(SigningRequest request) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SigningTeamScreen(request: request, gateway: gateway),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.admin ? 'Signing-only requests' : 'Signing progress'),
      actions: [
        IconButton(
          onPressed: busy ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh actual progress',
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.offline)
            const Text('OFFLINE TEST · synthetic request, no legal signing'),
          const Text(
            'Progress updates only when the actual processing step is recorded. Uploading is not signing.',
          ),
          const SizedBox(height: 18),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(error!, style: const TextStyle(color: AppColors.error)),
          if (requests?.isEmpty == true)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text('No signing requests yet.'),
            ),
          for (final request in requests ?? <SigningRequest>[])
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: request.id == widget.highlightId
                      ? AppColors.primary
                      : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    request.stageLabel,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${request.pageCount} pages · ${request.signers.length} people',
                  ),
                  Text(
                    request.signers
                        .map((person) => '${person.name} (${person.role})')
                        .join(' · '),
                  ),
                  Text(
                    'Updated ${DateFormat('d MMM, h:mm a').format(request.updatedAt)}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: busy ? null : () => _view(request, false),
                    child: const Text('See original pages'),
                  ),
                  if (request.status == 'completed')
                    FilledButton.icon(
                      onPressed: busy ? null : () => _view(request, true),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('View signed agreement'),
                    ),
                  if (widget.admin && request.status != 'completed')
                    OutlinedButton(
                      onPressed: busy ? null : () => _manage(request),
                      child: const Text('Update actual progress'),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _SigningTeamScreen extends StatefulWidget {
  const _SigningTeamScreen({required this.request, required this.gateway});
  final SigningRequest request;
  final AgreementImportGateway gateway;
  @override
  State<_SigningTeamScreen> createState() => _SigningTeamScreenState();
}

class _SigningTeamScreenState extends State<_SigningTeamScreen> {
  final reference = TextEditingController();
  final note = TextEditingController();
  bool busy = false;
  bool checked = false;
  bool signed = false;
  AgreementPageFile? file;
  String? operationId;
  String? error;
  String? get next => switch (widget.request.status) {
    'received' => 'stamp_preparing',
    'stamp_preparing' => 'ready_to_sign',
    'ready_to_sign' => 'signing',
    _ => null,
  };
  @override
  void dispose() {
    reference.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selected = await pickAgreementCopy();
      if (selected == null || !mounted) return;
      final accepted = await reviewPrivateDocument(
        context,
        selected,
        upload: true,
        selectionOnly: true,
        reviewTitle: 'Review the genuine signed original',
        instructions:
            'Check every page against the submitted original, all signatures and stamp details. Do not upload an unsigned or demo PDF.',
      );
      if (accepted && mounted) {
        setState(() {
          file = AgreementPageFile(name: selected.name, bytes: selected.bytes);
          checked = false;
          signed = false;
          operationId = null;
        });
      }
    } catch (failure) {
      if (mounted) _fail(failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _fail(Object failure) => setState(
    () => error = failure is DocumentFailure
        ? failure.message
        : 'Update was not confirmed. Retry.',
  );
  Future<void> _save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (next != null) {
        await widget.gateway.record(
          widget.request,
          next!,
          reference.text,
          note.text,
        );
      } else {
        if (file == null || !checked || !signed) {
          throw const DocumentFailure(
            'Select the genuine signed PDF and confirm both checks.',
          );
        }
        operationId ??= importOperationId();
        await widget.gateway.publish(widget.request, file!, operationId!);
      }
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) _fail(failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Record actual processing')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.request.stageLabel,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            'Only record work that really happened. Portal signing is external; a completed legal original is uploaded privately here.',
          ),
          for (final person in widget.request.signers)
            ListTile(
              title: Text('${person.name} · ${person.role}'),
              subtitle: Text(person.phone),
            ),
          if (error != null)
            Text(error!, style: const TextStyle(color: AppColors.error)),
          if (next != null) ...[
            TextField(
              controller: reference,
              enabled: !busy,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Actual stamp / portal / delivery reference',
              ),
            ),
            TextField(
              controller: note,
              enabled: !busy,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Processing note'),
            ),
            Text(
              'Next stage: ${switch (next) {
                'stamp_preparing' => 'Buying stamp paper',
                'ready_to_sign' => 'Ready for signing',
                _ => 'Sent to everyone to sign',
              }}',
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: busy ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: Text(file?.name ?? 'Choose signed PDF'),
            ),
            CheckboxListTile(
              value: checked,
              onChanged: busy
                  ? null
                  : (value) => setState(() => checked = value == true),
              title: const Text(
                'I checked the original, stamp details and every page',
              ),
            ),
            CheckboxListTile(
              value: signed,
              onChanged: busy
                  ? null
                  : (value) => setState(() => signed = value == true),
              title: const Text(
                'Every required party has actually signed externally',
              ),
            ),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: busy
                ? 'Saving…'
                : next == null
                ? 'Publish signed original'
                : 'Record actual next stage',
            onPressed: busy ? null : _save,
          ),
        ],
      ),
    ),
  );
}
