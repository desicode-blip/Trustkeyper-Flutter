import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../broker/data/agreement_draft.dart';
import '../../broker/data/private_documents.dart';
import '../data/agreement_approvals.dart';

class BrokerApprovalScreen extends StatefulWidget {
  const BrokerApprovalScreen({required this.draft, this.repository, super.key});
  final AgreementDraft draft;
  final AgreementApprovals? repository;
  @override
  State<BrokerApprovalScreen> createState() => _BrokerApprovalScreenState();
}

class _BrokerApprovalScreenState extends State<BrokerApprovalScreen> {
  late final repository = widget.repository ?? FirebaseAgreementApprovals();
  late final stream = repository.watch(widget.draft.id, widget.draft.revision);
  List<ApprovalLink> links = [];
  bool busy = false;
  String? error;
  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : failure is FirebaseFunctionsException
              ? failure.message
              : 'Could not prepare this link. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _prepare({String? refreshPartyId}) async {
    final prepared = await repository.prepare(
      widget.draft.id,
      widget.draft.revision,
      refreshPartyId: refreshPartyId,
    );
    if (mounted) setState(() => links = prepared);
  }

  Future<void> _share(String partyId, String channel) => _run(() async {
    if (links.isEmpty) await _prepare();
    if (!mounted) return;
    var link = links.singleWhere((item) => item.partyId == partyId);
    if (link.expired) {
      await _prepare(refreshPartyId: partyId);
      if (!mounted) return;
      link = links.singleWhere((item) => item.partyId == partyId);
    }
    final message =
        'Hi ${link.name}, please read and reply to your TrustKeyper demo agreement. This is not a legal contract or signature. Link valid for 7 days: ${link.url}';
    if (channel == 'Copy') {
      await Clipboard.setData(ClipboardData(text: message));
    } else {
      final destination = channel == 'WhatsApp'
          ? Uri.https('wa.me', link.phone.replaceAll('+', ''), {
              'text': message,
            })
          : Uri(
              scheme: 'sms',
              path: link.phone,
              queryParameters: {'body': message},
            );
      if (!await launchUrl(destination, mode: LaunchMode.externalApplication)) {
        throw const DocumentFailure(
          'Could not open messaging. Use Copy instead.',
        );
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            channel == 'Copy'
                ? 'Link copied. Send it privately to ${link.name}.'
                : 'Message opened. Delivery is not confirmed by TrustKeyper.',
          ),
        ),
      );
    }
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Send to each person')),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final statuses = {
          for (final record
              in (snapshot.hasError
                  ? <Map<String, dynamic>>[]
                  : snapshot.data ?? <Map<String, dynamic>>[]))
            record['partyId']: record,
        };
        final people = [...widget.draft.owners, ...widget.draft.tenants];
        final agreed = people
            .where((party) => statuses[party.id]?['status'] == 'agreed')
            .length;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Each person gets their own private link.',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Saved version ${widget.draft.revision} · $agreed of ${people.length} said yes',
            ),
            const SizedBox(height: 12),
            const Text(
              'Demo only. Replies do not sign an agreement, collect money or start a tenancy. Email delivery is deferred.',
            ),
            const SizedBox(height: 16),
            if (snapshot.hasError)
              const Text(
                'Replies could not be loaded. Do not assume everyone agreed. Reopen this page.',
              ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            for (final party in people) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.primarySoft,
                            child: Text(
                              party.name
                                  .trim()
                                  .split(RegExp(r'\s+'))
                                  .take(2)
                                  .map((part) => part[0])
                                  .join(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              party.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${widget.draft.owners.any((owner) => owner.id == party.id) ? "Owner" : "Tenant"} · ${party.phone}',
                      ),
                      Text(
                        approvalStatus(
                          statuses[party.id]?['status'] as String? ??
                              'not_opened',
                        ),
                      ),
                      if (statuses[party.id]?['reply'] is Map &&
                          statuses[party.id]?['status'] == 'change_requested')
                        Text(
                          (statuses[party.id]!['reply'] as Map)['note']
                              as String,
                          style: const TextStyle(color: AppColors.primary),
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final channel in ['WhatsApp', 'SMS', 'Copy'])
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => _share(party.id, channel),
                              child: Text(channel),
                            ),
                          if (![
                            'agreed',
                            'change_requested',
                          ].contains(statuses[party.id]?['status']))
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => _share(party.id, 'WhatsApp'),
                              child: const Text('Remind'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (busy) const LinearProgressIndicator(),
            Text(
              agreed == people.length && !snapshot.hasError
                  ? 'Everyone replied yes to this version. Return to the saved draft to request team review.'
                  : 'Everyone must reply yes to the same saved version before team review. Saving changes invalidates every previous reply and link.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : () => _run(() => _prepare()),
              child: const Text('Prepare private links'),
            ),
          ],
        );
      },
    ),
  );
}
