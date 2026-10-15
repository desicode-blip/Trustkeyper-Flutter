import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../features/broker/data/private_documents.dart';
import '../../features/participants/data/participant_workspace.dart';
import '../../features/repairs/data/repair_gateway.dart';
import 'document_fixture.dart';

class OfflineRepairFixture implements RepairGateway, IssuePhotoReader {
  OfflineRepairFixture({this.role = 'owner', bool completed = false}) {
    data = {
      'actorRole': role,
      'actorUid': 'offline-$role',
      'title': completed ? 'Geyser fixed' : 'Geyser not heating',
      'propertyAddress': 'Phoenix Towers 402',
      'description': 'The geyser is not heating water.',
      'status': completed ? 'resolved' : 'waiting_owner',
      'workflowVersion': 1,
      'createdAtMs': DateTime(2026, 9, 25, 9, 10).millisecondsSinceEpoch,
      'canApprove': role == 'owner' && !completed,
      'canConfirm': role == 'tenant' && completed,
      'photos': [
        {'path': 'offline/before/0'},
        {'path': 'offline/before/1'},
      ],
      'quote': {
        'version': 1,
        'amountPaise': 280000,
        'needsApproval': true,
        'vendorName': 'Sri Sai Plumbing',
        'vendorPhone': '+919000090000',
        'description': 'Replace the geyser heating element.',
      },
      if (completed)
        'completion': {
          'amountPaise': 280000,
          'invoiceNumber': 'INV-2091',
          'vendorName': 'Sri Sai Plumbing',
          'payoutDateISO': '2026-10-07',
          'completedAtMs': DateTime(2026, 9, 26, 12, 40).millisecondsSinceEpoch,
          'evidence': {'bill': {}, 'after': {}},
        },
    };
  }
  final String role;
  late Map<String, dynamic> data;
  final changes = StreamController<void>.broadcast();
  @override
  Stream<RepairRecord> watch(String issueId) => Stream.multi((controller) {
    controller.add(RepairRecord(issueId, data));
    final subscription = changes.stream.listen(
      (_) => controller.add(RepairRecord(issueId, data)),
    );
    controller.onCancel = subscription.cancel;
  });
  @override
  Future<void> command(String action, Map<String, dynamic> input) async {
    if (action == 'approve') {
      data = {
        ...data,
        'status': 'approved',
        'canApprove': false,
        'ownerApprovals': {
          'offline-owner': {
            'approvedAtMs': DateTime(2026, 9, 25, 10, 5).millisecondsSinceEpoch,
          },
        },
      };
    } else if (action == 'confirm') {
      data = {
        ...data,
        'status': input['outcome'] == 'working' ? 'closed' : 'needs_attention',
        'tenantConfirmations': {
          'offline-tenant': {
            'outcome': input['outcome'],
            'note': input['note'] ?? '',
            'recordedAtMs': DateTime(
              2026,
              9,
              26,
              14,
              20,
            ).millisecondsSinceEpoch,
          },
        },
      };
    } else {
      throw StateError(
        'Offline design preview. No live vendor, visit or bill is recorded.',
      );
    }
    changes.add(null);
  }

  @override
  Future<void> complete(
    Map<String, dynamic> input,
    Map<String, DocumentFile> files,
  ) async => throw StateError(
    'Offline design preview. No live completion or deduction is created.',
  );
  @override
  Future<DocumentFile> evidence(String issueId, String slot) async =>
      DocumentFile(
        name: slot == 'bill' ? 'TEST repair bill.pdf' : 'TEST $slot.png',
        bytes: slot == 'bill' ? testDocumentPdf() : _pixel(),
      );
  @override
  Future<Uint8List> readPhoto(String issueId, String path) async => _pixel();
  Uint8List _pixel() => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jH3sAAAAASUVORK5CYII=',
  );
}
