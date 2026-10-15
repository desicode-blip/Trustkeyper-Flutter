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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
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
                        fontWeight: FontWeight.w600,
                        color: AppColors.heading,
                      ),
                    ),
                    Text(
                      'Stopped at ${progressLabel(widget.progress)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3F8),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_outlined, size: 14, color: AppColors.muted),
                SizedBox(width: 4),
                Text(
                  'Draft',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: deleting
                      ? null
                      : widget.onContinue ??
                            () => context.push(
                              '/broker/progress/${Uri.encodeComponent(widget.progress.draft.id)}',
                            ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text('Continue')),
                      SizedBox(width: 8),
                      Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: deleting ? null : _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.delete_outline, size: 17),
                label: Text(deleting ? 'Deleting…' : 'Delete'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var index = 0; index < 5; index++)
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: index == 4 ? 0 : 4),
                    height: 8,
                    decoration: BoxDecoration(
                      color: index < step
                          ? AppColors.success
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
        ],
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
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Continue your agreement',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.heading,
                        ),
                      ),
                      const SizedBox(height: 10),
                      BrokerDraftCard(
                        progress: saved.first,
                        repository: widget.repository,
                      ),
                      TextButton(
                        onPressed: () => context.push('/broker/unfinished'),
                        child: Text('See all ${saved.length} saved drafts'),
                      ),
                    ],
                  ),
                );
              },
            ),
      );
}
