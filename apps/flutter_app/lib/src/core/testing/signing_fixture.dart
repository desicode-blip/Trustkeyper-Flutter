import '../../features/broker/data/agreement_imports.dart';
import '../../features/broker/data/private_documents.dart';
import 'document_fixture.dart';

class OfflineSigningGateway implements AgreementImportGateway {
  final values = <SigningRequest>[];
  bool failFirstSend = false;
  final operations = <String>[];
  @override
  Future<String> send(
    List<AgreementPageFile> files,
    List<AgreementSigner> signers,
    String operationId,
  ) async {
    validateSigningRequest(files, signers);
    operations.add(operationId);
    if (failFirstSend && operations.length == 1) {
      throw const DocumentFailure(
        'TEST connection interrupted. Retry the same send.',
      );
    }
    final existing = values.where(
      (value) => value.data['operationId'] == operationId,
    );
    if (existing.isNotEmpty) return existing.first.id;
    const id = 'offline-signing-request';
    values.add(
      SigningRequest({
        'id': id,
        'operationId': operationId,
        'status': 'received',
        'revision': 2,
        'pageCount': 1,
        'signers': signers.map((person) => person.payload).toList(),
        'updatedAtMs': DateTime(2026, 10, 10, 12).millisecondsSinceEpoch,
      }),
    );
    return id;
  }

  @override
  Future<List<SigningRequest>> list() async => List.unmodifiable(values);
  @override
  Future<AgreementPageFile> read(String id, {bool signed = false}) async =>
      AgreementPageFile(
        name: 'OFFLINE TEST · not a legal agreement.pdf',
        bytes: testDocumentPdf(),
      );
  @override
  Future<void> record(
    SigningRequest request,
    String status,
    String reference,
    String note,
  ) async {
    throw const DocumentFailure(
      'Offline fixtures cannot update actual signing.',
    );
  }

  @override
  Future<void> publish(
    SigningRequest request,
    AgreementPageFile file,
    String operationId,
  ) async {
    throw const DocumentFailure(
      'Offline fixtures cannot publish legal originals.',
    );
  }
}
