import 'dart:async';
import 'package:flutter/material.dart';
import '../../participants/data/participant_repository.dart';
import '../data/tenant_setup.dart';
import 'tenant_setup_screen.dart';

class TenantWorkspaceGate extends StatefulWidget {
  const TenantWorkspaceGate({
    required this.repository,
    required this.gateway,
    required this.child,
    super.key,
  });
  final ParticipantRepository repository;
  final TenantSetupGateway gateway;
  final Widget child;
  @override
  State<TenantWorkspaceGate> createState() => _TenantWorkspaceGateState();
}

class _TenantWorkspaceGateState extends State<TenantWorkspaceGate> {
  StreamSubscription<List<ParticipantRecord>>? subscription;
  Timer? initialTimeout;
  ParticipantRecord? agreement;
  bool loaded = false;
  bool completed = false;
  TenantSetupData? setup;
  String? failure;
  String signature = '';
  int generation = 0;
  int readGeneration = 0;
  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(TenantWorkspaceGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.gateway != widget.gateway) {
      _listen();
    }
  }

  void _listen() {
    final active = ++generation;
    subscription?.cancel();
    initialTimeout?.cancel();
    loaded = false;
    failure = null;
    signature = '';
    agreement = null;
    completed = false;
    setup = null;
    initialTimeout = Timer(const Duration(seconds: 45), () {
      if (mounted && generation == active && !loaded) {
        setState(() {
          failure =
              'Your home is taking too long to load. Check your connection and retry.';
        });
      }
    });
    subscription = widget.repository
        .watch('agreements')
        .listen(
          (records) {
            if (!mounted || generation != active) {
              return;
            }
            initialTimeout?.cancel();
            final homes = records
                .where(
                  (record) => [
                    'signed_copy_received',
                    'active',
                  ].contains(record.text('status', '')),
                )
                .toList();
            homes.sort((left, right) => left.id.compareTo(right.id));
            final next = homes.isEmpty ? null : homes.first;
            final nextSignature = next == null
                ? ''
                : '${next.id}:${next.data['revision']}';
            if (loaded && nextSignature == signature && failure == null) {
              return;
            }
            setState(() {
              loaded = true;
              signature = nextSignature;
              agreement = next;
              failure = null;
              completed = false;
              setup = null;
            });
            if (next != null) {
              unawaited(_read(next, active));
            }
          },
          onError: (Object error) {
            if (mounted && generation == active) {
              initialTimeout?.cancel();
              setState(() {
                agreement = null;
                loaded = false;
                failure = 'Your linked home could not be loaded. Please retry.';
              });
            }
          },
        );
  }

  Future<void> _read(ParticipantRecord next, int active) async {
    final read = ++readGeneration;
    final expected = '${next.id}:${next.data['revision']}';
    try {
      final result = await widget.gateway
          .read(next.id)
          .timeout(const Duration(seconds: 45));
      if (mounted &&
          generation == active &&
          signature == expected &&
          read == readGeneration) {
        setState(() {
          completed = result.complete || result.pending;
          setup = result;
        });
      }
    } catch (error) {
      if (mounted &&
          generation == active &&
          signature == expected &&
          read == readGeneration) {
        setState(() {
          failure = 'Your confirmation could not be loaded. Please retry.';
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    initialTimeout?.cancel();
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failure != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(failure!, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => setState(_listen),
                    child: const Text('Retry linked home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (!loaded || agreement != null && setup == null) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }
    if (agreement == null || completed) {
      return widget.child;
    }
    return TenantSetupScreen(
      key: ValueKey(signature),
      agreementId: agreement!.id,
      gateway: widget.gateway,
      initialData: setup,
      onDone: () => setState(() {
        readGeneration++;
        completed = true;
      }),
    );
  }
}
