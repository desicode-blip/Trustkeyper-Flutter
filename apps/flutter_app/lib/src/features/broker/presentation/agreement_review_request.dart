import 'package:flutter/material.dart';

import '../data/agreement_review_repository.dart';

class AgreementReviewRequest extends StatefulWidget {
  const AgreementReviewRequest({
    required this.agreementId,
    required this.revision,
    required this.onSubmitted,
    this.repository,
    super.key,
  });
  final String agreementId;
  final int revision;
  final VoidCallback onSubmitted;
  final AgreementReviewRepository? repository;
  @override
  State<AgreementReviewRequest> createState() => _AgreementReviewRequestState();
}

class _AgreementReviewRequestState extends State<AgreementReviewRequest> {
  bool busy = false;
  bool submitted = false;
  String? message;

  Future<void> _submit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request team review?'),
        content: const Text(
          'Every owner and tenant must have replied yes to this saved version first. This freezes the demo for administrator review. It does not send participant links, sign a contract or collect money.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Request review'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await (widget.repository ?? FirebaseAgreementReviewRepository()).request(
        widget.agreementId,
        widget.revision,
      );
      if (!mounted) return;
      setState(() {
        submitted = true;
        message = 'Team review requested. This demo is not signed.';
      });
      widget.onSubmitted();
    } catch (error) {
      if (mounted) {
        setState(
          () => message = error is ReviewFailure
              ? error.message
              : 'Could not confirm review. Reopen the draft before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: busy || submitted ? null : _submit,
        icon: const Icon(Icons.fact_check_outlined),
        label: Text(
          busy ? 'Requesting review…' : 'Request team review · Demo only',
        ),
      ),
      if (message != null) Text(message!, style: const TextStyle(height: 1.5)),
    ],
  );
}
