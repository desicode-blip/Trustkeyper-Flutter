import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    this.onAddBank,
    super.key,
  });
  final AgreementProgressRepository repository;
  final Stream<List<BrokerAgreementSummary>>? agreements;

  /// When set, an "Add your bank" row is shown inside the same panel.
  final VoidCallback? onAddBank;
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
                final hasBank = widget.onAddBank != null;
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return hasBank
                      ? _panel(context, const [], widget.onAddBank)
                      : const SizedBox.shrink();
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
                  return hasBank
                      ? _panel(context, const [], widget.onAddBank)
                      : const SizedBox.shrink();
                }
                return _panel(context, saved, widget.onAddBank);
              },
            ),
      );

  static const _maxDraftRows = 2;

  Widget _panel(
    BuildContext context,
    List<AgreementProgress> saved,
    VoidCallback? onAddBank,
  ) => Container(
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
            'Continue',
            style: TextStyle(
              fontSize: 18,
              height: 24 / 18,
              fontWeight: FontWeight.w500,
              color: AppColors.heading,
            ),
          ),
        ),
        for (final progress in saved.take(_maxDraftRows))
          _ContinueRow(
            title: 'Complete rent agreement',
            subtitle: progress.draft.propertyAddress.trim().isEmpty
                ? 'Unnamed property'
                : progress.draft.propertyAddress,
            icon: 'agreement',
            onTap: () => context.push(
              '/broker/progress/${Uri.encodeComponent(progress.draft.id)}',
            ),
          ),
        if (onAddBank != null)
          _ContinueRow(
            title: 'Add your bank',
            subtitle: 'So we can send your fees',
            icon: 'bank',
            warm: true,
            trailingPlus: true,
            onTap: onAddBank,
          ),
        if (saved.length > _maxDraftRows)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push('/broker/unfinished'),
              child: Text('See all ${saved.length} saved drafts'),
            ),
          )
        else
          const SizedBox(height: 8),
      ],
    ),
  );
}

class _ContinueRow extends StatelessWidget {
  const _ContinueRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.warm = false,
    this.trailingPlus = false,
  });
  final String title;
  final String subtitle;
  final String icon;
  final VoidCallback onTap;
  final bool warm;
  final bool trailingPlus;

  @override
  Widget build(BuildContext context) {
    final accent = warm ? const Color(0xFF8A4500) : AppColors.primaryDark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: warm ? const Color(0xFFFFF3E0) : Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: warm ? const Color(0xFFF3C98B) : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: warm ? Colors.white : AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/design/home-$icon.svg',
                      width: 22,
                      height: 22,
                      colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 22 / 17,
                          fontWeight: FontWeight.w500,
                          color: AppColors.heading,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 19 / 14,
                          color: warm ? accent : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (trailingPlus)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: accent),
                    ),
                    child: Icon(Icons.add, size: 20, color: accent),
                  )
                else
                  const Icon(
                    Icons.chevron_right,
                    size: 22,
                    color: AppColors.muted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
