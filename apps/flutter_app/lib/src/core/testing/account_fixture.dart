import '../../features/account/data/account_gateway.dart';

class OfflineAccountGateway implements AccountGateway {
  final values = <String, dynamic>{
    'displayName': 'Rahul Sharma',
    'phone': '+919848011223',
    'phoneVerified': true,
    'email': 'rahul.broker@example.invalid',
    'emailVerified': true,
    'city': 'Hyderabad',
    'reraNumber': '',
    'language': 'en',
    'bankName': 'State Bank of India',
    'bankAccountLast4': '7766',
    'bankVerified': false,
  };
  final saved = <Map<String, dynamic>>[];
  bool blocked = false, staleLogin = false, closed = false, loggedOut = false;
  @override
  Future<AccountProfileData> read() async => AccountProfileData(values);
  @override
  Future<AccountProfileData> save(Map<String, dynamic> details) async {
    saved.add(Map.of(details));
    values.addAll(details);
    return AccountProfileData(values);
  }

  @override
  Future<String> requestEmail(String email) async => 'offline-email-challenge';
  @override
  Future<void> verifyEmail(String email, String challenge, String code) async {
    if (code.length != 6 || challenge != 'offline-email-challenge') {
      throw StateError('Enter six digits.');
    }
    values['email'] = email;
    values['emailVerified'] = true;
  }

  @override
  Future<Map<String, dynamic>> closure() async => {
    'canClose': !blocked,
    'blockers': blocked
        ? [
            'Close or transfer your active signed agreements with the team first.',
          ]
        : <String>[],
    'duePaise': 0,
    'requiresLogin': staleLogin,
    'status': closed ? 'closed' : 'open',
  };
  @override
  Future<Map<String, dynamic>> close({
    required String reason,
    required String note,
  }) async {
    if (blocked || staleLogin) throw StateError('This closure is not ready.');
    closed = true;
    return {'closed': true, 'recordsRetained': true};
  }

  @override
  Future<void> logout() async {
    loggedOut = true;
  }
}
