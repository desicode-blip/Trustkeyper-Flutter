import '../../features/tenant/data/tenant_setup.dart';

class OfflineTenantSetupGateway implements TenantSetupGateway {
  OfflineTenantSetupGateway({int step = 0})
    : values = {
        'revision': 1,
        'property': 'Flat 402, Phoenix Towers',
        'ownerNames': ['Rajesh Kumar'],
        'brokerName': 'Rahul',
        'rentSharePaise': 1100000,
        'depositSharePaise': 2200000,
        'monthlyRentPaise': 2200000,
        'homeConfirmed': step >= 1,
        'flatmatesConfirmed': step >= 2,
        'complete': false,
        'request': null,
        'tenants': [
          {
            'name': 'Priya Sharma',
            'phone': '+919876543211',
            'you': true,
            'rentSharePaise': 1100000,
          },
          {
            'name': 'Rahul Verma',
            'phone': '+919010122334',
            'you': false,
            'rentSharePaise': 1100000,
          },
        ],
      };
  final Map<String, dynamic> values;
  @override
  Future<TenantSetupData> read(String agreementId) async =>
      TenantSetupData(Map.from(values));
  @override
  Future<TenantSetupData> record(
    String agreementId,
    int revision,
    String action, {
    String? kind,
    int? rentSharePaise,
    String? note,
  }) async {
    if (action == 'home') {
      values['homeConfirmed'] = true;
    }
    if (action == 'flatmates') {
      values['flatmatesConfirmed'] = true;
    }
    if (action == 'complete') {
      values['complete'] = true;
    }
    if (action == 'request') {
      values['request'] = {
        'kind': kind,
        'status': 'pending',
        'note': note,
        'rentSharePaise': ?rentSharePaise,
      };
    }
    return TenantSetupData(Map.from(values));
  }

  @override
  Future<List<Map<String, dynamic>>> pending() async => [];
  @override
  Future<void> resolve(Map<String, dynamic> request) async =>
      throw StateError('Offline fixture: no real team request is resolved.');
}
