import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../data/tenant_setup.dart';

class AdminTenantSetupQueue extends StatefulWidget {
  const AdminTenantSetupQueue({required this.gateway, super.key});
  final TenantSetupGateway gateway;
  @override
  State<AdminTenantSetupQueue> createState() => _AdminTenantSetupQueueState();
}

class _AdminTenantSetupQueueState extends State<AdminTenantSetupQueue> {
  List<Map<String, dynamic>> requests = const [];
  bool busy = true;
  String? failure;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final active = ++generation;
    setState(() {
      busy = true;
      requests = const [];
      failure = null;
    });
    try {
      final result = await widget.gateway.pending().timeout(
        const Duration(seconds: 45),
      );
      if (mounted && generation == active) {
        setState(() {
          requests = result;
          busy = false;
        });
      }
    } catch (error) {
      if (mounted && generation == active) {
        setState(() {
          busy = false;
          failure = error is FirebaseFunctionsException
              ? error.message
              : 'The queue could not be loaded. Try again.';
        });
      }
    }
  }

  Future<void> _resolve(Map<String, dynamic> request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve this correction?'),
        content: const Text(
          'First correct the agreement with the broker and participants, then publish its externally signed new revision. The server will check it. This button does not change rent or home membership.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Check signed revision'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) {
      return;
    }
    final active = ++generation;
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      await widget.gateway
          .resolve(request)
          .timeout(const Duration(seconds: 45));
      if (mounted && generation == active) {
        await _load();
      }
    } catch (error) {
      if (mounted && generation == active) {
        setState(() {
          busy = false;
          failure = error is FirebaseFunctionsException
              ? error.message
              : 'This request could not be resolved. Retry after checking the signed revision.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tenant corrections'),
      actions: [
        IconButton(
          onPressed: busy ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Reload queue',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Home, flatmate and rent-share requests',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          'Correct and re-sign the actual agreement before resolving. Existing legal terms and money remain unchanged.',
          style: TextStyle(color: AppColors.muted),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: LinearProgressIndicator(),
          ),
        if (failure != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              failure!,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        if (!busy && failure == null && requests.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Text('No pending tenant corrections.'),
          ),
        for (final request in requests)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['property'] as String? ?? 'Linked home',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${request['tenantName']} · revision ${request['revision']}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 12),
                    Text('Correction: ${request['request']['kind']}'),
                    if (request['request']['rentSharePaise'] is int)
                      Text(
                        'Requested share: ₹${(request['request']['rentSharePaise'] as int) / 100}',
                      ),
                    if ((request['request']['note'] as String? ?? '')
                        .isNotEmpty)
                      Text(request['request']['note'] as String),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: busy ? null : () => _resolve(request),
                      child: const Text('Check corrected signed revision'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
