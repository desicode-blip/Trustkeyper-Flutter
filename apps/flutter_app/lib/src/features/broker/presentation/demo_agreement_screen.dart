import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/demo_agreement.dart';

class DemoAgreementScreen extends StatelessWidget {
  const DemoAgreementScreen({
    required this.agreement,
    this.previous,
    this.changedFields = const {},
    super.key,
  });
  final DemoAgreement agreement;
  final DemoAgreement? previous;
  final Set<String> changedFields;
  @override
  Widget build(BuildContext context) {
    final changed = {...agreement.changedFrom(previous), ...changedFields};
    return Scaffold(
      appBar: AppBar(title: const Text('Demo agreement · Not for signing')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            DemoAgreement.warning,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            'Template ${DemoAgreement.templateVersion} · source revision ${agreement.revision} · preview only',
          ),
          const Text(
            'Yellow: captured draft fields. Green: changed since the opened draft. Changes still require saving; this preview never records consent.',
          ),
          const SizedBox(height: 16),
          for (final field in agreement.fields)
            Card(
              color: changed.contains(field.id)
                  ? const Color(0xFFE5F8F0)
                  : const Color(0xFFFFF4CE),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${field.label}${changed.contains(field.id) ? " · Changed" : ""}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(field.value),
                  ],
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Additional legal clauses and execution requirements are not approved. Signatures, consent, stamp duty and payment: not requested or recorded.',
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Copy demo text?'),
                  content: const Text(
                    'This includes the entered names and contact details. It is not a signed agreement. Only copy it to a trusted destination.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Copy demo'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              await Clipboard.setData(ClipboardData(text: agreement.text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Demo text copied. No agreement sent or signed.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy demo text'),
          ),
        ],
      ),
    );
  }
}
