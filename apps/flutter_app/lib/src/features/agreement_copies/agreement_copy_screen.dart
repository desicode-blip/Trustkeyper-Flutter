import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_brand.dart';
import '../broker/data/private_documents.dart';
import '../broker/data/private_pdf_reference.dart';
import 'agreement_copies.dart';

class AgreementCopyScreen extends StatefulWidget {
  const AgreementCopyScreen({
    required this.agreementId,
    required this.revision,
    required this.demo,
    this.gateway,
    this.reader,
    this.role,
    this.onDashboard,
    this.onPayments,
    super.key,
  });
  final String agreementId;
  final int revision;
  final bool demo;
  final AgreementCopyGateway? gateway;
  final Future<AgreementCopyFile> Function()? reader;
  final String? role;
  final VoidCallback? onDashboard;
  final VoidCallback? onPayments;
  @override
  State<AgreementCopyScreen> createState() => _AgreementCopyScreenState();
}

class _AgreementCopyScreenState extends State<AgreementCopyScreen> {
  AgreementCopyFile? file;
  PdfDocumentRef? pdf;
  String? error;
  bool busy = true;
  int? pages;
  bool viewing = false;
  bool get demo =>
      file?.mode != null ? file!.mode != 'externally_signed' : widget.demo;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
      file = null;
      pdf = null;
    });
    try {
      final result = widget.reader != null
          ? await widget.reader!()
          : await (widget.gateway ?? FirebaseAgreementCopyGateway()).read(
              widget.agreementId,
              widget.revision,
            );
      if (!mounted) return;
      setState(() {
        file = result;
        pdf = privatePdfReference(result);
      });
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : 'The private PDF could not be opened. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await FilePicker.saveFile(
        fileName: file!.name,
        bytes: file!.bytes,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (mounted && saved != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Agreement copy saved.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save the file. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !viewing,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && viewing) setState(() => viewing = false);
    },
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => viewing
              ? setState(() => viewing = false)
              : Navigator.pop(context),
        ),
        title: viewing
            ? Text(demo ? 'Demo agreement copy' : 'Signed agreement')
            : const AppBrand(height: 32),
        actions: !viewing && ['owner', 'tenant'].contains(widget.role)
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Chip(
                    avatar: const Icon(
                      Icons.person_outline,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    label: Text(widget.role == 'owner' ? 'Owner' : 'Tenant'),
                    backgroundColor: const Color(0xFFEAF0FF),
                    side: BorderSide.none,
                  ),
                ),
              ]
            : null,
      ),
      body: !viewing
          ? _summary()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        demo
                            ? 'Demo only · not a signed legal agreement'
                            : 'Your signed agreement is ready',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        pages == null
                            ? 'Private PDF · version ${widget.revision}'
                            : 'PDF · $pages pages · version ${widget.revision}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      if (error != null)
                        Text(
                          error!,
                          style: const TextStyle(color: AppColors.error),
                        ),
                    ],
                  ),
                ),
                if (pdf != null)
                  Expanded(
                    child: PdfViewer(
                      pdf!,
                      params: PdfViewerParams(
                        onViewerReady: (document, controller) {
                          if (mounted) {
                            setState(() => pages = document.pages.length);
                          }
                        },
                        errorBannerBuilder:
                            (
                              context,
                              failure,
                              stack,
                              reference,
                            ) => const Center(
                              child: Text(
                                'This PDF cannot be rendered. Save it to inspect the copy.',
                              ),
                            ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Center(
                      child: busy
                          ? const CircularProgressIndicator()
                          : TextButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: viewing
              ? FilledButton.icon(
                  onPressed: busy || file == null ? null : _save,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Save agreement'),
                )
              : FilledButton(
                  onPressed: busy || file == null
                      ? null
                      : widget.onDashboard ??
                            () => setState(() => viewing = true),
                  child: Text(
                    widget.onDashboard == null
                        ? 'Read agreement'
                        : 'Open my dashboard',
                  ),
                ),
        ),
      ),
    ),
  );

  Widget _summary() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 8),
      Center(
        child: Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: demo ? const Color(0xFFEAF0FF) : const Color(0xFFE6F7EF),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: demo ? AppColors.primary : AppColors.success,
            ),
            child: Icon(
              demo ? Icons.description_outlined : Icons.check,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        demo
            ? 'Demo agreement copy'
            : file?.partyCount == null
            ? 'Your signed agreement is ready'
            : 'Agreement signed by all ${file!.partyCount}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      Text(
        demo
            ? 'Demo only · not a signed legal agreement'
            : 'Your signed copy is ready to read and save.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted, fontSize: 16),
      ),
      const SizedBox(height: 20),
      if (widget.onPayments != null) ...[
        FilledButton.icon(
          onPressed: busy || file == null ? null : widget.onPayments,
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: const Text('Pay rent and deposit · test'),
        ),
        const SizedBox(height: 16),
      ],
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDEDEA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.picture_as_pdf_outlined,
                color: AppColors.error,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: file == null || busy
                    ? null
                    : () => setState(() => viewing = true),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      demo ? 'Demo agreement' : 'Signed agreement',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      pages == null
                          ? 'Private PDF · version ${widget.revision}'
                          : 'PDF · $pages pages · version ${widget.revision}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: file == null || busy ? null : _save,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
      if (file?.startDate != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Tenants move in',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              Text(
                DateFormat('d MMM yyyy').format(file!.startDate!),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
      if (busy)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (error != null) ...[
        const SizedBox(height: 12),
        Text(error!, style: const TextStyle(color: AppColors.error)),
        if (file == null)
          TextButton(onPressed: _load, child: const Text('Retry')),
      ],
    ],
  );
}
