import '../../features/broker/data/agreement_imports.dart';
import '../../features/broker/data/private_documents.dart';
import '../../features/owner/data/owner_lifecycle.dart';
import '../../features/owner/data/owner_properties.dart';

class OfflineOwnerLifecycleGateway implements OwnerLifecycleGateway {
  Never _unavailable() => throw const DocumentFailure(
    'OFFLINE UI TEST · real owner contracts, listings and tenant decisions require the normal Firebase app.',
  );
  @override
  Future<Map<String, dynamic>> change(
    OwnerPropertyRecord property,
    String action,
    Map<String, dynamic> input,
  ) async => _unavailable();
  @override
  Future<OwnerPropertyRecord> uploadContract(
    OwnerPropertyRecord property,
    AgreementPageFile file,
    String kind,
    String reference,
    String operationId, {
    required bool signaturesChecked,
  }) async => _unavailable();
  @override
  Future<AgreementPageFile> readContract(
    OwnerPropertyRecord property, {
    bool signed = false,
    bool admin = false,
  }) async => _unavailable();
  @override
  Future<Map<String, dynamic>> readPublic(String id) async => _unavailable();
  @override
  Future<AgreementPageFile> readPublicPhoto(String id, int index) async =>
      _unavailable();
  @override
  Future<void> enquire(String id, Map<String, dynamic> input) async =>
      _unavailable();
  @override
  Future<Map<String, dynamic>> receipt(String id) async => _unavailable();
}

class OfflineOwnerContractPhoneProof implements OwnerContractPhoneProof {
  @override
  String get phone => 'OFFLINE UI TEST';
  @override
  Future<void> sendCode() async => throw const DocumentFailure(
    'OFFLINE UI TEST · no SMS or legal consent is created.',
  );
  @override
  Future<void> confirmCode(String code) async =>
      throw const DocumentFailure('OFFLINE UI TEST · no OTP is verified.');
}
