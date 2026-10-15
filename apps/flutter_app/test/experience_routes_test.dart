import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/experiences/data/experience_catalog.dart';
import 'package:trustkeyper/src/features/experiences/data/implemented_experiences.dart';
import 'package:trustkeyper/src/features/experiences/presentation/experience_hub_screen.dart';
import 'package:trustkeyper/src/features/journeys/presentation/guided_journey_screen.dart';

void main() {
  test(
    'working entries use actual routes and do not claim missing workflows',
    () {
      for (final entry in implementedExperiences.entries) {
        expect(ExperienceCatalog.byId(entry.key)?.archived, false);
        expect(entry.value, isNotEmpty);
        for (final target in entry.value) {
          expect(target.label, isNotEmpty);
          expect(target.route.startsWith('/experience'), false);
        }
      }
      expect(implementedExperiences['owner-self-onboarding']!.single.route, '/owner/onboarding');
      expect(implementedExperiences['owner-links-documents'], isNull);
      expect(implementedExperiences['archive-review-options'], isNull);
    },
  );

  testWidgets(
    'move-out journey opens a chosen real role entry instead of a static preview',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/experience/move-out',
        routes: [
          GoRoute(
            path: '/experience/move-out',
            builder: (_, state) =>
                const ExperienceFlowScreen(experienceId: 'move-out'),
          ),
          for (final entry in implementedExperiences['move-out']!)
            GoRoute(
              path: entry.route,
              builder: (_, state) =>
                  Scaffold(body: Text('Actual ${state.uri.path}')),
            ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GuidedJourneyScreen), findsNothing);
      expect(find.text('Broker move-out'), findsOneWidget);
      await tester.tap(find.text('Tenant move-out'));
      await tester.pumpAndSettle();
      expect(find.text('Actual /tenant/move-out'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
