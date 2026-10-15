import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/tenant_setup_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/participants/data/participant_repository.dart';
import 'package:trustkeyper/src/features/tenant/data/tenant_setup.dart';
import 'package:trustkeyper/src/features/tenant/presentation/tenant_workspace_gate.dart';

class GateRepository implements ParticipantRepository {
  final changes = StreamController<List<ParticipantRecord>>.broadcast();
  @override
  Stream<List<ParticipantRecord>> watch(String collection) => changes.stream;
}

class GateGateway extends OfflineTenantSetupGateway {
  int reads = 0;
  Completer<TenantSetupData>? wait;
  @override
  Future<TenantSetupData> read(String agreementId) {
    reads++;
    return wait?.future ?? super.read(agreementId);
  }
}

ParticipantRecord home(String id) =>
    ParticipantRecord(id, {'revision': 1, 'status': 'signed_copy_received'});
Future<void> showGate(
  WidgetTester tester,
  GateRepository repository,
  GateGateway gateway,
) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: TenantWorkspaceGate(
      repository: repository,
      gateway: gateway,
      child: const Scaffold(body: Text('Actual tenant workspace')),
    ),
  ),
);
void main() {
  testWidgets(
    'tenant entry uses one bounded read and seeds confirmation without a second fetch',
    (tester) async {
      final repository = GateRepository();
      final gateway = GateGateway();
      addTearDown(repository.changes.close);
      await showGate(tester, repository, gateway);
      repository.changes.add([home('first')]);
      await tester.pumpAndSettle();
      expect(gateway.reads, 1);
      expect(find.text('Is this your home?'), findsOneWidget);
    },
  );
  testWidgets(
    'membership removal cancels a stale home read and clears private confirmation',
    (tester) async {
      final repository = GateRepository();
      final gateway = GateGateway()..wait = Completer<TenantSetupData>();
      addTearDown(repository.changes.close);
      await showGate(tester, repository, gateway);
      repository.changes.add([home('private')]);
      await tester.pump();
      repository.changes.add([]);
      await tester.pump();
      gateway.wait!.complete(TenantSetupData(gateway.values));
      await tester.pumpAndSettle();
      expect(find.text('Actual tenant workspace'), findsOneWidget);
      expect(find.text('Is this your home?'), findsNothing);
    },
  );
  testWidgets(
    'an unanswered linked-home read offers retry instead of an endless loader',
    (tester) async {
      final repository = GateRepository();
      final gateway = GateGateway()..wait = Completer<TenantSetupData>();
      addTearDown(repository.changes.close);
      await showGate(tester, repository, gateway);
      repository.changes.add([home('timeout')]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 46));
      expect(find.text('Retry linked home'), findsOneWidget);
      gateway.wait!.complete(TenantSetupData(gateway.values));
      await tester.pump();
      expect(find.text('Is this your home?'), findsNothing);
    },
  );
}
