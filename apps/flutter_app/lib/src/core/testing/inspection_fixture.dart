import 'dart:async';
import 'dart:convert';

import '../../features/broker/data/private_documents.dart';
import '../../features/inspections/inspection_gateway.dart';

class OfflineInspectionFixture implements InspectionGateway {
  OfflineInspectionFixture({this.role = 'broker'});
  final String role;
  final updates = StreamController<void>.broadcast();
  final checks = <Map<String, dynamic>>[
    {
      'id': 'offline-kitchen',
      'title': 'Kitchen tap leak',
      'room': 'Kitchen',
      'actorName': 'Priya Sharma',
      'actorRole': 'Tenant',
      'status': 'flagged',
      'receivedAtMs': DateTime(2026, 11, 2, 9, 14).millisecondsSinceEpoch,
      'version': 1,
    },
    {
      'id': 'offline-visit',
      'title': 'Owner visit',
      'room': 'Living room',
      'actorName': 'Rajesh Kumar',
      'actorRole': 'Owner',
      'status': 'approved',
      'receivedAtMs': DateTime(2026, 10, 20, 16, 5).millisecondsSinceEpoch,
      'version': 1,
    },
  ];
  int saved = 0;
  @override
  Stream<InspectionList> watch(
    String propertyId,
    String? agreementId, [
    String? selectedRole,
  ]) => Stream.multi((controller) {
    void emit() => controller.add(
      InspectionList({
        'address': 'Phoenix Towers 402',
        'actorRole': role,
        'canCapture': role != 'admin',
        'checks': List.of(checks),
      }),
    );
    emit();
    final subscription = updates.stream.listen((_) => emit());
    controller.onCancel = subscription.cancel;
  });
  @override
  Future<Map<String, dynamic>> begin(Map<String, dynamic> input) async => {
    'checkId': 'offline-new',
    'startedAtMs': DateTime(2026, 9, 25, 12, 20).millisecondsSinceEpoch,
    'actorName': 'Rahul Sharma',
    'actorRole': role,
    'request': input,
  };
  @override
  Future<void> save(Map<String, dynamic> grant, DocumentFile file) async {
    file.validate();
    final request = grant['request'] as Map;
    saved++;
    checks.insert(0, {
      'id': 'offline-new-$saved',
      'title': request['title'],
      'room': request['room'],
      'note': request['note'],
      'actorName': grant['actorName'],
      'actorRole': role,
      'status': 'submitted',
      'receivedAtMs': grant['startedAtMs'],
      'version': 1,
    });
    updates.add(null);
  }

  @override
  Future<DocumentFile> photo(String propertyId, String checkId) async =>
      camera();
  Future<DocumentFile> camera() async => DocumentFile(
    name: 'TEST camera photo.png',
    bytes: base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAFklEQVR4nGMwTPhPEmIY1TCqYfhqAADY3ZAQ0l74KQAAAABJRU5ErkJggg==',
    ),
  );
  @override
  Future<void> review(Map<String, dynamic> input) async {
    final check = checks.firstWhere((value) => value['id'] == input['checkId']);
    check['status'] = input['status'];
    check['reviewNote'] = input['note'];
    updates.add(null);
  }
}
