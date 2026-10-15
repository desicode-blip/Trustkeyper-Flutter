import 'package:flutter/material.dart';

import '../data/agreement_draft_repository.dart';
import '../data/agreement_progress_repository.dart';
import 'broker_agreement_wizard.dart';
import 'broker_draft_cards.dart';

class UnfinishedDraftsScreen extends StatefulWidget {
  const UnfinishedDraftsScreen({this.repository, super.key});
  final AgreementProgressRepository? repository;

  @override
  State<UnfinishedDraftsScreen> createState() => _UnfinishedDraftsScreenState();
}

class _UnfinishedDraftsScreenState extends State<UnfinishedDraftsScreen> {
  late final repository =
      widget.repository ?? FirebaseAgreementProgressRepository();
  late Stream<List<AgreementProgress>> progress = repository.watch();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Unfinished drafts')),
    body: StreamBuilder<List<AgreementProgress>>(
      stream: progress,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Could not load your draft progress. Check your login and connection.',
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => progress = repository.watch()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(
            child: Text('No unfinished drafts. Start a new agreement.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Progress is private to your broker account. A complete agreement is saved only after reviewing every required term.',
            ),
            const SizedBox(height: 16),
            for (final entry in snapshot.data!)
              BrokerDraftCard(progress: entry, repository: repository),
          ],
        );
      },
    ),
  );
}

class ResumeDraftProgressScreen extends StatefulWidget {
  const ResumeDraftProgressScreen({
    required this.id,
    this.progressRepository,
    this.draftRepository,
    this.role,
    this.partyId,
    super.key,
  });
  final String id;
  final AgreementProgressRepository? progressRepository;
  final AgreementDraftRepository? draftRepository;
  final String? role;
  final String? partyId;

  @override
  State<ResumeDraftProgressScreen> createState() =>
      _ResumeDraftProgressScreenState();
}

class _ResumeDraftProgressScreenState extends State<ResumeDraftProgressScreen> {
  late final progressRepository =
      widget.progressRepository ?? FirebaseAgreementProgressRepository();
  late final draftRepository =
      widget.draftRepository ?? FirebaseAgreementDraftRepository();
  late Future<AgreementProgress> progress;

  Future<AgreementProgress> _load() async {
    final value = await progressRepository.load(widget.id);
    if (widget.partyId != null) {
      final parties = widget.role == 'owner'
          ? value.draft.owners
          : widget.role == 'tenant'
          ? value.draft.tenants
          : [];
      if (!parties.any((party) => party.id == widget.partyId)) {
        throw const DraftFailure(
          'This person is no longer on the draft. Open the current saved agreement.',
        );
      }
    }
    try {
      final completed = await draftRepository.load(widget.id);
      if (completed.revision > value.draft.revision) {
        throw const DraftFailure(
          'A newer complete draft already exists. Open it from Agreements instead.',
        );
      }
    } on DraftMissing {
      return value;
    }
    return value;
  }

  @override
  void initState() {
    super.initState();
    progress = _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AgreementProgress>(
    future: progress,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return BrokerAgreementWizard(
          initialProgress: snapshot.data,
          initialPartyId: widget.partyId,
          initialPartyRole: widget.role,
          progressRepository: progressRepository,
          repository: draftRepository,
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Resume draft')),
        body: Center(
          child: snapshot.hasError
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.error is DraftFailure
                            ? (snapshot.error as DraftFailure).message
                            : 'Could not reopen this progress. Check your login and connection.',
                      ),
                      TextButton(
                        onPressed: () => setState(() => progress = _load()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
