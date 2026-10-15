import 'package:cloud_functions/cloud_functions.dart';

class TenantSetupData {
  const TenantSetupData(this.values);
  final Map<String, dynamic> values;
  int get revision => values['revision'] as int;
  String get property => values['property'] as String;
  String get brokerName => values['brokerName'] as String;
  List<String> get owners => (values['ownerNames'] as List).cast<String>();
  List<Map<String, dynamic>> get tenants => (values['tenants'] as List)
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList();
  int get rent => values['rentSharePaise'] as int;
  int get deposit => values['depositSharePaise'] as int;
  int get totalRent => values['monthlyRentPaise'] as int;
  bool get homeConfirmed => values['homeConfirmed'] == true;
  bool get flatmatesConfirmed => values['flatmatesConfirmed'] == true;
  bool get complete => values['complete'] == true;
  bool get pending =>
      values['request'] is Map && values['request']['status'] == 'pending';
}

abstract interface class TenantSetupGateway {
  Future<TenantSetupData> read(String agreementId);
  Future<TenantSetupData> record(
    String agreementId,
    int revision,
    String action, {
    String? kind,
    int? rentSharePaise,
    String? note,
  });
  Future<List<Map<String, dynamic>>> pending();
  Future<void> resolve(Map<String, dynamic> request);
}

class FirebaseTenantSetupGateway implements TenantSetupGateway {
  FirebaseTenantSetupGateway({FirebaseFunctions? functions})
    : functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');
  final FirebaseFunctions functions;
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> input,
  ) async {
    final result = await functions
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
        )
        .call(input);
    return Map<String, dynamic>.from(result.data as Map);
  }

  @override
  Future<TenantSetupData> read(String agreementId) async => TenantSetupData(
    await _call('readTenantSetup', {'agreementId': agreementId}),
  );
  @override
  Future<TenantSetupData> record(
    String agreementId,
    int revision,
    String action, {
    String? kind,
    int? rentSharePaise,
    String? note,
  }) async => TenantSetupData(
    await _call('recordTenantSetup', {
      'agreementId': agreementId,
      'revision': revision,
      'action': action,
      'kind': ?kind,
      'rentSharePaise': ?rentSharePaise,
      'note': ?note,
    }),
  );
  @override
  Future<List<Map<String, dynamic>>> pending() async =>
      ((await _call('listTenantSetupRequests', {}))['requests'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
  @override
  Future<void> resolve(Map<String, dynamic> request) async {
    await _call('resolveTenantSetupRequest', {
      'agreementId': request['agreementId'],
      'tenantUid': request['tenantUid'],
      'revision': request['revision'],
    });
  }
}

int? tenantSharePaise(String value) {
  final input = value.trim();
  if (input.contains(',') &&
      !RegExp(
        r'^(?:\d{1,3}(?:,\d{3})+|\d{1,2}(?:,\d{2})*,\d{3})(?:\.\d{1,2})?$',
      ).hasMatch(input)) {
    return null;
  }
  final normalized = input.replaceAll(',', '');
  if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(normalized)) {
    return null;
  }
  final parts = normalized.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
}
