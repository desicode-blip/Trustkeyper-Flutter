import 'dart:async';
import '../../features/owner/data/manager_callbacks.dart';

class OfflineCallbackFixture implements ManagerCallbackGateway {
  OfflineCallbackFixture({String status = 'none'}) {
    if (status != 'none') {
      state['callback'] = {
        'status': status,
        'topic': 'property',
        'window': 'tomorrow_morning',
        'requestedFromMs': DateTime.utc(
          2026,
          10,
          11,
          3,
          30,
        ).millisecondsSinceEpoch,
        'scheduledAtMs': DateTime.utc(2026, 10, 11, 4).millisecondsSinceEpoch,
        if (status == 'missed')
          'attemptedAtMs': DateTime.utc(
            2026,
            10,
            10,
            12,
            40,
          ).millisecondsSinceEpoch,
        if (status == 'missed')
          'outcome': 'TEST no answer on the verified phone.',
      };
    }
  }
  final changes = StreamController<void>.broadcast();
  final state = <String, dynamic>{
    'version': 0,
    'phone': '+919000000001',
    'manager': {
      'uid': 'offline-manager',
      'name': 'TEST Anita',
      'phone': '+919000000003',
      'email': 'test@trustkeyper.com',
    },
    'availableWindows': [
      'soon',
      'today_evening',
      'tomorrow_morning',
      'tomorrow_evening',
    ],
    'callback': null,
    'deliveryStatus': 'offline_only',
  };
  String? lastAction;
  final operations = <String, Map<String, dynamic>>{};
  @override
  Stream<Map<String, dynamic>> watch(String? ownerUid) async* {
    yield Map<String, dynamic>.from(state);
    await for (final _ in changes.stream) {
      yield Map<String, dynamic>.from(state);
    }
  }

  @override
  Future<Map<String, dynamic>> record(Map<String, dynamic> input) async {
    final operation = input['operationId'] as String;
    if (operations.containsKey(operation)) return operations[operation]!;
    if (input['version'] != state['version']) {
      throw StateError('This request changed. Reload before saving.');
    }
    final payload = Map<String, dynamic>.from(input['payload'] as Map);
    lastAction = input['action'] as String;
    if (lastAction == 'request') {
      state['callback'] = {
        'status': 'requested',
        'window': payload['window'],
        'topic': payload['topic'],
        'scheduledAtMs': null,
      };
    } else if (lastAction == 'cancel') {
      state['callback'] = {
        ...?state['callback'] as Map<String, dynamic>?,
        'status': 'cancelled',
      };
    } else {
      throw StateError(
        'Only owner callbacks are supported by this offline fixture.',
      );
    }
    state['version'] = (state['version'] as int) + 1;
    final result = Map<String, dynamic>.from(state);
    operations[operation] = result;
    changes.add(null);
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> list() async => [];
  @override
  Future<void> refresh() async {
    changes.add(null);
  }
}
