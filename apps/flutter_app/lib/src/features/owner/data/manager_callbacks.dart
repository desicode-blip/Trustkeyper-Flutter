import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

abstract interface class ManagerCallbackGateway {
  Stream<Map<String, dynamic>> watch(String? ownerUid);
  Future<Map<String, dynamic>> record(Map<String, dynamic> input);
  Future<List<Map<String, dynamic>>> list();
  Future<void> refresh();
}

class FirebaseManagerCallbackGateway implements ManagerCallbackGateway {
  FirebaseManagerCallbackGateway({
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
  final changes = StreamController<void>.broadcast();
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> input,
  ) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('Log in again.');
    final response = await functions.httpsCallable(name).call(input);
    if (uid != auth.currentUser?.uid) {
      throw StateError('Your login changed. Reopen this page.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Stream<Map<String, dynamic>> watch(String? ownerUid) {
    late StreamController<Map<String, dynamic>> controller;
    final subscriptions = <StreamSubscription<dynamic>>[];
    var generation = 0;
    final uid = auth.currentUser?.uid;
    Future<void> load() async {
      final request = ++generation;
      try {
        if (uid == null || auth.currentUser?.uid != uid) {
          throw StateError('Your login changed. Reopen this page.');
        }
        final data = await _call(
          'readManagerCallback',
          ownerUid == null ? {} : {'ownerUid': ownerUid},
        );
        if (!controller.isClosed && request == generation) controller.add(data);
      } catch (error, stack) {
        if (!controller.isClosed && request == generation) {
          controller.addError(error, stack);
        }
      }
    }

    void invalidate(Object error) {
      generation++;
      if (!controller.isClosed) controller.addError(error);
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        subscriptions.add(
          auth.authStateChanges().listen((user) {
            if (user?.uid != uid) {
              invalidate(StateError('Your login changed. Reopen this page.'));
            } else {
              load();
            }
          }),
        );
        if (uid != null) {
          for (final path in [
            'users/$uid',
            'ownerCallbacks/${ownerUid ?? uid}',
          ]) {
            subscriptions.add(
              database
                  .doc(path)
                  .snapshots()
                  .listen((_) => load(), onError: invalidate),
            );
          }
        }
        subscriptions.add(changes.stream.listen((_) => load()));
        load();
      },
      onCancel: () async {
        generation++;
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<Map<String, dynamic>> record(Map<String, dynamic> input) async {
    final result = await _call('recordManagerCallback', input);
    changes.add(null);
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> list() async =>
      ((await _call('listManagerCallbacks', {}))['records'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
  @override
  Future<void> refresh() async {
    changes.add(null);
  }
}
