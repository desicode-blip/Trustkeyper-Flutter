import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_brand.dart';
import '../../broker/data/private_documents.dart';
import '../data/document_request_repository.dart';
import 'document_request_widgets.dart';
import 'recipient_bank_fields.dart';
import 'linkedin_profile_fields.dart';

class RecipientDocumentLayout extends StatefulWidget {
  const RecipientDocumentLayout({
    required this.info,
    required this.loading,
    required this.busy,
    required this.progress,
    required this.error,
    required this.otpSent,
    required this.cooldown,
    required this.code,
    required this.files,
    required this.bankDetails,
    required this.onRequestOtp,
    required this.onVerify,
    required this.onReload,
    required this.onSignOut,
    required this.onSubmit,
    required this.onPick,
    required this.onRemove,
    required this.onView,
    required this.onBank,
    this.linkedInDetails,
    this.onLinkedIn,
    this.onCancelSelection,
    super.key,
  });
  final DocumentRequestInfo? info;
  final bool loading, busy, otpSent;
  final double? progress;
  final String? error;
  final int cooldown;
  final TextEditingController code;
  final Map<DocumentKind, DocumentFile> files;
  final Map<String, dynamic>? bankDetails;
  final Map<String, dynamic>? linkedInDetails;
  final Future<void> Function(Map<String, dynamic>)? onLinkedIn;
  final VoidCallback? onCancelSelection;
  final Future<void> Function() onRequestOtp,
      onVerify,
      onReload,
      onSignOut,
      onSubmit;
  final Future<void> Function(DocumentKind, bool) onPick;
  final Future<void> Function(DocumentKind) onRemove, onView;
  final ValueChanged<Map<String, dynamic>> onBank;
  @override
  State<RecipientDocumentLayout> createState() =>
      _RecipientDocumentLayoutState();
}

