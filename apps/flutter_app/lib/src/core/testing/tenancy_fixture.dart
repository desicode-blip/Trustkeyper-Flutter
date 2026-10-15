import 'dart:async';

import '../../features/broker/data/private_documents.dart';
import '../../features/inspections/inspection_gateway.dart';
import '../../features/tenancy/tenancy_gateway.dart';
import 'inspection_fixture.dart';

class OfflineTenancyFixture implements InspectionGateway {
  OfflineTenancyFixture({
    this.role = 'broker',
    this.ready = false,
    this.active = false,
  }) {
    data = {
      'agreementId': 'offline-home',
      'propertyId': 'offline-flat',
      'address': 'TEST Phoenix Towers 402',
      'revision': 1,
      'role': role,
      'version': 0,
      'phase': active ? 'active' : 'preparing',
      'startDate': '2026-10-01',
      'endDate': '2027-08-31',
      'today': '2026-10-10',
      'canEdit': role == 'broker',
      'moneyComplete': ready,
      'meterComplete': ready,
      'payments': [
        {
          'personId': 'priya',
          'name': 'TEST Priya Sharma',
          'paid': ready,
          'amountPaise': 3300000,
          'month': '2026-10',
        },
        {
          'personId': 'rahul',
          'name': 'TEST Rahul Verma',
          'paid': ready,
          'amountPaise': 3300000,
          'month': '2026-10',
        },
      ],
      'rooms': [
        for (final room in roomItems.keys)
          {
            'room': room,
            'items': [
              for (final title in roomItems[room]!)
                {
                  'id': '$room-$title',
                  'title': title,
                  'optional': false,
                  'checkId': ready
                      ? 'offline-${title.replaceAll(' ', '-')}'
                      : null,
                },
            ],
          },
      ],
      'photoComplete': ready,
      'roomConfiguration': {'bedrooms': 2, 'washrooms': 2, 'balcony': true},
      'meters': ready
          ? {
              'noGas': true,
              'electricity': {
                'reading': '14582',
                'checkId': 'offline-electricity',
              },
              'water': {'reading': '3210', 'checkId': 'offline-water'},
            }
          : null,
      'keys': role == 'tenant' || active
          ? {'mainDoor': 2, 'bedrooms': 2, 'letterBox': 1, 'parkingCard': 1}
          : null,
      'challenge': role == 'tenant'
          ? {
              'id': 'offline-challenge',
              'personId': 'priya',
              'name': 'TEST Priya Sharma',
            }
          : null,
      'canIssueCode': role == 'tenant' && !active,
      'canHandOver': role == 'broker' && ready && !active,
      'myPersonId': role == 'tenant' ? 'priya' : null,
      'earliestMoveOutDate': '2026-11-10',
      'lockInEnds': '2027-04-01',
      'noticeMonths': 1,
      'nextInspectionDate': active ? '2027-01-10' : null,
      'rent': [
        {
          'personId': 'priya',
          'uid': 'offline-priya',
          'name': 'TEST Priya Sharma',
          'phone': '+912222222222',
          'month': '2026-11',
          'amountPaise': 1100000,
          'status': 'unpaid',
          'dueDate': '2026-11-05',
          'deadline': '2026-11-05',
          'daysLate': 3,
          'lateFeePaise': 0,
          'followUp': null,
        },
        {
          'personId': 'rahul',
          'uid': 'offline-rahul',
          'name': 'TEST Rahul Verma',
          'phone': '+913333333333',
          'month': '2026-11',
          'amountPaise': 1100000,
          'status': 'paid',
          'daysLate': 0,
          'lateFeePaise': 0,
        },
      ],
    };
  }
  final String role;
  final bool ready;
  final bool active;
  late Map<String, dynamic> data;
  final updates = StreamController<void>.broadcast();
  final imageFixture = OfflineInspectionFixture();
  final photos = <String, DocumentFile>{};
  final operations = <Map<String, dynamic>>[];
  int captured = 0;
  Future<DocumentFile> camera() => imageFixture.camera();

  static const roomItems = {
    'Living room': [
      'Entrance door',
      'Door lock',
      'Walls',
      'Ceiling',
      'Floor',
      'Windows',
      'Lights',
      'Switches',
      'Fans',
      'Living room overview',
    ],
    'Kitchen': [
      'Kitchen overview',
      'Walls',
      'Floor',
      'Countertop',
      'Sink',
      'Sink tap',
      'Under-sink pipes',
      'Cabinets',
      'Chimney',
      'Stove area',
      'Window',
      'Sockets',
    ],
    'Bedroom 1': [
      'Room overview',
      'Door and lock',
      'Walls',
      'Ceiling',
      'Floor',
      'Window',
      'Lights and switches',
      'Wardrobe',
      'Fan',
    ],
    'Bedroom 2': [
      'Room overview',
      'Door and lock',
      'Walls',
      'Ceiling',
      'Floor',
      'Window',
      'Lights and switches',
      'Wardrobe',
    ],
    'Washroom 1': [
      'Room overview',
      'Door and lock',
      'Walls and floor',
      'Wash basin',
      'Taps and shower',
      'Toilet',
      'Drain and pipes',
      'Geyser',
    ],
    'Washroom 2': [
      'Room overview',
      'Door and lock',
      'Walls and floor',
      'Wash basin',
      'Taps and shower',
      'Toilet',
      'Drain and pipes',
    ],
    'Balcony / utility': ['Overview', 'Floor', 'Railing', 'Drain'],
    'Fixtures & fittings': [
      'Main locks',
      'Intercom',
      'Electrical panel',
      'Water connections',
      'Parking access',
      'Other fixtures',
    ],
  };
  @override
  Stream<InspectionList> watch(
    String propertyId,
    String? agreementId, [
    String? role,
  ]) => imageFixture.watch(propertyId, agreementId, role);

