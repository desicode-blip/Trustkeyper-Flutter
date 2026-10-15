import 'package:flutter/material.dart';

import '../../participants/data/participant_repository.dart';
import 'rent_payment_screen.dart';

class PaymentAgreementPicker extends StatefulWidget {
  const PaymentAgreementPicker({this.repository, super.key});
  final ParticipantRepository? repository;
  @override
  State<PaymentAgreementPicker> createState() => _PaymentAgreementPickerState();
}

class _PaymentAgreementPickerState extends State<PaymentAgreementPicker> {
  late final agreements =
      (widget.repository ?? SessionParticipantRepository.firebase()).watch(
        'agreements',
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your payments')),
    body: StreamBuilder<List<ParticipantRecord>>(
      stream: agreements,
      builder: (context, snapshot) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Choose your agreement. Razorpay is in test mode; no real money will move.',
          ),
          const SizedBox(height: 20),
          if (snapshot.hasError)
            const Text(
              'Your agreements could not load. Check your login and connection.',
            ),
          if (!snapshot.hasData && !snapshot.hasError)
            const Center(child: CircularProgressIndicator()),
          for (final record in snapshot.data ?? <ParticipantRecord>[])
            if (record.data['agreementCopy'] is Map &&
                record.data['revision'] is int)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(record.text('propertyAddress')),
                subtitle: const Text(
                  'Rent and deposit · verified personal share · test',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => RentPaymentScreen(
                      agreementId: record.id,
                      revision: record.data['revision'] as int,
                    ),
                  ),
                ),
              ),
          if (snapshot.hasData &&
              !snapshot.data!.any(
                (record) => record.data['agreementCopy'] is Map,
              ))
            const Text(
              'Your broker must finish the reviewed agreement copy first. If you received a private agreement link, reopen it and verify your tenant phone.',
            ),
        ],
      ),
    ),
  );
}
