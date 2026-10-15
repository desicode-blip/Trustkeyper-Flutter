import 'package:flutter/material.dart';
import '../data/account_gateway.dart';
import 'account_screens.dart';

class AccountRestorationQueue extends StatefulWidget {
  const AccountRestorationQueue({required this.gateway, super.key});
  final AccountRestorationGateway gateway;
  @override
  State<AccountRestorationQueue> createState() =>
      _AccountRestorationQueueState();
}

class _AccountRestorationQueueState extends State<AccountRestorationQueue> {
  List<Map<String, dynamic>> requests = [];
  bool busy = true;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AccountRestorationQueue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway) {
      _load();
    }
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
      error = null;
      requests = [];
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
    } catch (failure) {
      if (mounted && generation == active) {
        setState(() {
          error = accountError(failure);
          busy = false;
        });
      }
    }
  }

  Future<void> _restore(Map<String, dynamic> request) async {
    if (busy) return;
    final finishing = request['status'] == 'closing';
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          finishing ? 'Confirm pending closure?' : 'Restore this account?',
        ),
        content: Text(
          finishing
              ? 'This customer has already confirmed closure. Retry disabling their login and revoking sessions. This does not erase shared legal records.'
              : 'Confirm the customer has requested restoration. The server checks admin access and the seven-day window. Required legal records are preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(finishing ? 'Complete closure' : 'Restore'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final active = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await (finishing
              ? widget.gateway.finishClosure(request['uid'] as String)
              : widget.gateway.restore(request['uid'] as String))
          .timeout(const Duration(seconds: 45));
      if (mounted && generation == active) {
        await _load();
      }
    } catch (failure) {
      if (mounted && generation == active) {
        setState(() {
          error = accountError(failure);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account closures')),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
              TextButton(onPressed: _load, child: const Text('Refresh')),
              if (requests.isEmpty && error == null)
                const Text('No account closures need attention.'),
              for (final request in requests)
                Card(
                  child: ListTile(
                    title: Text(
                      request['displayName'] as String? ??
                          request['uid'] as String,
                    ),
                    subtitle: Text('${request['status']} · ${request['uid']}'),
                    trailing:
                        request['status'] == 'closing' ||
                            request['status'] == 'restoring' ||
                            request['status'] == 'closed' &&
                                (request['restoreUntilMs'] as num? ?? 0) >
                                    DateTime.now().millisecondsSinceEpoch
                        ? FilledButton(
                            onPressed: () => _restore(request),
                            child: Text(
                              request['status'] == 'closing'
                                  ? 'Complete closure'
                                  : 'Restore',
                            ),
                          )
                        : const Text('Review'),
                  ),
                ),
            ],
          ),
  );
}
