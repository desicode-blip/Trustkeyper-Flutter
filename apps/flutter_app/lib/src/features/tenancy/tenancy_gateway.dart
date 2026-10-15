import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TenancyRecord {
  TenancyRecord(this.data);
  final Map<String, dynamic> data;
  String text(String key) => data[key] as String? ?? '';
  bool flag(String key) => data[key] == true;
  int number(String key) => (data[key] as num?)?.toInt() ?? 0;
  Map<String, dynamic>? map(String key) =>
      data[key] is Map ? Map<String, dynamic>.from(data[key] as Map) : null;
  List<Map<String, dynamic>> rows(String key) => (data[key] as List? ?? [])
      .whereType<Map>()
      .map((value) => Map<String, dynamic>.from(value))
      .toList();
  List<Map<String, dynamic>> get items => rows('rooms')
      .expand((room) => (room['items'] as List).whereType<Map>())
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  int get recordedItems => items
      .where((item) => item['checkId'] != null || item['absentReason'] != null)
      .length;
}

abstract interface class TenancyGateway {
  Stream<TenancyRecord> watch(String agreementId, String role);
  Future<Map<String, dynamic>> record(Map<String, dynamic> input);
  Future<Map<String, dynamic>> issueCode(Map<String, dynamic> input);
  Future<void> refresh(String agreementId, String role);
}

class FirebaseTenancyGateway implements TenancyGateway {
  FirebaseTenancyGateway({
    this.moveOut = false,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FirebaseFirestore? database,
  }) : auth = auth ?? FirebaseAuth.instance,
       functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1'),
       database = database ?? FirebaseFirestore.instance;
  final FirebaseAuth auth;
  final bool moveOut;
  final FirebaseFunctions functions;
  final FirebaseFirestore database;
  final changes = StreamController<void>.broadcast();

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> input,
  ) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('Log in again to open this home.');
    final result = await functions.httpsCallable(name).call(input);
    if (auth.currentUser?.uid != uid) {
      throw StateError('Your login changed. Reopen this home.');
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  @override
  Stream<TenancyRecord> watch(String agreementId, String role) {
    late StreamController<TenancyRecord> controller;
    final subscriptions = <StreamSubscription<dynamic>>[];
    Timer? timer;
    var generation = 0;
    final uid = auth.currentUser?.uid;
    Future<void> load() async {
      final request = ++generation;
      try {
        if (uid == null || uid != auth.currentUser?.uid) {
          throw StateError('Your login changed. Reopen this home.');
        }
        final result = await _call(moveOut ? 'readMoveOut' : 'readTenancy', {
          'agreementId': agreementId,
          'role': role,
        });
        if (!controller.isClosed && request == generation) {
          controller.add(TenancyRecord(result));
        }
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

    controller = StreamController<TenancyRecord>(
      onListen: () {
        subscriptions.add(
          auth.authStateChanges().listen((user) {
            if (user?.uid != uid) {
              invalidate(StateError('Your login changed. Reopen this home.'));
            } else {
              load();
            }
          }),
        );
        for (final path in [
          'agreements/$agreementId',
          'tenancies/$agreementId',
          if (moveOut) 'moveOuts/$agreementId',
          if (uid != null) 'users/$uid',
        ]) {
          subscriptions.add(
            database
                .doc(path)
                .snapshots()
                .listen((_) => load(), onError: invalidate),
          );
        }
        subscriptions.add(changes.stream.listen((_) => load()));
        if (uid != null) {
          subscriptions.add(
            database
                .collection('payments')
                .where('participantUids', arrayContains: uid)
                .snapshots()
                .listen((_) => load(), onError: invalidate),
          );
        }
        timer = Timer.periodic(const Duration(minutes: 5), (_) => load());
        load();
      },
      onCancel: () async {
        generation++;
        timer?.cancel();
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<Map<String, dynamic>> record(Map<String, dynamic> input) async {
    final result = await _call(
      moveOut ? 'recordMoveOutAction' : 'recordTenancyAction',
      input,
    );
    changes.add(null);
    return result;
  }

  @override
  Future<Map<String, dynamic>> issueCode(Map<String, dynamic> input) =>
      _call(moveOut ? 'issueKeyReturnCode' : 'issueKeyConfirmationCode', input);
  @override
  Future<void> refresh(String agreementId, String role) async {
    changes.add(null);
  }
}
