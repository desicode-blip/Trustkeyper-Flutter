import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:trustkeyper/src/features/auth/data/firebase_auth_service.dart';
import 'package:trustkeyper/src/features/auth/presentation/auth_screens.dart';

class SplashAuthFake extends Fake implements FirebaseAuthService {
  int checks = 0;
  bool failFirst = false;

  @override
  Future<String> landingRoute() async {
    checks++;
    if (failFirst && checks == 1) throw StateError('Network unavailable');
    return '/login';
  }
}

void main() {
  for (final failFirst in [true, false]) {
    testWidgets(
      'splash can recover its login check (initial failure=$failFirst)',
      (tester) async {
        final auth = SplashAuthFake()..failFirst = failFirst;
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, state) => SplashScreen(authService: auth),
            ),
            GoRoute(
              path: '/login',
              builder: (_, state) =>
                  const Scaffold(body: Text('Recovered login')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pump(const Duration(milliseconds: 2500));
        await tester.pump();
        if (failFirst) {
          expect(
            find.textContaining('Could not check your login'),
            findsOneWidget,
          );
          await tester.tap(find.text('Try again'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Recovered login'), findsOneWidget);
        expect(auth.checks, failFirst ? 2 : 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
