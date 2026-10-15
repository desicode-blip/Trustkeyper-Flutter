import '../../features/broker/data/private_documents.dart';
import '../../features/document_requests/data/document_request_repository.dart';
import '../../features/document_requests/data/recipient_document_gateway.dart';

class OfflineRecipientFixture implements RecipientDocumentGateway {
  OfflineRecipientFixture({required this.paper});
  final RequestedPaper paper;
  bool received = false;
  @override
  Future<DocumentRequestInfo> read(String token) async => DocumentRequestInfo({
    'requestId': 'offline-fixture',
    'type': paper.name,
    'status': received ? 'added' : 'seen',
    'verified': true,
    'phone': '+919000000001',
    'partyName': 'Offline Test Person',
    'brokerName': 'Offline Test Broker',
    'address': 'OFFLINE FIXTURE · NO LIVE PROPERTY',
    'role': [RequestedPaper.bank, RequestedPaper.all].contains(paper)
        ? 'owner'
        : 'tenant',
    'version': 1,
    'expiresAtMs': DateTime.now()
        .add(const Duration(days: 1))
        .millisecondsSinceEpoch,
  });
  @override
  Future<bool> requestOtp(String phone) async =>
      throw const DocumentFailure('Offline fixture: no OTP is sent.');
  @override
  Future<void> verifyOtp(String code) async => throw const DocumentFailure(
    'Offline fixture: authentication is disabled.',
  );
  @override
  Future<void> signOut() async {
    received = false;
  }

  @override
  Future<DocumentRequestInfo> submit(
    String token,
    Map<DocumentKind, DocumentFile> files,
    void Function(double) progress, {
    Map<String, dynamic>? bankDetails,
    Map<String, dynamic>? linkedInDetails,
  }) async {
    final slots = paper.slots
        .where((kind) => bankDetails == null || kind != DocumentKind.bankProof)
        .toList();
    if (!slots.every(files.containsKey) || files.length != slots.length) {
      throw const DocumentFailure('Select every fixture page.');
    }
    for (final file in files.values) {
      file.validate();
    }
    received = true;
    progress(1);
    return read(token);
  }
}
