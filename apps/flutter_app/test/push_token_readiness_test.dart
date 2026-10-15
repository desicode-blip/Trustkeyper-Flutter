import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/broker/data/push_token_readiness.dart';

void main() {
  test('Android requests the normal token without asking for APNs', () async {
    final token = await readyMessagingToken(
      requiresApns: false,
      readApnsToken: () async => throw StateError('APNs must not run'),
      readMessagingToken: () async => 'android-token',
      isActive: () => true,
    );
    expect(token, 'android-token');
  });

  test('iOS waits for APNs before asking for the normal FCM token', () async {
    var reads = 0;
    var pauses = 0;
    final token = await readyMessagingToken(
      requiresApns: true,
      readApnsToken: () async => ++reads == 3 ? 'apns-token' : null,
      readMessagingToken: () async {
        expect(reads, 3);
        return 'ios-token';
      },
      isActive: () => true,
      wait: (_) async => pauses++,
    );
    expect(token, 'ios-token');
    expect(pauses, 2);
  });

  test(
    'missing APNs is bounded and never causes an invalid FCM request',
    () async {
      var reads = 0;
      final token = await readyMessagingToken(
        requiresApns: true,
        attempts: 3,
        readApnsToken: () async {
          reads++;
          return null;
        },
        readMessagingToken: () async => throw StateError('APNs not ready'),
        isActive: () => true,
        wait: (_) async {},
      );
      expect(token, isNull);
      expect(reads, 3);
    },
  );

  test('logging out during the wait prevents token lookup', () async {
    var active = true;
    final token = await readyMessagingToken(
      requiresApns: true,
      readApnsToken: () async => null,
      readMessagingToken: () async => throw StateError('Session changed'),
      isActive: () => active,
      wait: (_) async => active = false,
    );
    expect(token, isNull);
  });

  test('an already stopped session never calls the provider', () async {
    final token = await readyMessagingToken(
      requiresApns: true,
      readApnsToken: () async => throw StateError('Session stopped'),
      readMessagingToken: () async => throw StateError('Session stopped'),
      isActive: () => false,
    );
    expect(token, isNull);
  });

  test('a late token cannot cross an account change', () async {
    var active = true;
    final token = await readyMessagingToken(
      requiresApns: false,
      readApnsToken: () async => null,
      readMessagingToken: () async {
        active = false;
        return 'old-user-token';
      },
      isActive: () => active,
    );
    expect(token, isNull);
  });
}
