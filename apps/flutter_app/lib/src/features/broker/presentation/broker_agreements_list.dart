import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/agreement_progress_repository.dart';
import '../data/broker_repository.dart';
import '../data/broker_updates_repository.dart';
import 'broker_draft_cards.dart';
import 'broker_updates_screen.dart';

class BrokerAgreementsList extends StatefulWidget {
  const BrokerAgreementsList({
    required this.agreements,
    required this.approvalPending,
    required this.itemBuilder,
    this.progressRepository,
    this.updates,
    super.key,
  });
  final Stream<List<BrokerAgreementSummary>> agreements;
  final bool approvalPending;
  final AgreementProgressRepository? progressRepository;
  final BrokerUpdatesRepository? updates;
  final Widget Function(BuildContext, BrokerAgreementSummary) itemBuilder;
  @override
  State<BrokerAgreementsList> createState() => _BrokerAgreementsListState();
}

class _BrokerAgreementsListState extends State<BrokerAgreementsList> {
  late var progress = widget.progressRepository?.watch();
  String filter = 'All';
  @override
  void didUpdateWidget(BrokerAgreementsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progressRepository != widget.progressRepository) {
      progress = widget.progressRepository?.watch();
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<BrokerAgreementSummary>>(
    stream: widget.agreements,
    builder: (context, agreements) => StreamBuilder<List<AgreementProgress>>(
      stream: progress,
      builder: (context, drafts) {
        final saved = agreements.hasError
            ? <AgreementProgress>[]
            : (drafts.data ?? <AgreementProgress>[])
                  .where(
                    (draft) => !(agreements.data ?? []).any(
                      (agreement) =>
                          agreement.id == draft.draft.id &&
                          (agreement.status != 'draft' ||
                              agreement.revision > draft.draft.revision),
                    ),
                  )
                  .toList();
        final summaries = (agreements.data ?? [])
            .where(
              (agreement) =>
                  !saved.any((draft) => draft.draft.id == agreement.id) &&
                  (filter == 'All' ||
                      filter == 'Drafts' && agreement.status == 'draft' ||
                      filter == 'Signed' &&
                          agreement.copyMode == 'externally_signed' ||
                      filter == 'In progress' &&
                          agreement.status != 'draft' &&
                          agreement.copyMode != 'externally_signed'),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Agreements',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                ),
                BrokerUpdatesBell(repository: widget.updates),
              ],
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Make new agreement',
              icon: Icons.add,
              iconBeforeLabel: true,
              onPressed: widget.approvalPending
                  ? null
                  : () => context.push('/broker/start'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F9FD),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                children: [
                  for (final label in [
                    'All',
                    'In progress',
                    'Signed',
                    'Drafts',
                  ])
                    Expanded(
                      flex: label == 'In progress' ? 16 : 10,
                      child: ChoiceChip(
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label),
                        ),
                        selected: filter == label,
                        showCheckmark: false,
                        shape: const StadiumBorder(),
                        side: BorderSide.none,
                        selectedColor: Colors.white,
                        backgroundColor: const Color(0xFFF6F9FD),
                        labelStyle: TextStyle(
                          color: filter == label
                              ? AppColors.primary
                              : AppColors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                        onSelected: (_) => setState(() => filter = label),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (agreements.hasError)
              const Text(
                'Could not load agreements. Check your connection and login.',
              )
            else if (!agreements.hasData)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (widget.progressRepository != null &&
                  !drafts.hasData &&
                  !drafts.hasError)
                const Center(child: CircularProgressIndicator()),
              if (drafts.hasError)
                TextButton(
                  onPressed: () => setState(
                    () => progress = widget.progressRepository?.watch(),
                  ),
                  child: const Text('Could not load saved drafts · Retry'),
                ),
              if (filter == 'All' || filter == 'Drafts')
                for (final draft in saved)
                  BrokerDraftCard(
                    progress: draft,
                    repository: widget.progressRepository!,
                  ),
              for (final agreement in summaries)
                widget.itemBuilder(context, agreement),
              if (summaries.isEmpty &&
                  (!(filter == 'All' || filter == 'Drafts') || saved.isEmpty))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    filter == 'All'
                        ? 'No agreements yet'
                        : filter == 'Drafts'
                        ? 'No saved drafts'
                        : 'No ${filter.toLowerCase()} agreements',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
            if (widget.progressRepository != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => context.push('/broker/signing-requests'),
                icon: const Icon(Icons.draw_outlined),
                label: const Text('Signing-only progress'),
              ),
            ],
          ],
        );
      },
    ),
  );
}
