import 'dart:async';
import 'dart:convert';

import '../../features/broker/data/private_documents.dart';
import '../../features/inspections/inspection_gateway.dart';
import '../../features/tenancy/tenancy_gateway.dart';
import 'inspection_fixture.dart';
import 'tenancy_fixture.dart';

class OfflineMoveOutFixture implements InspectionGateway {
  OfflineMoveOutFixture({
    this.role = 'broker',
    this.ready = false,
    this.published = false,
    this.disputed = false,
  }) {
    data = {
      'agreementId': 'offline-move-out',
      'propertyId': 'offline-flat',
      'address': 'TEST Phoenix Towers 402',
      'revision': 1,
      'version': 1,
      'role': role,
      'canEdit': role == 'broker',
      'myPersonId': role == 'tenant'
          ? 'priya'
          : role == 'owner'
          ? 'rajesh'
          : null,
      'notice': {
        'date': '2026-10-10',
        'personIds': ['priya', 'rahul'],
      },
      'status': 'notice_received',
      'today': '2026-10-10',
      'booking': null,
      'people': [
        for (final entry in {
          'priya': 'TEST Priya Sharma',
          'rahul': 'TEST Rahul Verma',
        }.entries)
          {
            'personId': entry.key,
            'name': entry.value,
            'depositPaise': 2200000,
            'depositVerified': true,
          },
      ],
      'rooms': [
        for (final room in OfflineTenancyFixture.roomItems.entries)
          {
            'room': room.key,
            'items': [
              for (final title in room.value)
                {
                  'id': '${room.key}-$title',
                  'title': title,
                  'beforeId': 'before-${room.key}-$title',
                  'afterId': ready ? 'after-${room.key}-$title' : null,
                  'comparison': ready
                      ? {
                          'condition':
                              title == 'Walls' && room.key == 'Bedroom 1'
                              ? 'repair'
                              : 'same',
                          'costPaise':
                              title == 'Walls' && room.key == 'Bedroom 1'
                              ? 350000
                              : 0,
                          'note': 'TEST marks and nail holes near bed.',
                        }
                      : null,
                },
            ],
          },
      ],
      'beforeMeters': {
        'noGas': true,
        'electricity': {'reading': '14582'},
        'water': {'reading': '3210'},
      },
      'meters': ready
          ? {
              'noGas': true,
              'electricity': {
                'reading': '14800',
                'checkId': 'offline-meter-electricity',
              },
              'water': {'reading': '3240', 'checkId': 'offline-meter-water'},
            }
          : null,
      'givenKeys': {
        'mainDoor': 2,
        'bedrooms': 2,
        'letterBox': 1,
        'parkingCard': 1,
      },
      'returnedKeys': ready || role == 'tenant'
          ? {'mainDoor': 2, 'bedrooms': 2, 'letterBox': 1, 'parkingCard': 1}
          : null,
      'keysConfirmed': ready,
      'keyChallenge': role == 'tenant' && !ready
          ? {
              'id': 'offline-key-return',
              'name': 'TEST Priya Sharma',
              'personId': 'priya',
            }
          : null,
      'inspectionComplete': ready,
      'handoverComplete': published,
      'report': null,
      'responses': {},
      'decisions': {},
      'ownerApprovals': {},
      'ownersApproved': published && role != 'owner',
      'charges': [],
      'destination': null,
      'rent': [
        for (final person in ['priya', 'rahul'])
          {'personId': person, 'status': 'paid'},
      ],
      'shares': [
        for (final person in ['priya', 'rahul'])
          if (role != 'tenant' || person == 'priya')
            {
              'personId': person,
              'name': person == 'priya'
                  ? 'TEST Priya Sharma'
                  : 'TEST Rahul Verma',
              'depositPaise': 2200000,
              'depositVerified': true,
              'deductionsPaise': 0,
              'heldPaise': published ? 175000 : 0,
              'refundableNowPaise': published && role != 'owner' ? 2025000 : 0,
              'refundStatus': 'not_requested',
            },
      ],
    };
    if (published) {
      data['report'] = {
        'version': 1,
        'lines': [
          {
            'id': 'Bedroom 1-Walls',
            'title': 'Wall paint · marks',
            'room': 'Bedroom 1',
            'amountPaise': 350000,
            'note': 'TEST marks and nail holes near bed.',
            'beforeId': 'before-Bedroom 1-Walls',
            'afterId': 'after-Bedroom 1-Walls',
            'shares': {'priya': 175000, 'rahul': 175000},
          },
        ],
      };
    }
    if (disputed) {
      data['responses'] = {
        'priya': {
          'Bedroom 1-Walls': {
            'status': 'disputed',
            'reason': 'TEST it was like this at move-in.',
          },
        },
      };
    }
  }
  final String role;
  final bool ready;
  final bool published;
  final bool disputed;
  late Map<String, dynamic> data;
  final updates = StreamController<void>.broadcast();
  final imageFixture = OfflineInspectionFixture();
  final files = <String, DocumentFile>{};
  final operations = <Map<String, dynamic>>[];
  int captures = 0;
  Future<DocumentFile> camera() => imageFixture.camera();
  void emit() => updates.add(null);
  Stream<TenancyRecord> tenancyWatch(String agreementId, String selectedRole) =>
      Stream.multi((controller) {
        void send() => controller.add(
          TenancyRecord(jsonDecode(jsonEncode(data)) as Map<String, dynamic>),
        );
        send();
        final subscription = updates.stream.listen((_) => send());
        controller.onCancel = subscription.cancel;
      });
  Future<Map<String, dynamic>> record(Map<String, dynamic> input) async {
    if (input['version'] != data['version']) {
      throw StateError('This move-out changed. Reload first.');
    }
    final payload = Map<String, dynamic>.from(input['payload'] as Map);
    operations.add(jsonDecode(jsonEncode(input)) as Map<String, dynamic>);
    switch (input['action']) {
      case 'book':
        data['booking'] = payload;
      case 'compare':
        if (payload['costPaise'] == null) {
          throw StateError('Enter a valid cost.');
        }
        for (final room in data['rooms'] as List) {
          for (final item in (room as Map)['items'] as List) {
            if ((item as Map)['id'] == payload['itemId']) {
              item['comparison'] = {
                'condition': payload['condition'],
                'costPaise': payload['costPaise'],
                'note': payload['note'],
              };
            }
          }
        }
      case 'meters':
        if (['electricity', 'water'].any(
          (kind) =>
              (payload[kind] as Map)['checkId'] == null ||
              (payload[kind] as Map)['reading'] == '',
        )) {
          throw StateError('Add photos and actual readings.');
        }
        data['meters'] = payload;
      case 'keys':
        data['returnedKeys'] = payload['counts'];
        data['keyChallenge'] = {
          'id': 'offline-key-return',
          'personId': payload['personId'],
          'name': 'TEST Priya Sharma',
        };
      case 'confirm_keys':
        if (payload['code'] != '654321') {
          return {
            'codeAccepted': false,
            'message': 'Incorrect TEST key-return code.',
          };
        }
        data['keysConfirmed'] = true;
        data['keyChallenge'] = null;
      case 'charge':
        (data['charges'] as List).add({
          ...payload,
          'id': 'offline-charge-${operations.length}',
          'room': payload['kind'] == 'key' ? 'Keys' : 'Utilities',
        });
      case 'publish':
        if (data['inspectionComplete'] != true ||
            data['meters'] == null ||
            data['keysConfirmed'] != true) {
          throw StateError('Finish photos, meters and keys first.');
        }
        data['report'] = {
          'version': data['version'],
          'lines': [
            for (final room in data['rooms'] as List)
              for (final item in (room as Map)['items'] as List)
                if ((((item as Map)['comparison'] as Map?)?['costPaise']
                            as int? ??
                        0) >
                    0)
                  {
                    ...Map<String, dynamic>.from(item),
                    'room': room['room'],
                    'amountPaise': (item['comparison'] as Map)['costPaise'],
                    'note': (item['comparison'] as Map)['note'],
                  },
            ...data['charges'] as List,
          ],
        };
      case 'respond':
        final responses = data['responses'] as Map;
        responses['priya'] = {
          ...responses['priya'] as Map? ?? {},
          payload['itemId']: payload,
        };
      case 'owner_approve':
        data['ownersApproved'] = true;
      case 'propose':
        final item = (data['rooms'] as List)
            .expand((room) => (room as Map)['items'] as List)
            .cast<Map>()
            .firstWhere((item) => item['id'] == payload['itemId']);
        data['proposals'] = [
          ...data['proposals'] as List? ?? [],
          {
            ...payload,
            'id': 'offline-proposal',
            'title': item['title'],
            'status': 'pending',
          },
        ];
      case 'review_proposal':
        final proposal = (data['proposals'] as List).cast<Map>().firstWhere(
          (proposal) => proposal['id'] == payload['proposalId'],
        );
        proposal['status'] = payload['decision'] == 'accept'
            ? 'accepted'
            : 'rejected';
        if (payload['decision'] == 'accept') {
          (data['report'] as Map)['version'] = (data['version'] as int) + 1;
          ((data['report'] as Map)['lines'] as List).add({
            'id': proposal['itemId'],
            'title': proposal['title'],
            'room': 'Move-out',
            'note': payload['reason'],
            'amountPaise': payload['amountPaise'],
            'shares': {
              'priya': (payload['amountPaise'] as int) ~/ 2,
              'rahul': (payload['amountPaise'] as int) ~/ 2,
            },
          });
          data['responses'] = {};
          data['decisions'] = {};
          data['ownersApproved'] = false;
        }
      case 'decide':
        (data['decisions'] as Map)[payload['itemId']] = payload;
      case 'destination':
        if ((data['shares'] as List).cast<Map>().any(
          (share) => share['refundStatus'] != 'not_requested',
        )) {
          throw StateError('The queued TEST refund destination is locked.');
        }
        if (payload['method'] == 'bank_review' && payload['inMyName'] != true) {
          throw StateError('Confirm this account is in your name.');
        }
        data['destination'] = {
          'method': payload['method'],
          'maskedAccount': payload['account'] == null
              ? null
              : '•••• ${(payload['account'] as String).substring((payload['account'] as String).length - 4)}',
          'verificationStatus': 'pending_provider',
        };
      case 'refund_request':
        if ((data['proposals'] as List? ?? []).cast<Map>().any(
          (proposal) => proposal['status'] == 'pending',
        )) {
          throw StateError('Review pending owner proposals first.');
        }
        if (data['ownersApproved'] != true ||
            data['handoverComplete'] != true) {
          throw StateError('Complete handover and owner review.');
        }
        for (final share in data['shares'] as List) {
          if ((share as Map)['personId'] == payload['personId']) {
            share['refundStatus'] = 'awaiting_provider';
          }
        }
      case 'complete':
        data['handoverComplete'] = true;
    }
    data['inspectionComplete'] = (data['rooms'] as List).every(
      (room) => ((room as Map)['items'] as List).every(
        (item) => (item as Map)['comparison'] != null,
      ),
    );
    data['version'] = (data['version'] as int) + 1;
    if (data['report'] is Map) {
      data['pendingOwnerReview'] = (data['proposals'] as List? ?? [])
          .cast<Map>()
          .any((proposal) => proposal['status'] == 'pending');
      for (final share in (data['shares'] as List).cast<Map>()) {
        var deductions = 0;
        var held = 0;
        for (final line
            in ((data['report'] as Map)['lines'] as List).cast<Map>()) {
          final decision = (data['decisions'] as Map)[line['id']] as Map?;
          final amount = decision == null
              ? ((line['shares'] as Map?)?[share['personId']] as int? ??
                    (line['amountPaise'] as int) ~/ 2)
              : (decision['amountPaise'] as int) ~/ 2;
          final response =
              ((data['responses'] as Map)[share['personId']]
                      as Map?)?[line['id']]
                  as Map?;
          if (decision != null || response?['status'] == 'agreed') {
            deductions += amount;
          } else {
            held += amount;
          }
        }
        share['deductionsPaise'] = deductions;
        share['heldPaise'] = held;
        share['refundableNowPaise'] =
            data['ownersApproved'] == true && data['pendingOwnerReview'] != true
            ? (share['depositPaise'] as int) - deductions - held
            : 0;
      }
    }
    emit();
    return {'saved': true, 'moneyTransferred': false};
  }

