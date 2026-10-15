import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/auth/data/recipient_web_persistence.dart';

class RecipientPersistenceAuth extends Fake implements FirebaseAuth {
  final selected = <Persistence>[];
  final failures = <FirebaseAuthException>[];
  int signOuts = 0;

  @override
  Future<void> setPersistence(Persistence persistence) async {
    selected.add(persistence);
    if (failures.isNotEmpty) throw failures.removeAt(0);
  }

  @override
  Future<void> signOut() async => signOuts++;
}

void main() {
  test(
    'temporary browser storage always selects non-persistent recipient auth',
    () async {
      final auth = RecipientPersistenceAuth();
      await configureRecipientWebPersistence(auth, transientStorage: true);
      expect(auth.selected, [Persistence.NONE]);
      expect(auth.signOuts, 0);
    },
  );
  test('normal recipient browsing keeps tab-only authentication', () async {
    final auth = RecipientPersistenceAuth();
    await configureRecipientWebPersistence(auth);
    expect(auth.selected, [Persistence.SESSION]);
    expect(auth.signOuts, 0);
  });

  for (final code in [
    'web-storage-unsupported',
    'operation-not-supported-in-this-environment',
  ]) {
    test(
      'unavailable browser storage uses memory, not a persistent login: $code',
      () async {
        final auth = RecipientPersistenceAuth()
          ..failures.add(FirebaseAuthException(code: code));
        await configureRecipientWebPersistence(auth);
        expect(auth.selected, [Persistence.SESSION, Persistence.NONE]);
        expect(auth.signOuts, 0);
      },
    );
  }

  test(
    'network and permission failures are not hidden by persistence fallback',
    () async {
      final failure = FirebaseAuthException(code: 'network-request-failed');
      final auth = RecipientPersistenceAuth()..failures.add(failure);
      await expectLater(
        configureRecipientWebPersistence(auth),
        throwsA(same(failure)),
      );
      expect(auth.selected, [Persistence.SESSION]);
    },
  );

  test(
    'memory-session failure does not report successful verification setup',
    () async {
      final failure = FirebaseAuthException(code: 'internal-error');
      final auth = RecipientPersistenceAuth()
        ..failures.addAll([
          FirebaseAuthException(code: 'web-storage-unsupported'),
          failure,
        ]);
      await expectLater(
        configureRecipientWebPersistence(auth),
        throwsA(same(failure)),
      );
      expect(auth.selected, [Persistence.SESSION, Persistence.NONE]);
    },
  );
}
