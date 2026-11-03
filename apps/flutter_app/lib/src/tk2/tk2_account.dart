import '../features/account/data/account_gateway.dart';
import 'tk2_store.dart';

/// The main app's account screens (My details, Bank, Delete account) run
/// unchanged in TrustKeeper 2 through this gateway. Demo build: details are
/// kept on the phone in [Tk2Store]; the email code is 123456.
/// Backend: swap this for FirebaseAccountGateway – the screens stay the same.
class Tk2AccountGateway implements AccountGateway {
  Tk2AccountGateway(this.store);
  final Tk2Store store;

  static const demoCode = '123456';

  Map<String, dynamic> get _values => {
    'displayName': store.brokerName,
    'phone': store.brokerPhone,
    'phoneVerified': store.brokerPhone.isNotEmpty,
    'email': '',
    'emailVerified': false,
    'city': '',
    'reraNumber': '',
    'language': 'en',
    'bankName': '',
    'bankAccountLast4': '',
    'bankVerified': false,
    ...store.account,
  };

  @override
  Future<AccountProfileData> read() async => AccountProfileData(_values);

  @override
  Future<AccountProfileData> save(Map<String, dynamic> details) async {
    await store.saveAccount(details);
    return AccountProfileData(_values);
  }

  @override
  Future<String> requestEmail(String email) async => 'tk2-email';

  @override
  Future<void> verifyEmail(String email, String challenge, String code) async {
    if (challenge != 'tk2-email' || code != demoCode) {
      throw StateError('That code is not right. Demo code: $demoCode.');
    }
    await store.saveAccount({'email': email, 'emailVerified': true});
  }

  /// Nothing blocks closing in the demo: no money or signed agreements here.
  @override
  Future<Map<String, dynamic>> closure() async => {'canClose': true, 'blockers': <String>[], 'duePaise': 0, 'requiresLogin': false, 'status': 'open'};

  @override
  Future<Map<String, dynamic>> close({required String reason, required String note}) async {
    await store.wipe();
    return {'closed': true, 'recordsRetained': false};
  }

  @override
  Future<void> logout() => store.setBroker('', '');
}