  Future<Map<String, dynamic>> issueCode(Map<String, dynamic> input) async {
    if (input['countsConfirmed'] != true) {
      throw StateError('Confirm returned keys first.');
    }
    return {
      'code': '654321',
      'challengeId': 'offline-key-return',
      'expiresAtMs': DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
    };
  }

  @override
  Stream<InspectionList> watch(
    String propertyId,
    String? agreementId, [
    String? role,
  ]) => imageFixture.watch(propertyId, agreementId, role);
  @override
  Future<Map<String, dynamic>> begin(Map<String, dynamic> input) async => {
    'checkId': 'offline-after-${++captures}',
    'startedAtMs': DateTime.now().millisecondsSinceEpoch,
    'actorName': 'TEST broker',
    'actorRole': role,
    'request': input,
  };
  @override
  Future<void> save(Map<String, dynamic> grant, DocumentFile file) async {
    file.validate();
    files[grant['checkId'] as String] = file;
    final request = grant['request'] as Map;
    if (request['purpose'] == 'move_out') {
      for (final room in data['rooms'] as List) {
        for (final item in (room as Map)['items'] as List) {
          if ((item as Map)['id'] == request['itemId']) {
            item['afterId'] = grant['checkId'];
            item['comparison'] = null;
          }
        }
      }
    }
    data['version'] = (data['version'] as int) + 1;
    emit();
  }

  @override
  Future<DocumentFile> photo(String propertyId, String checkId) async =>
      files[checkId] ?? await camera();
  @override
  Future<void> review(Map<String, dynamic> input) async {}
}

class OfflineMoveOutGateway implements TenancyGateway {
  OfflineMoveOutGateway(this.fixture);
  final OfflineMoveOutFixture fixture;
  @override
  Stream<TenancyRecord> watch(String agreementId, String role) =>
      fixture.tenancyWatch(agreementId, role);
  @override
  Future<Map<String, dynamic>> record(Map<String, dynamic> input) =>
      fixture.record(input);
  @override
  Future<Map<String, dynamic>> issueCode(Map<String, dynamic> input) =>
      fixture.issueCode(input);
  @override
  Future<void> refresh(String agreementId, String role) async => fixture.emit();
}
