import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/participant_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/participants/data/participant_repository.dart';
import 'package:trustkeyper/src/features/participants/data/participant_workspace.dart';
import 'package:trustkeyper/src/features/participants/presentation/participant_workspace_screen.dart';

class FailingIssueWriter implements ParticipantIssueWriter {
  @override
  Future<String> create(IssueInput input) async => throw StateError('Offline');
}

void main() {
  for (final linked in [true, false]) {
    testWidgets(
      'owner agreement deep entry only renders the requested linked record ($linked)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ParticipantWorkspaceScreen(
              repository: OfflineParticipantFixture(),
              role: 'owner',
              identity: OfflineParticipantFixture.owner,
              initialTab: 1,
              agreementId: linked
                  ? OfflineParticipantFixture.agreement.id
                  : 'unlinked-record',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            OfflineParticipantFixture.agreement.text('propertyAddress'),
          ),
          linked ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('repair deep entry opens the actual issue list immediately', (
    tester,
  ) async {
    final fixture = OfflineParticipantFixture();
    await fixture.create(
      IssueInput(
        agreementId: OfflineParticipantFixture.agreement.id,
        category: 'Water',
        description: 'The kitchen tap has been leaking.',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ParticipantWorkspaceScreen(
          repository: fixture,
          role: 'tenant',
          identity: OfflineParticipantFixture.tenant,
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Water problem'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  setUpAll(() async {
    final fonts = FontLoader('Roboto');
    for (final weight in [400, 500, 600, 700]) {
      fonts.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  test(
    'personal shares require unique account linkage; totals are never divided',
    () {
      final identity = OfflineParticipantFixture.tenant;
      expect(
        personalShare(
          OfflineParticipantFixture.agreement,
          identity,
          'rentSharePaise',
        ),
        1100000,
      );
      expect(
        personalShare(
          OfflineParticipantFixture.agreement,
          const ParticipantIdentity(uid: 'stranger', phone: '+919000000002'),
          'rentSharePaise',
        ),
        isNull,
      );
      expect(
        personalShare(
          ParticipantRecord('missing', {
            'participantUids': [identity.uid],
            'monthlyRentPaise': 2200000,
            'tenants': [],
          }),
          identity,
          'rentSharePaise',
        ),
        isNull,
      );
      expect(
        personalShare(
          ParticipantRecord('ambiguous', {
            'participantUids': [identity.uid],
            'tenants': [
              {'uid': identity.uid, 'rentSharePaise': 100},
              {'phone': identity.phone, 'rentSharePaise': 200},
            ],
          }),
          identity,
          'rentSharePaise',
        ),
        isNull,
      );
    },
  );
  test('issue validation rejects incomplete and unknown inputs', () {
    for (final input in [
      const IssueInput(
        agreementId: '',
        category: 'Water',
        description: 'The kitchen tap is leaking.',
      ),
      const IssueInput(
        agreementId: 'home',
        category: 'Fake',
        description: 'The kitchen tap is leaking.',
      ),
      const IssueInput(
        agreementId: 'home',
        category: 'Water',
        description: 'Leak',
      ),
    ]) {
      expect(input.error, isNotNull);
    }
    expect(
      const IssueInput(
        agreementId: 'home',
        category: 'Water',
        description: 'The kitchen tap is leaking.',
      ).error,
      isNull,
    );
  });
  for (final role in ['owner', 'tenant']) {
    for (final width in [440.0, 363.0, 320.0]) {
      testWidgets('$role workspace tabs fit $width px', (tester) async {
        tester.view.physicalSize = Size(width, width == 440 ? 956 : 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = OfflineParticipantFixture();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.3 : 1)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: ParticipantWorkspaceScreen(
                repository: fixture,
                role: role,
                identity: role == 'owner'
                    ? OfflineParticipantFixture.owner
                    : OfflineParticipantFixture.tenant,
                issueWriter: fixture,
                now: DateTime(2026, 10, 9),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(role == 'owner' ? '₹45,350' : '₹11,000'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        if (width == 440 && const bool.fromEnvironment('CAPTURE_UI')) {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '../../output/ui-audit/native/$role-workspace.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        for (final label
            in role == 'owner'
                ? ['Properties', 'Money', 'Issues', 'Profile', 'Home']
                : ['Pay', 'Issues', 'Profile', 'Home']) {
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
  testWidgets('issue form rejects short text then saves and updates the list', (
    tester,
  ) async {
    final fixture = OfflineParticipantFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ParticipantWorkspaceScreen(
          repository: fixture,
          role: 'tenant',
          identity: OfflineParticipantFixture.tenant,
          issueWriter: fixture,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Issues').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tell us a problem'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Leak');
    await tester.scrollUntilVisible(
      find.text('Send'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('10–2000'), findsOneWidget);
    expect(fixture.issues, isEmpty);
    await tester.enterText(
      find.byType(TextField),
      'The kitchen tap has been leaking since yesterday.',
    );
    await tester.ensureVisible(find.text('Send'));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Issue sent'), findsOneWidget);
    expect(fixture.issues.length, 1);
    await tester.tap(find.text('Back to issues'));
    await tester.pumpAndSettle();
    expect(find.text('Water problem'), findsOneWidget);
    await tester.tap(find.text('Water problem'));
    await tester.pumpAndSettle();
    expect(find.textContaining('leaking since yesterday'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'issue categories and Send remain usable with a small screen and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(363, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: ParticipantIssueScreen(
            agreements: [OfflineParticipantFixture.agreement],
            writer: FailingIssueWriter(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Appliance'), findsOneWidget);
      expect(find.text('Door / lock'), findsOneWidget);
      expect(tester.getRect(find.text('Send')).bottom, lessThan(500));
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.textContaining('10–2000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed issue save keeps input and never claims success', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ParticipantIssueScreen(
          agreements: [OfflineParticipantFixture.agreement],
          writer: FailingIssueWriter(),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'The kitchen tap is leaking.',
    );
    await tester.scrollUntilVisible(
      find.text('Send'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Issue sent'), findsNothing);
    expect(find.textContaining('Sending was not confirmed'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'The kitchen tap is leaking.',
    );
  });
}
