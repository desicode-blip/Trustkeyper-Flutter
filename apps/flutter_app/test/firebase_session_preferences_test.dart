import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/auth/data/firebase_session_preferences.dart';

class SessionAuthFake extends Fake implements FirebaseAuth {
  final persistence = <Persistence>[];
  int signOuts = 0;

  @override
  Future<void> setPersistence(Persistence selected) async {
    persistence.add(selected);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
  }
}

void main() {
  test('native unchecked login signs out on next cold start', () async {
    final auth = SessionAuthFake();
    bool? remembered;
    final policy = FirebaseSessionPreferences(
      auth: auth,
      isWeb: false,
      readRemembered: () async => remembered,
      writeRemembered: (selected) async => remembered = selected,
    );
    await policy.configure(keepLoggedIn: false);
    expect(remembered, false);
    await policy.restoreAtStartup();
    expect(auth.signOuts, 1);
    expect(auth.persistence, isEmpty);
  });

  test('native upgrades and remembered logins retain their session', () async {
    final auth = SessionAuthFake();
    bool? remembered;
    final policy = FirebaseSessionPreferences(
      auth: auth,
      isWeb: false,
      readRemembered: () async => remembered,
      writeRemembered: (selected) async => remembered = selected,
    );
    await policy.restoreAtStartup();
    await policy.configure(keepLoggedIn: true);
    await policy.restoreAtStartup();
    expect(auth.signOuts, 0);
    expect(remembered, true);
  });

  test(
    'web checkbox selects Firebase persistence without clearing reloads',
    () async {
      final auth = SessionAuthFake();
      final policy = FirebaseSessionPreferences(
        auth: auth,
        isWeb: true,
        readRemembered: () => throw StateError('Web uses Firebase persistence'),
        writeRemembered: (_) =>
            throw StateError('Web uses Firebase persistence'),
      );
      await policy.configure(keepLoggedIn: false);
      await policy.restoreAtStartup();
      await policy.configure(keepLoggedIn: true);
      expect(auth.persistence, [Persistence.SESSION, Persistence.LOCAL]);
      expect(auth.signOuts, 0);
    },
  );

  test(
    'native preference failure is not reported as successful configuration',
    () async {
      final policy = FirebaseSessionPreferences(
        auth: SessionAuthFake(),
        isWeb: false,
        writeRemembered: (_) async => throw StateError('Storage unavailable'),
      );
      await expectLater(
        policy.configure(keepLoggedIn: false),
        throwsStateError,
      );
    },
  );
}
