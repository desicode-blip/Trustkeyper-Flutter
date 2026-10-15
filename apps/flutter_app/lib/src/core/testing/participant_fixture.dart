import 'dart:async';
import 'dart:typed_data';

import '../../features/participants/data/participant_repository.dart';
import '../../features/participants/data/participant_workspace.dart';

class OfflineParticipantFixture
    implements ParticipantRepository, ParticipantIssueWriter, IssuePhotoReader {
  OfflineParticipantFixture({this.empty = false});
  final bool empty;
  final changes = StreamController<void>.broadcast();
  final issues = <ParticipantRecord>[];
  final photoBytes = <String, Uint8List>{};
  static const owner = ParticipantIdentity(
    uid: 'offline-owner',
    name: 'Rajesh Kumar',
    phone: '+919000000001',
  );
  static const tenant = ParticipantIdentity(
    uid: 'offline-tenant',
    name: 'Priya Sharma',
    phone: '+919000000002',
  );
  static final agreement = ParticipantRecord('offline-home', {
    'propertyAddress': 'Phoenix Towers 402',
    'participantUids': ['offline-owner', 'offline-tenant'],
    'status': 'review_requested',
    'monthlyRentPaise': 2200000,
    'securityDepositPaise': 4400000,
    'startDateISO': '2026-10-01',
    'endDateISO': '2027-08-31',
    'owners': [
      {
        'id': 'owner',
        'uid': owner.uid,
        'name': owner.name,
        'phone': owner.phone,
      },
    ],
    'tenants': [
      {
        'id': 'tenant',
        'uid': tenant.uid,
        'name': tenant.name,
        'phone': tenant.phone,
        'rentSharePaise': 1100000,
        'depositSharePaise': 2200000,
      },
    ],
  });
  List<ParticipantRecord> _records(String collection) => empty
      ? []
      : switch (collection) {
          'agreements' => [agreement],
          'payouts' => [
            ParticipantRecord('offline-payout', {
              'title': 'October 2026',
              'amountPaise': 4535000,
              'scheduledAt': DateTime(2026, 10, 7),
              'status': 'scheduled',
            }),
          ],
          'payments' => [
            ParticipantRecord('offline-rent', {
              'title': 'October rent',
              'amountPaise': 1100000,
              'dueDate': DateTime(2026, 10, 5),
              'status': 'pending',
            }),
          ],
          'issues' => issues,
          _ => throw ArgumentError('Unsupported fixture collection'),
        };
  @override
  Stream<List<ParticipantRecord>> watch(String collection) =>
      Stream.multi((controller) {
        controller.add(List.of(_records(collection)));
        final subscription = changes.stream.listen(
          (_) => controller.add(List.of(_records(collection))),
        );
        controller.onCancel = subscription.cancel;
      });
  @override
  Future<String> create(IssueInput input) async {
    if (empty || input.agreementId != agreement.id || input.error != null) {
      throw StateError('Invalid fixture issue');
    }
    final id = 'offline-issue-${issues.length + 1}';
    for (var index = 0; index < input.photos.length; index++) {
      photoBytes['issues/$id/photos/$index'] = input.photos[index].bytes;
    }
    issues.add(
      ParticipantRecord(id, {
        'title': '${input.category} problem',
        'description': input.description.trim(),
        'status': 'open',
        'propertyAddress': agreement.text('propertyAddress'),
        'createdAt': DateTime.now(),
        'photos': [
          for (var index = 0; index < input.photos.length; index++)
            {'path': 'issues/$id/photos/$index'},
        ],
      }),
    );
    changes.add(null);
    return id;
  }

  @override
  Future<Uint8List> readPhoto(String issueId, String path) async {
    final bytes = photoBytes[path];
    if (bytes == null) throw StateError('Fixture photo unavailable');
    return bytes;
  }
}
