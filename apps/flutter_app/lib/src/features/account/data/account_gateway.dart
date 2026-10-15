import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../auth/data/firebase_auth_service.dart';

class AccountProfileData {
  AccountProfileData(Map<String, dynamic> data)
    : values = Map.unmodifiable(data);
  final Map<String, dynamic> values;
  String text(String key) => values[key] is String ? values[key] as String : '';
  bool flag(String key) => values[key] == true;
}

abstract interface class AccountGateway {
  Future<AccountProfileData> read();
  Future<AccountProfileData> save(Map<String, dynamic> details);
  Future<String> requestEmail(String email);
  Future<void> verifyEmail(String email, String challenge, String code);
  Future<Map<String, dynamic>> closure();
  Future<Map<String, dynamic>> close({
    required String reason,
    required String note,
  });
  Future<void> logout();
}

class FirebaseAccountGateway implements AccountGateway {
  FirebaseAccountGateway({FirebaseFunctions? functions, FirebaseAuth? auth})
    : functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1'),
      auth = auth ?? FirebaseAuth.instance;
  final FirebaseFunctions functions;
  final FirebaseAuth auth;
  String? operation;
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> input,
  ) async => Map<String, dynamic>.from(
    (await functions
                .httpsCallable(
                  name,
                  options: HttpsCallableOptions(
                    timeout: const Duration(seconds: 35),
                  ),
                )
                .call(input))
            .data
        as Map,
  );
  @override
  Future<AccountProfileData> read() async =>
      AccountProfileData(await call('readAccountProfile', {}));
  @override
  Future<AccountProfileData> save(Map<String, dynamic> details) async {
    final uid = auth.currentUser?.uid;
    final result = await call('saveAccountProfile', details);
    if (auth.currentUser?.uid != uid || uid == null) {
      throw StateError('Your login changed.');
    }
    await auth.currentUser!.reload();
    return AccountProfileData(result);
  }

  @override
  Future<String> requestEmail(String email) =>
      FirebaseAuthService.instance.requestAccountEmailOtp(email);
  @override
  Future<void> verifyEmail(String email, String challenge, String code) async {
    await FirebaseAuthService.instance.verifyAccountEmailOtp(
      email: email,
      challengeId: challenge,
      code: code,
    );
  }

  @override
  Future<Map<String, dynamic>> closure() => call('readAccountClosure', {});
  @override
  Future<Map<String, dynamic>> close({
    required String reason,
    required String note,
  }) {
    operation ??= List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return call('closeAccount', {
      'operationId': operation,
      'confirmed': true,
      'reason': reason,
      'note': note,
    });
  }

  @override
  Future<void> logout() => FirebaseAuthService.instance.signOut();
}

abstract interface class AccountRestorationGateway {
  Future<List<Map<String, dynamic>>> pending();
  Future<void> finishClosure(String uid);
  Future<void> restore(String uid);
}

class FirebaseAccountRestorationGateway implements AccountRestorationGateway {
  final gateway = FirebaseAccountGateway();
  @override
  Future<List<Map<String, dynamic>>> pending() async =>
      ((await gateway.call('listAccountClosures', {}))['requests'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
  @override
  Future<void> finishClosure(String uid) async {
    await gateway.call('finishAccountClosure', {'uid': uid});
  }

  @override
  Future<void> restore(String uid) async {
    await gateway.call('restoreClosedAccount', {'uid': uid});
  }
}
