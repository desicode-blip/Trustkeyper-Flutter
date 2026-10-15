import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RenewalSource {
  RenewalSource(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
  String get address => data['propertyAddress'] as String? ?? '';
  int get revision => (data['revision'] as num).toInt();
  String get digest => (data['agreementCopy'] as Map)['digest'] as String;
  DateTime get end => DateTime.parse(data['endDateISO'] as String);
  DateTime get nextStart => DateTime(end.year, end.month, end.day + 1);
  List<Map> people(String role) =>
      (data[role] as List).whereType<Map>().toList();
  String names(String role) =>
      people(role).map((person) => person['name']).join(', ');
  String get identity => '$id:$revision:$digest';
  static bool available(Map<String, dynamic> data, String uid) {
    final copy = data['agreementCopy'];
    bool peopleValid(String key) =>
        data[key] is List &&
        (data[key] as List).isNotEmpty &&
        (data[key] as List).every(
          (person) => person is Map && person['name'] is String,
        );
    return data['brokerUid'] == uid &&
        ['signed_copy_received', 'active'].contains(data['status']) &&
        copy is Map &&
        copy['mode'] == 'externally_signed' &&
        copy['revision'] == data['revision'] &&
        copy['digest'] is String &&
        data['revision'] is int &&
        (data['revision'] as int) > 0 &&
        data['monthlyRentPaise'] is int &&
        data['securityDepositPaise'] is int &&
        DateTime.tryParse(data['startDateISO'] as String? ?? '') != null &&
        DateTime.tryParse(data['endDateISO'] as String? ?? '') != null &&
        peopleValid('owners') &&
        peopleValid('tenants');
  }
}

abstract interface class AgreementRenewalGateway {
  Stream<List<RenewalSource>> watch();
  Future<Map<String, dynamic>> create(RenewalSource source, String operationId);
}

String renewalOperationId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class FirebaseAgreementRenewalGateway implements AgreementRenewalGateway {
  FirebaseAgreementRenewalGateway({
    FirebaseAuth? auth,
    FirebaseFirestore? database,
    FirebaseFunctions? functions,
  }) : auth = auth ?? FirebaseAuth.instance,
       database = database ?? FirebaseFirestore.instance,
       functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');
  final FirebaseAuth auth;
  final FirebaseFirestore database;
  final FirebaseFunctions functions;
  @override
  Stream<List<RenewalSource>> watch() {
    late StreamController<List<RenewalSource>> controller;
    StreamSubscription<User?>? identity;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? profile;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? agreements;
    var generation = 0;
    var queryGeneration = 0;
    Future<void> bind(User? user) async {
      final request = ++generation;
      queryGeneration++;
      await profile?.cancel();
      await agreements?.cancel();
      if (controller.isClosed || request != generation) return;
      controller.addError(
        StateError(
          user == null
              ? 'Log in to renew an agreement.'
              : 'Checking your broker account.',
        ),
      );
      if (user == null) return;
      profile = database
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(
            (snapshot) async {
              final queryRequest = ++queryGeneration;
              await agreements?.cancel();
              if (controller.isClosed ||
                  request != generation ||
                  queryRequest != queryGeneration) {
                return;
              }
              controller.addError(StateError('Checking your broker account.'));
              final account = snapshot.data();
              if (account?['paused'] == true ||
                  account?['approvalStatus'] != 'approved' ||
                  !(account?['roles'] as List? ?? []).contains('broker')) {
                controller.addError(
                  StateError('An approved broker account is required.'),
                );
                return;
              }
              agreements = database
                  .collection('agreements')
                  .where('participantUids', arrayContains: user.uid)
                  .snapshots()
                  .listen(
                    (result) {
                      if (controller.isClosed ||
                          request != generation ||
                          queryRequest != queryGeneration) {
                        return;
                      }
                      final sources =
                          result.docs
                              .where(
                                (document) => RenewalSource.available(
                                  document.data(),
                                  user.uid,
                                ),
                              )
                              .map(
                                (document) =>
                                    RenewalSource(document.id, document.data()),
                              )
                              .toList()
                            ..sort(
                              (left, right) => left.end.compareTo(right.end),
                            );
                      controller.add(sources);
                    },
                    onError: (Object error) {
                      if (!controller.isClosed &&
                          request == generation &&
                          queryRequest == queryGeneration) {
                        controller.addError(error);
                      }
                    },
                  );
            },
            onError: (Object error) {
              if (!controller.isClosed && request == generation) {
                queryGeneration++;
                agreements?.cancel();
                controller.addError(error);
              }
            },
          );
    }

    controller = StreamController<List<RenewalSource>>(
      onListen: () => identity = auth.authStateChanges().listen(bind),
      onCancel: () async {
        generation++;
        await identity?.cancel();
        await profile?.cancel();
        await agreements?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<Map<String, dynamic>> create(
    RenewalSource source,
    String operationId,
  ) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('Log in again to renew this agreement.');
    final response = await functions
        .httpsCallable('createAgreementRenewal')
        .call({
          'sourceAgreementId': source.id,
          'revision': source.revision,
          'digest': source.digest,
          'operationId': operationId,
        });
    if (uid != auth.currentUser?.uid) {
      throw StateError('Your login changed. Open your records again.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }
}
