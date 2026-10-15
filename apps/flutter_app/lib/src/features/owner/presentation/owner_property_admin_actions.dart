import 'package:flutter/material.dart';
import '../../agreement_copies/agreement_copies.dart';
import '../../broker/data/agreement_imports.dart';
import '../../broker/data/private_documents.dart';
import '../../broker/presentation/private_documents_screen.dart';
import '../data/owner_properties.dart';
import '../data/owner_lifecycle.dart';

class OwnerPropertyAdminActions extends StatelessWidget {
  const OwnerPropertyAdminActions({
    required this.property,
    required this.onChanged,
    this.gateway,
    super.key,
  });
  final OwnerPropertyRecord property;
  final VoidCallback onChanged;
  final OwnerLifecycleGateway? gateway;
  Future<void> _photos(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OwnerPropertyPhotoDialog(property: property),
    );
    if (changed == true) onChanged();
  }

  Future<void> _upload(BuildContext context, String kind) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ContractUploadDialog(
        property: property,
        kind: kind,
        gateway: gateway ?? FirebaseOwnerLifecycleGateway(),
      ),
    );
    if (changed == true) onChanged();
  }

  Future<void> _tenant(
    BuildContext context,
    String candidateId,
    bool link,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TenantRecordDialog(
        property: property,
        candidateId: candidateId,
        link: link,
        gateway: gateway ?? FirebaseOwnerLifecycleGateway(),
      ),
    );
    if (changed == true) onChanged();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (property.nextStep == 4 &&
          property.photos.length < 5 &&
          [
            'draft',
            'property_added',
            'check_requested',
            'check_confirmed',
            'fee_offered',
            'contract_accepted',
            'plan_active',
            'listing_paused',
          ].contains(property.status))
        TextButton.icon(
          onPressed: () => _photos(context),
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Add reviewed team property photo'),
        ),
      if (property.status == 'fee_offered')
        TextButton.icon(
          onPressed: () => _upload(context, 'source'),
          icon: const Icon(Icons.upload_file),
          label: Text(
            property.data['contract'] == null
                ? 'Publish actual owner contract'
                : 'Replace unaccepted contract terms',
          ),
        ),
      if (property.status == 'contract_accepted')
        TextButton.icon(
          onPressed: () => _upload(context, 'signed'),
          icon: const Icon(Icons.upload_file),
          label: const Text('Publish genuine externally signed owner contract'),
        ),
      for (final entry in (property.data['candidates'] as Map? ?? {}).entries)
        if ([
          'interested',
          'visit_confirmed',
          'chosen',
        ].contains(entry.value['status']))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${entry.value['name']} · ${entry.value['phone']}'),
                  Text(
                    '${entry.value['household']} people · ${entry.value['work']} · move in ${entry.value['moveIn']}',
                  ),
                  if (entry.value['status'] != 'chosen')
                    TextButton(
                      onPressed: () =>
                          _tenant(context, entry.key as String, false),
                      child: Text(
                        entry.value['identityCheck']?['checked'] == true
                            ? 'Update identity evidence reference'
                            : 'Record actual identity check',
                      ),
                    ),
                  if (entry.value['status'] == 'chosen')
                    TextButton(
                      onPressed: () =>
                          _tenant(context, entry.key as String, true),
                      child: const Text(
                        'Link actual prepared tenancy agreement',
                      ),
                    ),
                ],
              ),
            ),
          ),
    ],
  );
}

class _OwnerPropertyPhotoDialog extends StatefulWidget {
  const _OwnerPropertyPhotoDialog({required this.property});
  final OwnerPropertyRecord property;
  @override
  State<_OwnerPropertyPhotoDialog> createState() =>
      _OwnerPropertyPhotoDialogState();
}

