import '../../features/broker/data/agreement_imports.dart';
import '../../features/broker/data/private_documents.dart';
import '../../features/owner/data/owner_properties.dart';

class OfflineOwnerPropertyGateway implements OwnerPropertyGateway {
  final records = <String, OwnerPropertyRecord>{};
  final photos = <String, List<AgreementPageFile>>{};
  int attempts = 0;
  bool failNext = false;
  @override
  Future<List<OwnerPropertyRecord>> list({bool admin = false}) async =>
      records.values.toList();
  @override
  Future<OwnerPropertyRecord> save(
    OwnerPropertyRecord? property,
    int step,
    Map<String, dynamic> input,
    String operationId,
  ) async {
    attempts++;
    if (failNext) {
      failNext = false;
      throw const DocumentFailure('OFFLINE TEST · retry the saved step.');
    }
    final id = property?.id ?? operationId;
    final value = OwnerPropertyRecord({
      ...?property?.data,
      'id': id,
      'revision': (property?.revision ?? 0) + 1,
      'nextStep': step == 4 ? 4 : step + 1,
      'status': step == 4 ? 'property_added' : 'draft',
      'details': {...?property?.details, ...input},
      'photos': property?.photos ?? [],
    });
    records[id] = value;
    return value;
  }

  @override
  Future<OwnerPropertyRecord> uploadPhotos(
    OwnerPropertyRecord property,
    List<AgreementPageFile> selected,
    String operationId, {
    bool admin = false,
  }) async {
    photos[property.id] = List.of(selected);
    final value = OwnerPropertyRecord({
      ...property.data,
      'revision': property.revision + 1,
      'photos': selected.map((photo) => photo.payload).toList(),
    });
    records[property.id] = value;
    return value;
  }

  @override
  Future<AgreementPageFile> readPhoto(
    OwnerPropertyRecord property,
    int index, {
    bool admin = false,
  }) async => photos[property.id]![index];
  @override
  Future<OwnerPropertyRecord> requestPlan(
    OwnerPropertyRecord property,
    String plan,
    String method,
    String day,
    String slot,
  ) async {
    final value = OwnerPropertyRecord({
      ...property.data,
      'revision': property.revision + 1,
      'status': 'check_requested',
      'plan': plan,
      'check': {
        'status': 'requested',
        'method': method,
        'day': day,
        'slot': slot,
      },
    });
    records[property.id] = value;
    return value;
  }

  @override
  Future<OwnerPropertyRecord> recordCheck(
    OwnerPropertyRecord property,
    Map<String, dynamic> details,
  ) async => throw const DocumentFailure(
    'OFFLINE TEST · team actions are not connected to live appointments.',
  );
}
