import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'document_request_widgets.dart';

class DocumentLinkDialog extends StatefulWidget {
  const DocumentLinkDialog({
    required this.paper,
    required this.name,
    required this.phone,
    this.email = '',
    this.canEditEmail = false,
    this.remind = false,
    super.key,
  });
  final String paper;
  final String name;
  final String phone;
  final String email;
  final bool canEditEmail;
  final bool remind;
  @override
  State<DocumentLinkDialog> createState() => _DocumentLinkDialogState();
}

class _DocumentLinkDialogState extends State<DocumentLinkDialog> {
  String channel = 'WhatsApp';
  @override
  Widget build(BuildContext context) => Dialog(
    alignment: const Alignment(0, -.26),
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: AppColors.successSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: DocumentGlyph('send', color: Color(0xFF23AF69)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.remind ? 'Remind about' : 'Send'} ${widget.paper.replaceAll(' card', '')} link?',
                        style: const TextStyle(
                          fontSize: 21,
                          height: 26 / 21,
                          fontWeight: FontWeight.w700,
                          color: AppColors.heading,
                        ),
                      ),
                      Text(
                        'To ${widget.name.split(' ').first} · ${channel == 'Email' ? widget.email : widget.phone}',
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final option in ['WhatsApp', 'SMS', 'Email'])
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: option == 'Email' && widget.email.isEmpty
                      ? null
                      : () => setState(() => channel = option),
                  child: Container(
                    height: 66,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: channel == option
                          ? AppColors.primarySoft
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: channel == option
                            ? AppColors.primary
                            : AppColors.border,
                        width: channel == option ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          channel == option
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 26,
                          color: channel == option
                              ? AppColors.primary
                              : const Color(0xFF9AA8BA),
                        ),
                        const SizedBox(width: 12),
                        DocumentGlyph(
                          option.toLowerCase(),
                          color: option == 'WhatsApp'
                              ? const Color(0xFF23AF69)
                              : option == 'Email'
                              ? const Color(0xFF8B5CFF)
                              : AppColors.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.heading,
                                ),
                              ),
                              Text(
                                option == 'WhatsApp'
                                    ? 'Best – most people use it'
                                    : option == 'SMS'
                                    ? 'Normal text message'
                                    : widget.email.isEmpty
                                    ? 'No email added'
                                    : widget.email,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.muted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (option == 'Email' && widget.email.isEmpty)
                          TextButton(
                            onPressed: widget.canEditEmail
                                ? () => Navigator.pop(context, 'Add email')
                                : null,
                            child: const Text('Add email'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, channel),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DocumentGlyph('send', color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      'Send link',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(fontSize: 17)),
            ),
          ],
        ),
      ),
    ),
  );
}
