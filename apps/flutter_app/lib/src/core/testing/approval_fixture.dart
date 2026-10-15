import '../../features/agreement_approvals/data/agreement_approvals.dart';
import '../../features/broker/data/agreement_draft.dart';
import '../../features/broker/data/private_documents.dart';
import '../../features/agreement_copies/agreement_copies.dart';

class OfflineApprovalFixture implements AgreementRecipientGateway {
  @override
  Future<AgreementCopyFile> readCopy(String agreementId, int revision) async =>
      throw const DocumentFailure(
        'This offline fixture has no published signed copy.',
      );
  OfflineApprovalFixture({this.role = 'owner', this.changed = false});
  final String role;
  final bool changed;
  bool verified = true;
  String status = 'seen';
  Map<String, dynamic>? recordedReply;
  AgreementDraft get draft => AgreementDraft(
    id: 'offline-approval',
    propertyAddress: 'OFFLINE TEST · Flat 402, Test Towers',
    owners: const [
      AgreementParty(
        id: 'owner-test',
        name: 'Test Owner',
        phone: '+911111111111',
      ),
    ],
    tenants: const [
      AgreementParty(
        id: 'tenant-test',
        name: 'Test Tenant',
        phone: '+912222222222',
        rentSharePaise: 2200000,
        depositSharePaise: 4400000,
      ),
    ],
    monthlyRentPaise: 2200000,
    maintenancePaise: 0,
    depositPaise: 4400000,
    ownerBrokeragePaise: 1100000,
    tenantBrokeragePaise: 2200000,
    startDate: DateTime(2026, 10, 1),
    endDate: DateTime(2027, 8, 31),
    lockInMonths: 6,
    noticeMonths: 1,
    revision: changed ? 2 : 1,
    rentDueDay: changed ? 10 : 5,
  );
  @override
  Future<ApprovalInfo> read(String token) async => ApprovalInfo({
    'verified': verified,
    'invitationId': 'offline-approval',
    'role': role,
    'phoneMasked': role == 'owner' ? '+91 ••••••1111' : '+91 ••••••2222',
    'brokerName': 'Offline Test Broker',
    if (verified) ...{
      'agreementId': draft.id,
      'revision': draft.revision,
      'digest': 'offline-fixture-digest',
      'partyId': role == 'owner' ? 'owner-test' : 'tenant-test',
      'partyName': role == 'owner' ? 'Test Owner' : 'Test Tenant',
      'status': status,
      'snapshot': draft.toMap(),
      'demoOnly': true,
      'signable': false,
      'changedFields': [if (changed) 'rentDueDay'],
      'reply': recordedReply ?? {'status': status},
      'people': [
        {
          'id': 'owner-test',
          'name': 'Test Owner',
          'role': 'owner',
          'status': role == 'owner' ? status : 'not_opened',
        },
        {
          'id': 'tenant-test',
          'name': 'Test Tenant',
          'role': 'tenant',
          'status': role == 'tenant' ? status : 'not_opened',
        },
      ],
    },
  });
  @override
  Future<ApprovalInfo> reply(
    String token,
    ApprovalInfo info,
    Map<String, dynamic> reply,
  ) async {
    status = reply['decision'] as String;
    recordedReply = Map.from(reply);
    return read(token);
  }

  @override
  String operationId() => 'offline-reply';
  @override
  Future<bool> requestOtp(String phone) async =>
      throw const DocumentFailure('Offline preview cannot send real OTP.');
  @override
  Future<void> verifyOtp(String code) async =>
      throw const DocumentFailure('Offline preview cannot verify real OTP.');
  @override
  Future<void> signOut() async {
    verified = false;
  }
}