  Stream<TenancyRecord> tenancyWatch(String agreementId, String selectedRole) =>
      Stream.multi((controller) {
        controller.add(TenancyRecord(data));
        final subscription = updates.stream.listen(
          (_) => controller.add(TenancyRecord(data)),
        );
        controller.onCancel = subscription.cancel;
      });

  Future<Map<String, dynamic>> record(Map<String, dynamic> input) async {
    operations.add(input);
    final payload = input['payload'] as Map;
    if (input['action'] == 'keys') {
      data['keys'] = Map<String, dynamic>.from(payload['counts'] as Map);
      data['challenge'] = {
        'id': 'offline-challenge',
        'name': 'TEST Priya Sharma',
        'personId': payload['personId'],
      };
    } else if (input['action'] == 'confirm') {
      if (payload['code'] != '654321') {
        return {
          'codeAccepted': false,
          'message': 'That TEST code is not correct.',
        };
      }
      data['phase'] = 'active';
      data['canHandOver'] = false;
      data['challenge'] = null;
      data['nextInspectionDate'] = '2027-01-10';
    } else if (input['action'] == 'meters') {
      if (['electricity', 'water'].any(
        (kind) =>
            (payload[kind] as Map)['checkId'] == null ||
            (payload[kind] as Map)['reading'] == '',
      )) {
        throw StateError('Add meter photos and readings before saving.');
      }
      data['meters'] = payload;
      data['meterComplete'] = true;
    } else if (input['action'] == 'notice') {
      data['notice'] = payload;
    } else if (input['action'] == 'rooms') {
      data['roomConfiguration'] = payload;
    } else if ((input['action'] as String).startsWith('rent_')) {
      final row = (data['rent'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((row) => row['personId'] == payload['personId']);
      final followUp = Map<String, dynamic>.from(row['followUp'] as Map? ?? {});
      final event = {'date': payload['date'], 'note': payload['note']};
      if (input['action'] == 'rent_extension') {
        followUp['extension'] = event;
        row['deadline'] = payload['date'];
        row['daysLate'] = 0;
      } else if (input['action'] == 'rent_promise') {
        followUp['promise'] = event;
      } else {
        followUp['lastCall'] = event;
      }
      row['followUp'] = followUp;
    }
    data['version'] = (data['version'] as int) + 1;
    updates.add(null);
    return {'saved': true, 'phase': data['phase']};
  }

  Future<Map<String, dynamic>> issueCode(Map<String, dynamic> input) async => {
    'code': '654321',
    'expiresAtMs': DateTime.now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch,
    'delivery': 'offline_test_screen',
    'challengeId': 'offline-challenge',
  };
  Future<void> refresh(String agreementId, String role) async {
    updates.add(null);
  }

  @override
  Future<Map<String, dynamic>> begin(Map<String, dynamic> input) async => {
    'checkId': 'offline-photo-${++captured}',
    'startedAtMs': DateTime(2026, 10, 10, 12, 20).millisecondsSinceEpoch,
    'actorName': 'TEST Rahul Sharma',
    'actorRole': 'Broker',
    'request': input,
  };
  @override
  Future<void> save(Map<String, dynamic> grant, DocumentFile file) async {
    photos[grant['checkId'] as String] = file;
    final request = grant['request'] as Map;
    if (request['purpose'] == 'move_in') {
      for (final room in data['rooms'] as List) {
        for (final item in (room as Map)['items'] as List) {
          if ((item as Map)['id'] == request['itemId']) {
            item['checkId'] = grant['checkId'];
          }
        }
      }
    }
    updates.add(null);
  }

  @override
  Future<DocumentFile> photo(String propertyId, String checkId) async =>
      photos[checkId] ?? await camera();
  @override
  Future<void> review(Map<String, dynamic> input) async {}
}

class OfflineTenancyGateway implements TenancyGateway {
  OfflineTenancyGateway(this.fixture);
  final OfflineTenancyFixture fixture;
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
  Future<void> refresh(String agreementId, String role) =>
      fixture.refresh(agreementId, role);
}