class _OwnerPropertyPhotoDialogState extends State<_OwnerPropertyPhotoDialog> {
  final gateway = FirebaseOwnerPropertyGateway();
  AgreementPageFile? selected;
  List<AgreementPageFile>? existing;
  String? operationId;
  bool busy = false;
  String? error;
  Future<void> _pick() async {
    try {
      final file = await pickPrivateDocument();
      if (file == null || !mounted) return;
      if (file.contentType == 'application/pdf') {
        throw const DocumentFailure('Choose a JPG or PNG property photo.');
      }
      final accepted = await reviewPrivateDocument(
        context,
        file,
        upload: true,
        selectionOnly: true,
        reviewTitle: 'Review actual team property photo',
        instructions:
            'Confirm this is the actual property. Do not include identity documents, phone numbers, people or other private details.',
      );
      if (accepted && mounted) {
        setState(() {
          selected = AgreementPageFile(name: file.name, bytes: file.bytes);
          operationId = null;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : 'The photo could not be read.',
        );
      }
    }
  }

  Future<void> _upload() async {
    if (selected == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (existing == null) {
        final received = <AgreementPageFile>[];
        for (var index = 0; index < widget.property.photos.length; index++) {
          received.add(
            await gateway.readPhoto(widget.property, index, admin: true),
          );
        }
        existing = received;
      }
      await gateway.uploadPhotos(
        widget.property,
        [...existing!, selected!],
        operationId ??= importOperationId(),
        admin: true,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : 'The photo upload was not confirmed. Retry the same file.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Team property photo'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Up to five actual JPG/PNG photos, 10 MB each and 20 MB total. Nothing becomes public until the owner approves the listing.',
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          TextButton(
            onPressed: busy ? null : _pick,
            child: Text(selected?.name ?? 'Select and review actual photo'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy || selected == null ? null : _upload,
        child: const Text('Save private photo'),
      ),
    ],
  );
}

class _ContractUploadDialog extends StatefulWidget {
  const _ContractUploadDialog({
    required this.property,
    required this.kind,
    required this.gateway,
  });
  final OwnerPropertyRecord property;
  final String kind;
  final OwnerLifecycleGateway gateway;
  @override
  State<_ContractUploadDialog> createState() => _ContractUploadDialogState();
}

class _ContractUploadDialogState extends State<_ContractUploadDialog> {
  final reference = TextEditingController();
  AgreementPageFile? file;
  String? operationId;
  String? error;
  bool checked = false;
  bool signatures = false;
  bool busy = false;
  @override
  void dispose() {
    reference.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final selected = await pickAgreementCopy();
    if (selected == null || !mounted) {
      return;
    }
    final reviewed = await reviewPrivateDocument(
      context,
      selected,
      upload: true,
      selectionOnly: true,
      reviewTitle: widget.kind == 'signed'
          ? 'Review the externally signed owner contract'
          : 'Review the complete owner contract',
      instructions:
          'Check every page, the owner, property, plan, 5–20% fee and effective date. Signed copies also require every signature. This must be the actual original, not a demo agreement.',
    );
    if (reviewed && mounted) {
      setState(() {
        file = AgreementPageFile(name: selected.name, bytes: selected.bytes);
        checked = false;
        signatures = false;
        operationId = null;
      });
    }
  }

  Future<void> _send() async {
    if (file == null ||
        !checked ||
        widget.kind == 'signed' && !signatures ||
        reference.text.trim().length < 3) {
      setState(
        () => error =
            'Review the actual original and enter its evidence reference.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.gateway.uploadContract(
        widget.property,
        file!,
        widget.kind,
        reference.text.trim(),
        operationId ??= importOperationId(),
        signaturesChecked: signatures,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : 'Upload was not confirmed. The PDF is retained for retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.kind == 'signed'
          ? 'Signed owner contract'
          : 'Owner contract terms',
    ),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'An OTP consent record is not a completed externally signed legal original. Upload only the actual checked PDF. No rent or payout is triggered.',
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            TextButton.icon(
              onPressed: busy ? null : _pick,
              icon: const Icon(Icons.attach_file),
              label: Text(file?.name ?? 'Select and review PDF'),
            ),
            TextField(
              controller: reference,
              maxLength: 200,
              enabled: !busy,
              onChanged: (_) => operationId = null,
              decoration: const InputDecoration(
                labelText: 'Actual contract/signing evidence reference',
              ),
            ),
            CheckboxListTile(
              value: checked,
              onChanged: busy
                  ? null
                  : (value) => setState(() => checked = value == true),
              title: const Text(
                'I checked every page and its owner, home, plan, fee and date',
              ),
            ),
            if (widget.kind == 'signed')
              CheckboxListTile(
                value: signatures,
                onChanged: busy
                    ? null
                    : (value) => setState(() => signatures = value == true),
                title: const Text(
                  'All required parties signed this original externally',
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : _send,
        child: const Text('Publish checked PDF'),
      ),
    ],
  );
}

class _TenantRecordDialog extends StatefulWidget {
  const _TenantRecordDialog({
    required this.property,
    required this.candidateId,
    required this.link,
    required this.gateway,
  });
  final OwnerPropertyRecord property;
  final String candidateId;
  final bool link;
  final OwnerLifecycleGateway gateway;
  @override
  State<_TenantRecordDialog> createState() => _TenantRecordDialogState();
}

class _TenantRecordDialogState extends State<_TenantRecordDialog> {
  final value = TextEditingController();
  bool checked = false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!checked || value.text.trim().length < (widget.link ? 1 : 3)) {
      setState(
        () => error = 'Enter the actual reference and confirm your review.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.gateway.change(
        widget.property,
        widget.link ? 'link_agreement' : 'check_tenant',
        {
          'candidateId': widget.candidateId,
          if (widget.link)
            'agreementId': value.text.trim()
          else ...{
            'reference': value.text.trim(),
            'identityChecked': true,
          },
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : 'The record was not confirmed. Refresh and retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.link
          ? 'Link prepared agreement'
          : 'Record actual tenant identity check',
    ),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          TextField(
            controller: value,
            enabled: !busy,
            maxLength: widget.link ? 150 : 200,
            decoration: InputDecoration(
              labelText: widget.link
                  ? 'Existing tenancy agreement ID'
                  : 'Reviewed identity evidence reference',
            ),
          ),
          CheckboxListTile(
            value: checked,
            onChanged: busy
                ? null
                : (value) => setState(() => checked = value == true),
            title: Text(
              widget.link
                  ? 'I checked the actual property, owner and selected tenant'
                  : 'I checked the actual consenting tenant’s identity evidence',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : _save,
        child: const Text('Record verified details'),
      ),
    ],
  );
}
