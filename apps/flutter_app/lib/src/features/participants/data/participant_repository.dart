import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ParticipantRecord {
  ParticipantRecord(this.id, Map<String, dynamic> data)
    : data = Map.unmodifiable(data);
  final String id;
  final Map<String, dynamic> data;
  String text(String key, [String fallback = 'Not available']) {
    final value = data[key];
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }

  int? amount(String key) {
    final value = data[key];
    return value is int && value >= 0 ? value : null;
  }
}

abstract interface class ParticipantRepository {
  Stream<List<ParticipantRecord>> watch(String collection);
}

typedef ParticipantQuery =
    Stream<List<ParticipantRecord>> Function(String collection, String uid);

class SessionParticipantRepository implements ParticipantRepository {
  SessionParticipantRepository({required this.identities, required this.query});
  factory SessionParticipantRepository.firebase() {
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;
    return SessionParticipantRepository(
      identities: auth.authStateChanges().map((user) => user?.uid),
      query: (collection, uid) => firestore
          .collection(collection)
          .where('participantUids', arrayContains: uid)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (document) => ParticipantRecord(document.id, document.data()),
                )
                .toList(),
          ),
    );
  }
  final Stream<String?> identities;
  final ParticipantQuery query;
  static const collections = {'agreements', 'payments', 'payouts', 'issues'};

  @override
  Stream<List<ParticipantRecord>> watch(String collection) {
    if (!collections.contains(collection)) {
      throw ArgumentError('Unsupported collection');
    }
    late StreamController<List<ParticipantRecord>> controller;
    StreamSubscription<String?>? identitySubscription;
    StreamSubscription<List<ParticipantRecord>>? dataSubscription;
    var generation = 0;
    controller = StreamController<List<ParticipantRecord>>(
      onListen: () {
        identitySubscription = identities.distinct().listen(
          (uid) {
            final active = ++generation;
            dataSubscription?.cancel();
            dataSubscription = null;
            controller.add(const []);
            if (uid == null) return;
            try {
              dataSubscription = query(collection, uid).listen(
                (records) {
                  if (generation != active || controller.isClosed) return;
                  controller.add(
                    List.unmodifiable(
                      records.where((record) {
                        final participants = record.data['participantUids'];
                        return participants is List &&
                            participants.contains(uid);
                      }),
                    ),
                  );
                },
                onError: (Object error, StackTrace stack) {
                  if (generation == active && !controller.isClosed) {
                    controller.addError(error, stack);
                  }
                },
              );
            } catch (error, stack) {
              controller.addError(error, stack);
            }
          },
          onError: (Object error, StackTrace stack) {
            ++generation;
            dataSubscription?.cancel();
            controller.addError(error, stack);
          },
        );
      },
      onCancel: () async {
        ++generation;
        await identitySubscription?.cancel();
        await dataSubscription?.cancel();
      },
    );
    return controller.stream;
  }
}