class _RecipientDocumentLayoutState extends State<RecipientDocumentLayout> {
  bool entered = false;
  RequestedPaper? editing;
  String? bankMethod;
  bool get verified => widget.info?.verified == true;
  bool get received => verified && widget.info?.status == 'added';
  bool _ready(RequestedPaper paper) => paper == RequestedPaper.linkedin
      ? widget.linkedInDetails != null
      : (paper == RequestedPaper.all
                ? widget.info?.slots ?? paper.slots
                : paper.slots)
            .every(
              (kind) =>
                  widget.files.containsKey(kind) ||
                  kind == DocumentKind.bankProof && widget.bankDetails != null,
            );
  @override
  void didUpdateWidget(covariant RecipientDocumentLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info?.verified != true && verified && widget.otpSent) {
      entered = true;
    }
    if (!verified) {
      entered = false;
      editing = null;
      bankMethod = null;
    }
  }

  void _back() {
    if (widget.busy) return;
    setState(() {
      if (bankMethod != null) {
        bankMethod = null;
      } else if (editing != null) {
        editing = null;
      } else {
        entered = false;
      }
    });
  }

  Widget _heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 26,
          height: 32 / 26,
          fontWeight: FontWeight.w700,
          color: AppColors.heading,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        subtitle,
        style: const TextStyle(
          fontSize: 17,
          height: 24 / 17,
          color: AppColors.muted,
        ),
      ),
    ],
  );
  Widget _header() => Container(
    padding: entered
        ? const EdgeInsets.fromLTRB(24, 18, 24, 18)
        : const EdgeInsets.fromLTRB(24, 18, 24, 0),
    decoration: BoxDecoration(
      border: entered
          ? const Border(bottom: BorderSide(color: Color(0xFFEDF1F6)))
          : null,
    ),
    child: Row(
      children: [
        if (editing != null)
          SizedBox(
            width: 44,
            height: 36,
            child: IconButton.outlined(
              onPressed: widget.busy ? null : _back,
              tooltip: 'Back to documents',
              icon: const Icon(Icons.chevron_left),
            ),
          )
        else
          const AppBrand(height: 34),
        const Spacer(),
        if (entered && verified) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 14,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.info!.role == 'owner' ? 'Owner' : 'Tenant',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Request updates'),
                  content: Text(
                    widget.info!.status == 'added'
                        ? 'Your documents have been received.'
                        : widget.info!.reason.isEmpty
                        ? 'Your broker is waiting for your documents.'
                        : widget.info!.reason,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.notifications_none),
              tooltip: 'Request updates',
              padding: EdgeInsets.zero,
            ),
          ),
        ] else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                Icon(Icons.language, size: 16),
                SizedBox(width: 8),
                Text(
                  'English',
                  style: TextStyle(fontSize: 14, color: AppColors.heading),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  Widget _landing(DocumentRequestInfo request) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!widget.otpSent) ...[
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Center(child: DocumentGlyph('folder', size: 38)),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${request.broker} asked for your documents',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 25,
            height: 31 / 25,
            color: AppColors.heading,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'For the rent agreement of '),
              TextSpan(
                text: request.address,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            height: 24 / 17,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 20),
        if (request.verified) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: AppColors.success,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'You are logged in',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${request.name} · ${request.phone}',
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
          ),
          const SizedBox(height: 20),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              for (final paper in request.papers)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: paper == request.papers.last
                        ? null
                        : const Border(
                            bottom: BorderSide(color: Color(0xFFEDF1F6)),
                          ),
                  ),
                  child: Row(
                    children: [
                      DocumentGlyph(paper.name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          paper == RequestedPaper.bank
                              ? 'Bank account or cancelled cheque'
                              : paper.label,
                          style: const TextStyle(
                            fontSize: 16.5,
                            color: AppColors.heading,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const DocumentNote(
          'Your documents are safe. They are used only for drafting this agreement.',
        ),
      ] else ...[
        _heading(
          'Verify your phone',
          'Enter the code sent to ${request.phone}',
        ),
        const SizedBox(height: 28),
        TextField(
          controller: widget.code,
          enabled: !widget.busy,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Six-digit OTP'),
          onSubmitted: (_) {
            if (!widget.busy) widget.onVerify();
          },
        ),
        TextButton(
          onPressed: !widget.busy && widget.cooldown == 0
              ? widget.onRequestOtp
              : null,
          child: Text(
            widget.cooldown > 0
                ? 'Resend in ${widget.cooldown} seconds'
                : 'Resend code',
          ),
        ),
        const DocumentNote(
          'Wrong number? Ask your broker to correct it and send a new link.',
        ),
      ],
    ],
  );
  Widget _hub(DocumentRequestInfo request) =>
      request.role == 'tenant' ? _tenantHub(request) : _standardHub(request);

  Future<void> _editLinkedIn() async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x80172231),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: LinkedInProfileFields(
            recipient: true,
            name: widget.info!.name,
            initial: widget.linkedInDetails?['url'] as String? ?? '',
            onSave: (value) async {
              await widget.onLinkedIn!(value);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
          ),
        ),
      ),
    );
  }

  Widget _tenantHub(DocumentRequestInfo request) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        '${request.broker.split(' ').first} needs your ${request.paper == RequestedPaper.linkedin ? 'LinkedIn profile' : 'documents'}',
        'For your rent agreement · ${request.address}',
      ),
      const SizedBox(height: 24),
      for (final paper in request.papers)
        if (paper != RequestedPaper.linkedin)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFEDF1F6))),
            ),
            child: Row(
              children: [
                DocumentGlyph(paper.name, color: AppColors.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        paper.label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: AppColors.heading,
                        ),
                      ),
                      if (_ready(paper))
                        Text(
                          paper == RequestedPaper.aadhaar
                              ? 'Added · front and back'
                              : 'Added · not sent',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.success,
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.busy
                      ? null
                      : () => setState(() => editing = paper),
                  icon: DocumentGlyph(
                    _ready(paper) ? 'sync' : 'upload',
                    size: 18,
                    color: AppColors.primary,
                  ),
                  label: Text(_ready(paper) ? 'Change' : 'Upload'),
                ),
              ],
            ),
          ),
      if ([RequestedPaper.all, RequestedPaper.linkedin].contains(request.paper))
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              const DocumentGlyph('linkedin', color: AppColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LinkedIn profile',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: AppColors.heading,
                      ),
                    ),
                    Text(
                      widget.linkedInDetails == null
                          ? 'Optional · paste your profile link'
                          : widget.linkedInDetails!['skipped'] == true
                          ? 'Skipped · can add later'
                          : 'Added · ${widget.linkedInDetails!['url']}',
                      style: TextStyle(
                        fontSize: 13,
                        color: widget.linkedInDetails == null
                            ? AppColors.muted
                            : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: widget.busy ? null : _editLinkedIn,
                child: Text(widget.linkedInDetails == null ? 'Add' : 'Change'),
              ),
            ],
          ),
        ),
      if (request.paper != RequestedPaper.linkedin)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Photo (JPG, PNG) or PDF · up to 10 MB',
            style: TextStyle(fontSize: 14, color: AppColors.muted),
          ),
        ),
    ],
  );

  Widget _standardHub(DocumentRequestInfo request) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'Upload documents',
        '${request.papers.length} ${request.papers.length == 1 ? 'thing' : 'things'} for ${request.address}',
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          for (final paper in request.papers)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: paper == request.papers.last ? 0 : 4,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _ready(paper) ? 1 : 0,
                    minHeight: 8,
                    backgroundColor: AppColors.primaryBorder,
                    color: const Color(0xFF23AF69),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 20),
      if (request.reason.isNotEmpty)
        Text(
          'Please replace: ${request.reason}',
          style: const TextStyle(color: AppColors.error),
        ),
      for (final paper in request.papers)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
          decoration: BoxDecoration(
            border: paper == request.papers.last
                ? null
                : const Border(bottom: BorderSide(color: Color(0xFFEDF1F6))),
          ),
          child: Row(
            children: [
              DocumentGlyph(paper.name, color: AppColors.muted),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paper.label,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: AppColors.heading,
                      ),
                    ),
                    Text(
                      _ready(paper)
                          ? 'Added · not sent'
                          : paper == RequestedPaper.bank
                          ? 'Cheque photo or type details'
                          : 'Photo or file only',
                      style: TextStyle(
                        fontSize: 13,
                        color: _ready(paper)
                            ? AppColors.success
                            : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              DocumentRoundAction(
                glyph: _ready(paper) ? 'file' : 'camera',
                label: _ready(paper)
                    ? 'See'
                    : paper == RequestedPaper.bank
                    ? 'Cheque'
                    : 'Photo',
                onTap: widget.busy
                    ? null
                    : () => setState(() => editing = paper),
              ),
              const SizedBox(width: 8),
              DocumentRoundAction(
                glyph: paper == RequestedPaper.bank ? 'pencil' : 'file',
                label: _ready(paper)
                    ? 'Change'
                    : paper == RequestedPaper.bank
                    ? 'Type'
                    : 'File',
                onTap: widget.busy
                    ? null
                    : () async {
                        if (paper == RequestedPaper.bank) {
                          setState(() => editing = paper);
                        } else if (paper == RequestedPaper.aadhaar) {
                          setState(() => editing = paper);
                          await widget.onPick(
                            widget.files.containsKey(DocumentKind.aadhaarFront)
                                ? DocumentKind.aadhaarBack
                                : DocumentKind.aadhaarFront,
                            false,
                          );
                        } else {
                          await widget.onPick(DocumentKind.pan, false);
                        }
                      },
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      const Row(
        children: [
          Icon(Icons.image_outlined, size: 16, color: AppColors.muted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Photo (JPG, PNG) or PDF · up to 10 MB',
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ),
        ],
      ),
    ],
  );
  Widget _pageTile(DocumentKind kind, String label) => Expanded(
    child: InkWell(
      onTap: widget.busy
          ? null
          : () => widget.files.containsKey(kind)
                ? widget.onView(kind)
                : widget.onPick(kind, true),
      borderRadius: BorderRadius.circular(20),
      child: DocumentDashedBorder(
        enabled: !widget.files.containsKey(kind),
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: widget.files.containsKey(kind)
                ? AppColors.successSoft
                : AppColors.surfaceMuted,
            border: Border.all(
              color: widget.files.containsKey(kind)
                  ? const Color(0xFF23AF69)
                  : AppColors.primaryBorder,
              width: widget.files.containsKey(kind) ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: widget.files.containsKey(kind)
                      ? const Color(0xFF23AF69)
                      : AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: widget.files.containsKey(kind)
                      ? const Icon(Icons.check, color: Colors.white)
                      : const DocumentGlyph('camera', color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.files.containsKey(kind) ? '$label added' : label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: widget.files.containsKey(kind)
                      ? AppColors.success
                      : AppColors.primaryDark,
                ),
              ),
              if (!widget.files.containsKey(kind))
                const Text(
                  'Tap to take photo',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> _chooseFile() async {
    final kind = editing!.slots.firstWhere(
      (kind) => !widget.files.containsKey(kind),
      orElse: () => editing!.slots.first,
    );
    await widget.onPick(kind, false);
  }

  Widget _details() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        bankMethod == 'upi' ? 'UPI' : editing!.label,
        editing == RequestedPaper.aadhaar
            ? 'Take a photo of both sides'
            : editing == RequestedPaper.bank
            ? widget.info?.role == 'tenant'
                  ? 'For your deposit refund'
                  : 'Where your rent money comes'
            : 'Add a clear photo of your card',
      ),
      const SizedBox(height: 18),
      if (bankMethod != null)
        RecipientBankFields(
          key: ValueKey(bankMethod),
          method: bankMethod!,
          initial: widget.bankDetails,
          onSave: (value) {
            widget.onBank(value);
            setState(() {
              bankMethod = null;
              editing = null;
            });
          },
        )
      else if (editing == RequestedPaper.bank) ...[
        InkWell(
          onTap: widget.busy ? null : _chooseFile,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              border: Border.all(color: AppColors.primary, width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: DocumentGlyph(
                      'camera',
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Upload cancelled cheque',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Photo or PDF · add bank proof',
                  style: TextStyle(fontSize: 15, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 14, color: AppColors.primaryDark),
                      SizedBox(width: 6),
                      Text(
                        'Fastest',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or type details',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final method in ['bank', 'upi'])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: method == 'bank' ? 12 : 0),
                  child: InkWell(
                    onTap: widget.busy
                        ? null
                        : () => setState(() => bankMethod = method),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      height: 142,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: AppColors.surfaceMuted,
                            child: Icon(
                              method == 'bank'
                                  ? Icons.account_balance_outlined
                                  : Icons.qr_code,
                              color: AppColors.primaryDark,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            method == 'bank' ? 'Bank' : 'UPI',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            method == 'bank' ? 'Account no. + IFSC' : 'UPI ID',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (widget.bankDetails != null)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: DocumentNote('Bank details added · not verified'),
          ),
      ] else ...[
        Row(
          children: [
            _pageTile(
              editing!.slots.first,
              editing == RequestedPaper.aadhaar ? 'Front' : 'PAN',
            ),
            if (editing == RequestedPaper.aadhaar) ...[
              const SizedBox(width: 12),
              _pageTile(DocumentKind.aadhaarBack, 'Back'),
            ],
          ],
        ),
        const SizedBox(height: 16),
        const DocumentNote(
          'Keep it flat, in good light. All 4 corners should show.',
          icon: Icons.image_outlined,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: widget.busy ? null : _chooseFile,
            icon: const DocumentGlyph('file', size: 16),
            label: const Text(
              'Have a PDF? Choose a file instead',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
      for (final kind in editing!.slots.where(widget.files.containsKey))
        Row(
          children: [
            Expanded(
              child: Text(
                widget.files[kind]!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ),
            IconButton(
              onPressed: widget.busy ? null : () => widget.onView(kind),
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'View ${kind.label}',
            ),
            IconButton(
              onPressed: widget.busy ? null : () => widget.onPick(kind, false),
              icon: const Icon(Icons.sync),
              tooltip: 'Change ${kind.label}',
            ),
            IconButton(
              onPressed: widget.busy ? null : () => widget.onRemove(kind),
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              tooltip: 'Delete ${kind.label}',
            ),
          ],
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final request = widget.info;
    final ready = request != null && _ready(request.paper);
    final detailsReady = editing != null && _ready(editing!);
    return PopScope(
      canPop: !widget.busy && editing == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  _header(),
                  if (widget.busy)
                    LinearProgressIndicator(value: widget.progress),
                  if (widget.onCancelSelection != null)
                    TextButton(
                      onPressed: widget.onCancelSelection,
                      child: const Text('Cancel selection'),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        entered ? 20 : 36,
                        24,
                        20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.loading)
                            const Center(child: CircularProgressIndicator())
                          else if (request == null) ...[
                            const Icon(
                              Icons.link_off,
                              size: 48,
                              color: AppColors.muted,
                            ),
                            const SizedBox(height: 20),
                            _heading(
                              'Link unavailable',
                              'Ask the broker for a new link.',
                            ),
                          ] else if (received) ...[
                            const Icon(
                              Icons.check_circle,
                              size: 84,
                              color: Color(0xFF23AF69),
                            ),
                            const SizedBox(height: 24),
                            _heading(
                              request.paper == RequestedPaper.all
                                  ? 'Documents sent'
                                  : '${request.paper.label} sent',
                              '${request.broker} has received your documents for ${request.address}.',
                            ),
                            const SizedBox(height: 20),
                            const DocumentNote(
                              'You can close this page. Sending a document does not mean it is identity-verified or bank-verified.',
                            ),
                          ] else if (!entered || !verified)
                            _landing(request)
                          else if (editing != null)
                            _details()
                          else
                            _hub(request),
                          if (widget.error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: Text(
                                widget.error!,
                                style: const TextStyle(color: AppColors.error),
                              ),
                            ),
                          if (widget.error != null &&
                              !widget.busy &&
                              !widget.loading)
                            TextButton(
                              onPressed: widget.onReload,
                              child: const Text('Try again'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!widget.loading &&
                      !(entered &&
                          verified &&
                          !received &&
                          request?.paper == RequestedPaper.linkedin) &&
                      bankMethod == null &&
                      !(editing == RequestedPaper.bank && !detailsReady))
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFEDF1F6)),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (entered &&
                              !received &&
                              !(editing != null ? detailsReady : ready)) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: AppColors.error,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    editing == RequestedPaper.aadhaar
                                        ? widget.files.containsKey(
                                                DocumentKind.aadhaarFront,
                                              )
                                              ? 'Add the back side to save'
                                              : 'Add both sides to save'
                                        : editing != null
                                        ? 'Add ${editing!.label} to save'
                                        : request?.paper == RequestedPaper.all
                                        ? request?.role == 'tenant'
                                              ? 'Add all 3 to submit'
                                              : 'Add all 3 to send'
                                        : 'Add the requested document to send',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.error,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                          SizedBox(
                            height: 56,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                disabledBackgroundColor: const Color(
                                  0xFFE6EBF3,
                                ),
                                disabledForegroundColor: const Color(
                                  0xFF6B7A8F,
                                ),
                              ),
                              onPressed: widget.busy
                                  ? null
                                  : request == null
                                  ? widget.onReload
                                  : received
                                  ? widget.onSignOut
                                  : !entered || !verified
                                  ? widget.otpSent
                                        ? widget.onVerify
                                        : () async {
                                            if (verified) {
                                              setState(() => entered = true);
                                            } else {
                                              await widget.onRequestOtp();
                                              if (mounted && verified) {
                                                setState(() => entered = true);
                                              }
                                            }
                                          }
                                  : editing != null
                                  ? detailsReady
                                        ? () => setState(() => editing = null)
                                        : null
                                  : ready
                                  ? widget.onSubmit
                                  : null,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      request == null
                                          ? 'Try again'
                                          : received
                                          ? 'End verification'
                                          : !entered || !verified
                                          ? widget.otpSent
                                                ? 'Verify code'
                                                : 'Continue with ${request.phone}'
                                          : editing != null
                                          ? 'Save'
                                          : '${request.role == 'tenant' ? 'Submit' : 'Send'} to ${request.broker.split(' ').first}',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  if (entered && editing == null && !received)
                                    DocumentGlyph(
                                      'send',
                                      color: ready && !widget.busy
                                          ? Colors.white
                                          : const Color(0xFF6B7A8F),
                                    )
                                  else
                                    Icon(
                                      editing != null
                                          ? Icons.check
                                          : Icons.chevron_right,
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (!entered &&
                              request != null &&
                              !widget.otpSent &&
                              !received)
                            if (verified)
                              TextButton(
                                onPressed: widget.busy
                                    ? null
                                    : widget.onSignOut,
                                child: const Text('Change phone number'),
                              )
                            else ...[
                              const SizedBox(height: 8),
                              const Text(
                                'We will send an OTP to this number',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
