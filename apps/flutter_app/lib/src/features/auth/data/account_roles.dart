import 'package:cloud_functions/cloud_functions.dart';

class AccountRoles {
  const AccountRoles({
    required this.name,
    required this.roles,
    this.brokerApproved = false,
  });
  final String name;
  final List<String> roles;
  final bool brokerApproved;
}

abstract interface class AccountRoleGateway {
  Future<AccountRoles> read();
  Future<String> select(String role);
  Future<String> add(String role);
}

class FirebaseAccountRoleGateway implements AccountRoleGateway {
  FirebaseAccountRoleGateway({FirebaseFunctions? functions})
    : functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');
  final FirebaseFunctions functions;
  @override
  Future<AccountRoles> read() async {
    final result = await functions.httpsCallable('readAccountRoles').call();
    final data = Map<String, dynamic>.from(result.data as Map);
    return AccountRoles(
      name: data['displayName'] as String? ?? '',
      roles: List<String>.from(data['roles'] as List),
      brokerApproved: data['brokerApproved'] == true,
    );
  }

  Future<String> _open(String function, String role) async {
    final result = await functions.httpsCallable(function).call({'role': role});
    final route = result.data['route'];
    if (!['/broker', '/broker/approval', '/owner', '/tenant'].contains(route)) {
      throw StateError('This role could not be opened.');
    }
    return route as String;
  }

  @override
  Future<String> select(String role) => _open('selectAccountRole', role);
  @override
  Future<String> add(String role) => _open('addAccountRole', role);
}

class OfflineAccountRoleGateway implements AccountRoleGateway {
  final roles = ['broker', 'owner'];
  @override
  Future<AccountRoles> read() async =>
      AccountRoles(name: 'Rahul', roles: List.of(roles), brokerApproved: true);
  @override
  Future<String> select(String role) async {
    if (!roles.contains(role)) {
      throw StateError('This offline role is not available.');
    }
    return role == 'broker'
        ? '/preview/broker-home'
        : '/ui-test/workspace/$role';
  }

  @override
  Future<String> add(String role) async {
    if (!['broker', 'owner', 'tenant'].contains(role)) {
      throw StateError('Choose a customer role.');
    }
    if (!roles.contains(role)) roles.add(role);
    return select(role);
  }
}
