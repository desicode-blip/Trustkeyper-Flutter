import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../broker/data/private_documents.dart';
import '../broker/presentation/private_documents_screen.dart';
import 'agreement_copies.dart';

class AdminCopyUploadScreen extends StatefulWidget {
  const AdminCopyUploadScreen({
    required this.agreementId,
    required this.revision,
    required this.property,
    this.gateway,
    this.picker,
    this.review,
    super.key,
  });
  final String agreementId;
  final int revision;
  final String property;
  final AgreementCopyGateway? gateway;
  final Future<AgreementCopyFile?> Function()? picker;
  final Future<bool> Function(AgreementCopyFile file)? review;
  @override
  State<AdminCopyUploadScreen> createState() => _AdminCopyUploadScreenState();
}

class _AdminCopyUploadScreenState extends State<AdminCopyUploadScreen> {
  late final gateway = widget.gateway ?? FirebaseAgreementCopyGateway();
  final template = TextEditingController();
  AgreementCopyFile? file;
  AgreementCopyRequest? pending;
  String mode = 'demo';
  bool approved = false;
  bool signed = false;
  bool matches = false;
  bool busy = false;
  bool complete = false;
  String? error;
  bool get editable => !busy && pending == null && !complete;
  @override
  void dispose() {
    template.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selected = await (widget.picker ?? pickAgreementCopy)();
      if (selected == null || !mounted) return;
      selected.validate();
      final bool accepted;
      if (widget.review != null) {
        accepted = await widget.review!(selected);
      } else {
        if (!context.mounted) return;
        accepted = await reviewPrivateDocument(
          context,
          selected,
          upload: true,
          selectionOnly: true,
          reviewTitle: 'Review every page of the final copy',
          instructions:
              'Check all names, dates, amounts, stamp details and signatures against the reviewed version. A demo PDF is never a signed legal agreement.',
        );
      }
      if (accepted && mounted) {
        setState(() {
          file = selected;
          approved = false;
          signed = false;
          matches = false;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : 'Could not select this PDF. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _publish() async {
    if (file == null || busy) return;
    if (pending == null &&
        mode == 'externally_signed' &&
        (!approved || !signed || !matches || template.text.trim().length < 5)) {
      setState(
        () => error =
            'Identify the approved original and confirm all three checks.',
      );
      return;
    }
    pending ??= AgreementCopyRequest(
      agreementId: widget.agreementId,
      revision: widget.revision,
      operationId: gateway.operationId(),
      file: file!,
      mode: mode,
      templateName: template.text.trim(),
      approvedOriginal: approved,
      allPartiesSigned: signed,
      matchesReviewedTerms: matches,
    );
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await gateway.publish(pending!);
      if (mounted) {
        setState(() {
          complete = true;
          pending = null;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : 'Upload not confirmed. Keep this selected file and retry the same upload.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Publish agreement copy')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.property,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          Text('Saved version ${widget.revision} · ${widget.agreementId}'),
          const SizedBox(height: 16),
          const Text(
            'Signing is completed on the external portal. Upload the completed original here. Customers see their agreement status and private copy, not this processing screen.',
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: AppColors.error)),
          if (complete)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Copy published and confirmed by the server.',
                style: TextStyle(color: AppColors.success),
              ),
            )
          else ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: mode,
              decoration: const InputDecoration(labelText: 'Document class'),
              items: const [
                DropdownMenuItem(
                  value: 'demo',
                  child: Text('Demo PDF · not signed'),
                ),
                DropdownMenuItem(
                  value: 'externally_signed',
                  child: Text('Externally signed legal PDF'),
                ),
              ],
              onChanged: editable
                  ? (value) => setState(() => mode = value!)
                  : null,
            ),
            if (mode == 'externally_signed') ...[
              const SizedBox(height: 16),
              TextField(
                controller: template,
                enabled: editable,
                decoration: const InputDecoration(
                  labelText: 'Approved legal original / template reference',
                ),
              ),
              CheckboxListTile(
                value: approved,
                title: const Text(
                  'This is an approved legal original, not the demo template',
                ),
                onChanged: editable
                    ? (value) => setState(() => approved = value == true)
                    : null,
              ),
              CheckboxListTile(
                value: signed,
                title: const Text(
                  'Every owner and tenant signed on the external portal',
                ),
                onChanged: editable
                    ? (value) => setState(() => signed = value == true)
                    : null,
              ),
              CheckboxListTile(
                value: matches,
                title: const Text(
                  'All pages match the exact reviewed terms and people',
                ),
                onChanged: editable
                    ? (value) => setState(() => matches = value == true)
                    : null,
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: editable ? _pick : null,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(file?.name ?? 'Choose and review PDF'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy || file == null ? null : _publish,
              child: Text(
                pending == null ? 'Publish private copy' : 'Retry same upload',
              ),
            ),
          ],
          if (busy) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          const Text(
            'No SMS/email delivery, payment, signature provider verification or move-in completion is inferred from uploading. The legal copy and admin attestations are retained privately with a checksum and audit trail.',
          ),
        ],
      ),
    ),
  );
}
