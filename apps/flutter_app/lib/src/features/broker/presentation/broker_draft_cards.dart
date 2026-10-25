import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../data/agreement_progress_repository.dart';
import '../data/broker_repository.dart';

String progressLabel(AgreementProgress progress) => switch (progress.stage) {
  'ownerCount' || 'owner' => 'Owner details',
  'ownerPapers' => 'Owner documents',
  'tenantCount' || 'tenant' => 'Tenant details',
  'tenantPapers' => 'Tenant documents',
  'money' || 'dates' || 'periods' => 'Rent and dates',
  'brokerage' => 'Brokerage',
  _ => 'Review',
};

class BrokerDraftCard extends StatefulWidget {
  const BrokerDraftCard({
    required this.progress,
    required this.repository,
    this.onContinue,
    super.key,
  });
  final AgreementProgress progress;
  final AgreementProgressRepository repository;
  final VoidCallback? onContinue;
  @override
  State<BrokerDraftCard> createState() => _BrokerDraftCardState();
}

class _BrokerDraftCardState extends State<BrokerDraftCard> {
  bool deleting = false;
  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this draft progress?'),
        content: const Text(
          'An unfinished agreement’s document links will stop working. This does not delete a signed agreement or its legal copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => deleting = true);
    try {
      await widget.repository.remove(
        widget.progress.draft.id,
        widget.progress.version,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Draft changed or could not be deleted. Reopen and retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.progress.stage.startsWith('owner')
        ? 2
        : widget.progress.stage.startsWith('tenant')
        ? 3
        : widget.progress.stage == 'review' ||
              widget.progress.stage == 'brokerage'
        ? 5
        : 4;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.heading.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: deleting
            ? null
            : widget.onContinue ??
                  () => context.push(
                    '/broker/progress/${Uri.encodeComponent(widget.progress.draft.id)}',
                  ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 8, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.progress.draft.propertyAddress.trim().isEmpty
                              ? 'Unnamed property'
                              : widget.progress.draft.propertyAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            height: 24 / 17,
                            fontWeight: FontWeight.w500,
                            color: AppColors.heading,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Stopped at ${progressLabel(widget.progress)}',
                          style: const TextStyle(
                            fontSize: 14,
                            height: 20 / 14,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete draft',
                    onPressed: deleting ? null : _delete,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 22,
                      color: deleting ? AppColors.muted : AppColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    for (var index = 0; index < 5; index++)
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: index == 4 ? 0 : 4),
                          height: 6,
                          decoration: BoxDecoration(
                            color: index < step
                                ? AppColors.success
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BrokerDraftSection extends StatefulWidget {
  const BrokerDraftSection({
    required this.repository,
    this.agreements,
    super.key,
  });
  final AgreementProgressRepository repository;
  final Stream<List<BrokerAgreementSummary>>? agreements;
  @override
  State<BrokerDraftSection> createState() => _BrokerDraftSectionState();
}

class _BrokerDraftSectionState extends State<BrokerDraftSection> {
  late var stream = widget.repository.watch();
  @override
  void didUpdateWidget(covariant BrokerDraftSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      stream = widget.repository.watch();
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<BrokerAgreementSummary>>(
        stream: widget.agreements,
        builder: (context, agreements) =>
            StreamBuilder<List<AgreementProgress>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return TextButton(
                    onPressed: () =>
                        setState(() => stream = widget.repository.watch()),
                    child: const Text('Retry saved agreements'),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox.shrink();
                }
                final saved = snapshot.data!
                    .where(
                      (draft) => !(agreements.data ?? []).any(
                        (agreement) =>
                            agreement.id == draft.draft.id &&
                            (agreement.status != 'draft' ||
                                agreement.revision > draft.draft.revision),
                      ),
                    )
                    .toList();
                if (agreements.hasError || saved.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Container(
                  margin: const EdgeInsets.only(top: 28),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
                        child: Text(
                          'Continue your agreement',
                          style: TextStyle(
                            fontSize: 18,
                            height: 24 / 18,
                            fontWeight: FontWeight.w500,
                            color: AppColors.heading,
                          ),
                        ),
                      ),
                      BrokerDraftCard(
                        progress: saved.first,
                        repository: widget.repository,
                      ),
                      if (saved.length > 1)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => context.push('/broker/unfinished'),
                            child: Text('See all ${saved.length} saved drafts'),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
      );
}
