import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/inspection_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/inspections/inspection_screen.dart';
import 'package:trustkeyper/src/features/inspections/inspection_gateway.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';

class DelayedInspectionFixture extends OfflineInspectionFixture {
  final grantResult = Completer<Map<String, dynamic>>();
  final photoResult = Completer<DocumentFile>();
  final identities = StreamController<InspectionList>.broadcast();
  bool delayPhoto = false;
  int cameraCalls = 0;

  @override
  Stream<InspectionList> watch(
    String propertyId,
    String? agreementId, [
    String? selectedRole,
  ]) => Stream.multi((controller) {
    controller.add(
      InspectionList({
        'canCapture': true,
        'actorRole': 'broker',
        'checks': checks,
      }),
    );
    final subscription = identities.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<Map<String, dynamic>> begin(Map<String, dynamic> input) =>
      grantResult.future;

  @override
  Future<DocumentFile> camera() {
    cameraCalls++;
    return super.camera();
  }

  @override
  Future<DocumentFile> photo(String propertyId, String checkId) =>
      delayPhoto ? photoResult.future : super.photo(propertyId, checkId);
}

void main() {
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
  Future<void> open(
    WidgetTester tester,
    OfflineInspectionFixture fixture, {
    Size size = const Size(440, 956),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(fixture.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: const ValueKey('inspection-capture'),
          child: InspectionScreen(
            propertyId: 'offline-flat',
            gateway: fixture,
            camera: fixture.camera,
            offline: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!Platform.environment.containsKey('TRUSTKEYPER_CAPTURE_UI')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('inspection-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '../../output/ui-audit/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'photo history uses real status, dates and actors; room choices match the approved grid',
    (tester) async {
      final fixture = OfflineInspectionFixture();
      await open(tester, fixture);
      expect(find.text('Kitchen tap leak'), findsOneWidget);
      expect(find.text('Needs repair'), findsOneWidget);
      await capture(tester, 'build24-photo-checks-timeline');
      await tester.tap(find.text('Take photos now'));
      await tester.pumpAndSettle();
      expect(find.text('Which room?'), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
      await tester.tap(find.text('Kitchen'));
      await tester.pumpAndSettle();
      await capture(tester, 'build24-photo-checks-rooms');
      await tester.tap(find.text('Open camera'));
      await tester.pumpAndSettle();
      expect(find.text('Kitchen · item'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fixture.saved, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'admin can see evidence but cannot masquerade as a camera uploader',
    (tester) async {
      final fixture = OfflineInspectionFixture(role: 'admin');
      await open(tester, fixture);
      expect(find.text('Take photos now'), findsNothing);
      expect(find.text('All good'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'small phone room selection remains scrollable and camera action remains accessible',
    (tester) async {
      final fixture = OfflineInspectionFixture();
      await open(tester, fixture, size: const Size(360, 720));
      await tester.tap(find.text('Take photos now'));
      await tester.pumpAndSettle();
      expect(find.text('Open camera'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'camera review and save add an actual pending record, not an approved placeholder',
    (tester) async {
      final fixture = OfflineInspectionFixture();
      await open(tester, fixture);
      await tester.tap(find.text('Take photos now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kitchen'));
      await tester.tap(find.text('Open camera'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Sink tap');
      await tester.tap(find.widgetWithText(TextButton, 'Open camera'));
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 20 && find.text('Upload private copy').evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.text('Check your photo'), findsOneWidget);
      expect(fixture.saved, 0);
      await tester.tap(find.text('Upload private copy'));
      await tester.pumpAndSettle();
      expect(fixture.saved, 1);
      expect(find.text('Sink tap'), findsOneWidget);
      expect(find.text('Awaiting review'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'camera evidence is stamped as PNG with a server-started actor and time',
    (tester) async {
      final fixture = OfflineInspectionFixture();
      final grant = await fixture.begin({});
      final file = await tester.runAsync(
        () async => stampInspectionPhoto(await fixture.camera(), grant),
      );
      expect(file!.contentType, 'image/png');
      expect(file.bytes.length, greaterThan(100));
      file.validate();
      await fixture.updates.close();
    },
  );
  testWidgets(
    'a revoked session discards a late grant and never opens the camera',
    (tester) async {
      final fixture = DelayedInspectionFixture();
      addTearDown(fixture.identities.close);
      await open(tester, fixture);
      await tester.tap(find.text('Take photos now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open camera'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Sink tap');
      await tester.tap(find.widgetWithText(TextButton, 'Open camera'));
      await tester.pump();
      fixture.identities.addError(StateError('Access revoked'));
      await tester.pump();
      fixture.identities.add(
        InspectionList({
          'canCapture': true,
          'actorRole': 'broker',
          'checks': [],
        }),
      );
      fixture.grantResult.complete({
        'startedAtMs': 1,
        'actorName': 'Old user',
        'actorRole': 'broker',
      });
      await tester.pumpAndSettle();
      expect(fixture.cameraCalls, 0);
      expect(fixture.saved, 0);
      expect(find.text('Check your photo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a late private photo is not shown after revoked access recovers',
    (tester) async {
      final fixture = DelayedInspectionFixture()..delayPhoto = true;
      addTearDown(fixture.identities.close);
      await open(tester, fixture);
      await tester.tap(find.text('Kitchen tap leak'));
      await tester.pump();
      fixture.identities.addError(StateError('Access revoked'));
      await tester.pump();
      fixture.identities.add(
        InspectionList({
          'canCapture': true,
          'actorRole': 'broker',
          'checks': [],
        }),
      );
      fixture.photoResult.complete(await fixture.camera());
      await tester.pumpAndSettle();
      expect(find.text('TEST camera photo.png'), findsNothing);
      expect(find.text('Kitchen · Kitchen tap leak'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
