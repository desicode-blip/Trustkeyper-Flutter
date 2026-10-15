import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/participant_repository.dart';
import '../../broker/data/agreement_draft.dart';
import '../../broker/data/demo_agreement.dart';
import '../../broker/presentation/demo_agreement_screen.dart';

class ParticipantRecordsScreen extends StatefulWidget {
  const ParticipantRecordsScreen({
    required this.repository,
    required this.role,
    required this.collection,
    required this.title,
    super.key,
  });
  final ParticipantRepository repository;
  final String role;
  final String collection;
  final String title;
  @override
  State<ParticipantRecordsScreen> createState() =>
      _ParticipantRecordsScreenState();
}

class _ParticipantRecordsScreenState extends State<ParticipantRecordsScreen> {
  late Stream<List<ParticipantRecord>> records;
  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    records = widget.repository.watch(widget.collection);
  }

  @override
  void didUpdateWidget(ParticipantRecordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.collection != widget.collection) {
      _subscribe();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ParticipantRecord>>(
    stream: records,
    builder: (context, snapshot) => ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(widget.role, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 12),
        Text(widget.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        const Text(
          'Only records linked to your signed-in account appear here. No sample balance or property is assigned to you.',
        ),
        const SizedBox(height: 20),
        if (snapshot.hasError) ...[
          const Text(
            'Could not load your records. Check your connection and account access.',
          ),
          OutlinedButton(
            onPressed: () => setState(_subscribe),
            child: const Text('Retry'),
          ),
        ] else if (!snapshot.hasData)
          const Center(child: CircularProgressIndicator())
        else if (snapshot.data!.isEmpty)
          const Text(
            'No linked records yet. Ask your broker or team to check your verified account and agreement access.',
          )
        else
          for (final record in snapshot.data!)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.text(
                        'propertyAddress',
                        record.text('title', 'Record ${record.id}'),
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Status: ${record.text('status', 'Not recorded')}'),
                    for (final field in _amountFields.entries)
                      if (record.amount(field.key) != null)
                        Text(
                          '${field.value}: ${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2).format(record.amount(field.key)! / 100)}',
                        ),
                    if (record.data['description'] is String)
                      Text(record.text('description')),
                    if (widget.collection == 'agreements')
                      const Text(
                        'Agreement totals above are not your personal share or proof of payment. Participant review and signing remain separate steps.',
                      ),
                    if (widget.collection == 'agreements' &&
                        _demo(record) != null)
                      OutlinedButton(
                        onPressed: () {
                          final demo = _demo(record);
                          if (demo != null) {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    DemoAgreementScreen(agreement: demo),
                              ),
                            );
                          }
                        },
                        child: const Text('Read demo terms · Not for signing'),
                      ),
                  ],
                ),
              ),
            ),
      ],
    ),
  );
  static const _amountFields = {
    'monthlyRentPaise': 'Agreement monthly rent',
    'securityDepositPaise': 'Agreement deposit',
    'amountPaise': 'Recorded amount',
  };
  static DemoAgreement? _demo(ParticipantRecord record) {
    try {
      final draft = AgreementDraft.fromMap(record.id, record.data);
      return draft.validationError == null ? DemoAgreement(draft) : null;
    } catch (_) {
      return null;
    }
  }
}
