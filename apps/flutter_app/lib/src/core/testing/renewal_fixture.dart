import '../../features/broker/data/agreement_draft.dart';
import '../../features/broker/data/agreement_renewals.dart';

class OfflineRenewalGateway implements AgreementRenewalGateway {
  OfflineRenewalGateway({this.saveDraft});
  final void Function(AgreementDraft draft)? saveDraft;
  final source = RenewalSource('offline-old-agreement', {
    'propertyId': 'offline-flat',
    'propertyAddress': 'TEST Phoenix Towers 402',
    'brokerUid': 'ui-test-broker',
    'status': 'active',
    'revision': 1,
    'agreementCopy': {
      'mode': 'externally_signed',
      'revision': 1,
      'digest': List.filled(64, 'a').join(),
    },
    'owners': [
      const AgreementParty(
        id: 'owner-1',
        name: 'TEST Rajesh Kumar',
        phone: '+911111111111',
      ).toMap(),
    ],
    'tenants': [
      const AgreementParty(
        id: 'tenant-1',
        name: 'TEST Priya Sharma',
        phone: '+912222222222',
        rentSharePaise: 2200000,
        depositSharePaise: 4400000,
      ).toMap(),
    ],
    'monthlyRentPaise': 2200000,
    'securityDepositPaise': 4400000,
    'startDateISO': '2025-11-01T00:00:00.000',
    'endDateISO': '2026-09-30T00:00:00.000',
    'rentDueDay': 5,
    'lockInMonths': 6,
    'noticeMonths': 1,
  });
  @override
  Stream<List<RenewalSource>> watch() => Stream.value([source]);
  @override
  Future<Map<String, dynamic>> create(
    RenewalSource source,
    String operationId,
  ) async {
    final start = source.nextStart;
    final draft = AgreementDraft.fromMap('offline-renewal', {
      ...source.data,
      'renewalSourceId': source.id,
      'startDateISO': start.toIso8601String(),
      'endDateISO': addCalendarMonths(
        start,
        11,
      ).subtract(const Duration(days: 1)).toIso8601String(),
    });
    saveDraft?.call(draft);
    return {'agreementId': draft.id, 'status': 'draft', 'resumed': false};
  }
}
