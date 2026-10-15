import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../data/broker_updates_repository.dart';

class BrokerUpdatesBell extends StatefulWidget {
  const BrokerUpdatesBell({this.repository, super.key});
  final BrokerUpdatesRepository? repository;
  @override
  State<BrokerUpdatesBell> createState() => _BrokerUpdatesBellState();
}

class _BrokerUpdatesBellState extends State<BrokerUpdatesBell> {
  late var stream = widget.repository?.watch();
  @override
  void didUpdateWidget(BrokerUpdatesBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      stream = widget.repository?.watch();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<BrokerUpdate>>(
    stream: stream,
    builder: (context, snapshot) {
      final unread = snapshot.hasError
          ? 0
          : (snapshot.data ?? []).where((update) => update.unread).length;
      return Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: IconButton(
          tooltip: unread == 0 ? 'Updates' : 'Updates · $unread unread',
          onPressed: () => context.push('/broker/updates'),
          icon: const Icon(Icons.notifications_none, color: AppColors.heading),
        ),
      );
    },
  );
}

class BrokerUpdatesScreen extends StatefulWidget {
  const BrokerUpdatesScreen({
    this.repository,
    this.onOpen,
    this.now,
    super.key,
  });
  final BrokerUpdatesRepository? repository;
  final ValueChanged<BrokerUpdate>? onOpen;
  final DateTime Function()? now;
  @override
  State<BrokerUpdatesScreen> createState() => _BrokerUpdatesScreenState();
}

class _BrokerUpdatesScreenState extends State<BrokerUpdatesScreen> {
  late final repository =
      widget.repository ?? FirebaseBrokerUpdatesRepository();
  late var stream = repository.watch();
  String? opening;
  String _day(DateTime at) {
    final today = DateUtils.dateOnly(widget.now?.call() ?? DateTime.now());
    final day = DateUtils.dateOnly(at);
    return day == today
        ? 'Today'
        : day == today.subtract(const Duration(days: 1))
        ? 'Yesterday'
        : DateFormat('d MMM yyyy').format(day);
  }

  Future<void> _open(BrokerUpdate update) async {
    setState(() => opening = update.id);
    try {
      if (update.unread) await repository.markRead(update);
      if (!mounted) return;
      if (widget.onOpen != null) {
        widget.onOpen!(update);
      } else {
        await context.push(
          '/broker/documents/${Uri.encodeComponent(update.requestId)}',
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open this update. Check your connection and retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => opening = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      toolbarHeight: 80,
      title: const Text(
        'Updates',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
      ),
      backgroundColor: Colors.white,
      leadingWidth: 72,
      leading: Padding(
        padding: const EdgeInsets.only(left: 24, top: 16, bottom: 16),
        child: IconButton(
          tooltip: 'Back',
          style: IconButton.styleFrom(
            shape: const CircleBorder(
              side: BorderSide(color: AppColors.border),
            ),
            backgroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.chevron_left, size: 24),
        ),
      ),
    ),
    body: StreamBuilder<List<BrokerUpdate>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load your updates.'),
                TextButton(
                  onPressed: () => setState(() => stream = repository.watch()),
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
            child: Text('No updates yet. Document uploads will appear here.'),
          );
        }
        String? previousDay;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            for (final update in snapshot.data!) ...[
              if (_day(update.at) != previousDay)
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Text(
                    previousDay = _day(update.at),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              Material(
                color: update.unread ? const Color(0xFFF7F9FF) : Colors.white,
                child: InkWell(
                  onTap: opening == null ? () => _open(update) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFEDF1F7)),
                      ),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primarySoft,
                          child: Icon(
                            Icons.folder_outlined,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                update.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.heading,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${update.address} · ${DateFormat('h:mm a').format(update.at)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (opening == update.id)
                          const SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (update.unread)
                          const Icon(
                            Icons.circle,
                            size: 10,
                            color: AppColors.primary,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}
