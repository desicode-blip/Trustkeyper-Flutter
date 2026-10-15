import 'dart:async';
import '../../features/broker/data/agreement_draft.dart';
import 'document_fixture.dart';
import '../../features/broker/data/private_documents.dart';
import '../../features/document_requests/data/document_request_repository.dart';

class OfflineDocumentRequests implements DocumentRequests {
  @override
  Stream<List<DocumentRequestInfo>> watch(String draftId, int revision) =>
      Stream.value([]);

  @override
  Future<IssuedDocumentLink> create({
    required String draftId,
    required int revision,
    required String partyId,
    required RequestedPaper paper,
    bool remind = false,
  }) async => throw const DocumentFailure(
    'Offline UI Test: no live link or message is created. Test real sharing in the Firebase app.',
  );

  @override
  Future<void> record(
    DocumentRequestInfo info,
    String action, {
    String? reason,
    String? channel,
    RequestedPaper? paper,
    Map<String, dynamic>? linkedInDetails,
  }) async => throw const DocumentFailure(
    'Offline UI Test: no backend request is changed.',
  );

  @override
  Future<DocumentFile> readFile(Map<String, dynamic> file) async =>
      throw const DocumentFailure(
        'Offline UI Test: no private server file is read.',
      );
}

class OfflineBrokerDocumentStates extends OfflineDocumentRequests {
  OfflineBrokerDocumentStates(this.party, this.state, {this.now});
  final AgreementParty party;
  final String state;
  final DateTime Function()? now;
  final changes = StreamController<List<DocumentRequestInfo>>.broadcast();
  List<DocumentRequestInfo>? current;

  List<DocumentRequestInfo> _seed() {
    final timestamp = (now?.call() ?? DateTime.now()).millisecondsSinceEpoch;
    return [
      if (state != 'empty')
        for (final paper in [
          ...RequestedPaper.individual,
          if (party.id.startsWith('tenant')) RequestedPaper.linkedin,
        ])
          DocumentRequestInfo({
            'requestId': 'offline-${party.id}-${paper.name}',
            'partyId': party.id,
            'type': paper.name,
            'version': 1,
            'partyName': party.name,
            'phone': party.phone,
            'brokerName': 'Rahul',
            'address': 'Phoenix Towers 402',
            'role': party.id.startsWith('owner') ? 'owner' : 'tenant',
            'issuedAtMs': timestamp - 3600000,
            'sharedAtMs':
                timestamp -
                (state == 'sent'
                    ? 5000
                    : state == 'cooldown'
                    ? 15000
                    : 120000),
            'channel': state == 'sms'
                ? 'SMS'
                : state == 'email'
                ? 'Email'
                : 'WhatsApp',
            'shareCount': state == 'cooldown' && paper == RequestedPaper.aadhaar
                ? 2
                : 1,
            'expiresAtMs': state == 'problems' && paper == RequestedPaper.pan
                ? timestamp - 1
                : timestamp + 86400000,
            'status':
                state == 'complete' ||
                    state == 'partial' && paper == RequestedPaper.aadhaar ||
                    state == 'problems' && paper == RequestedPaper.bank
                ? 'added'
                : state == 'seen' && paper == RequestedPaper.aadhaar
                ? 'seen'
                : state == 'problems' && paper == RequestedPaper.aadhaar
                ? 'unclear'
                : 'shared',
            if (state == 'deleted' && paper == RequestedPaper.aadhaar)
              'closedPapers': {
                'aadhaar': {'action': 'paper_deleted', 'atMs': timestamp},
              },
            'submission': {
              'uploadId': 'offline-upload-${paper.name}',
              'atMs': timestamp - 60000,
              'addedByName': party.name,
              'verified': false,
              if (paper == RequestedPaper.linkedin)
                'linkedInDetails': {
                  'url': 'https://www.linkedin.com/in/priya-sharma',
                  'skipped': false,
                },
              'files': {
                for (final kind in paper.slots)
                  kind.name: {
                    'path': 'offline-fixture',
                    'name': 'TEST-DOCUMENT-NOT-VALID.pdf',
                  },
              },
            },
          }),
    ];
  }

  @override
  Stream<List<DocumentRequestInfo>> watch(String draftId, int revision) async* {
    yield current ??= _seed();
    if (state.startsWith('live-')) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      current = [
        for (final record in current!)
          if (state == 'live-complete' ||
              record.paper == RequestedPaper.aadhaar)
            DocumentRequestInfo({...record.data, 'status': 'added'})
          else
            record,
      ];
      yield current!;
    }
    yield* changes.stream;
  }

  @override
  Future<void> record(
    DocumentRequestInfo info,
    String action, {
    String? reason,
    String? channel,
    RequestedPaper? paper,
    Map<String, dynamic>? linkedInDetails,
  }) async {
    current = [
      for (final record in current ?? _seed())
        if (record.id == info.id)
          DocumentRequestInfo({
            ...record.data,
            if (action == 'unclear') 'status': 'unclear',
            if (paper != null)
              'closedPapers': {
                ...record.closedPapers,
                paper.name: {
                  'action': action,
                  'atMs':
                      (now?.call() ?? DateTime.now()).millisecondsSinceEpoch,
                },
              },
          })
        else
          record,
    ];
    changes.add(current!);
  }

  @override
  Future<DocumentFile> readFile(Map<String, dynamic> file) async =>
      DocumentFile(
        name: 'TEST-DOCUMENT-NOT-VALID.pdf',
        bytes: testDocumentPdf(),
      );
}
