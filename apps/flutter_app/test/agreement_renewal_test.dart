import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/renewal_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_renewals.dart';
import 'package:trustkeyper/src/features/broker/presentation/agreement_renewal_screen.dart';

class ControlledRenewalGateway implements AgreementRenewalGateway {
  final fixture = OfflineRenewalGateway();
  final updates = StreamController<List<RenewalSource>>.broadcast();
  final response = Completer<Map<String, dynamic>>();
  final operations = <String>[];
  bool failFirst = false;
  @override
  Stream<List<RenewalSource>> watch() => Stream.multi((controller) {
    controller.add([fixture.source]);
    final subscription = updates.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = subscription.cancel;
  });
  @override
  Future<Map<String, dynamic>> create(
    RenewalSource source,
    String operationId,
  ) async {
    operations.add(operationId);
    if (failFirst && operations.length == 1) {
      throw StateError('Temporary connection error');
    }
    return response.future;
  }
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final weight in [400, 500, 600, 700]) {
      font.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    final fallback = FontLoader('GeneralSans');
    for (final weight in ['Regular', 'Medium', 'Semibold', 'Bold']) {
      fallback.addFont(rootBundle.load('assets/fonts/GeneralSans-$weight.otf'));
    }
    await fallback.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  Future<void> open(
    WidgetTester tester,
    AgreementRenewalGateway gateway, {
    void Function(String)? onDraft,
    Size size = const Size(440, 956),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: const ValueKey('renewal-capture'),
          child: AgreementRenewalScreen(
            gateway: gateway,
            now: DateTime(2026, 10, 10),
            onDraft: onDraft,
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
      find.byKey(const ValueKey('renewal-capture')),
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
    'saved signed agreement opens actual reviewed terms and creates a separate draft',
    (tester) async {
      AgreementDraft? saved;
      String? opened;
      final gateway = OfflineRenewalGateway(
        saveDraft: (value) => saved = value,
      );
      await open(tester, gateway, onDraft: (id) => opened = id);
      expect(find.text('Already ended'), findsOneWidget);
      expect(find.textContaining('Ended 10 days ago'), findsOneWidget);
      await capture(tester, 'build25-renewal-picker');
      await tester.tap(find.text(gateway.source.address));
      await tester.pumpAndSettle();
      expect(find.text('1 Oct 2026'), findsOneWidget);
      expect(find.text('₹22,000'), findsOneWidget);
      expect(
        find.textContaining('Nothing is carried over as verified or paid.'),
        findsOneWidget,
      );
      await capture(tester, 'build25-renewal-review');
      await tester.tap(find.text('Yes, make new agreement'));
      await tester.pumpAndSettle();
      expect(opened, 'offline-renewal');
      expect(saved?.renewalSourceId, gateway.source.id);
      expect(saved?.startDate, DateTime(2026, 10, 1));
      expect(gateway.source.end, DateTime(2026, 9, 30));
    },
  );
  testWidgets(
    'search excludes unrelated names and compact layout has no overflow',
    (tester) async {
      await open(tester, OfflineRenewalGateway(), size: const Size(360, 720));
      await tester.enterText(find.byType(TextField), 'not-a-home');
      await tester.pump();
      expect(find.text('No agreements match this search.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Priya');
      await tester.pump();
      expect(find.text('TEST Phoenix Towers 402'), findsOneWidget);
      await tester.tap(find.text('TEST Phoenix Towers 402'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Yes, make new agreement'), findsOneWidget);
    },
  );
  testWidgets(
    'renewal review preserves paise rather than rounding saved terms',
    (tester) async {
      final gateway = OfflineRenewalGateway();
      gateway.source.data['monthlyRentPaise'] = 2200001;
      gateway.source.data['securityDepositPaise'] = 4400019;
      await open(tester, gateway);
      await tester.tap(find.text(gateway.source.address));
      await tester.pumpAndSettle();
      expect(find.text('₹22,000.01'), findsOneWidget);
      expect(find.text('₹44,000.19'), findsOneWidget);
    },
  );
  testWidgets(
    'a failed response retries the same operation rather than duplicating a renewal',
    (tester) async {
      final gateway = ControlledRenewalGateway()..failFirst = true;
      addTearDown(gateway.updates.close);
      await open(tester, gateway, onDraft: (_) {});
      await tester.tap(find.text(gateway.fixture.source.address));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, make new agreement'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Retry without leaving this page'),
        findsOneWidget,
      );
      gateway.response.complete({'agreementId': 'renewed', 'status': 'draft'});
      await tester.tap(find.text('Yes, make new agreement'));
      await tester.pumpAndSettle();
      expect(gateway.operations.length, 2);
      expect(gateway.operations[0], gateway.operations[1]);
    },
  );
  testWidgets(
    'revoked access clears private terms and ignores a late saved result',
    (tester) async {
      final gateway = ControlledRenewalGateway();
      addTearDown(gateway.updates.close);
      String? opened;
      await open(tester, gateway, onDraft: (id) => opened = id);
      await tester.tap(find.text(gateway.fixture.source.address));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, make new agreement'));
      await tester.pump();
      gateway.updates.addError(StateError('Your account is paused.'));
      await tester.pumpAndSettle();
      expect(find.text('TEST Rajesh Kumar'), findsNothing);
      gateway.response.complete({
        'agreementId': 'late-renewal',
        'status': 'draft',
      });
      await tester.pumpAndSettle();
      expect(opened, isNull);
    },
  );
  testWidgets(
    'remote source changes invalidate the selection before a late response',
    (tester) async {
      final gateway = ControlledRenewalGateway();
      addTearDown(gateway.updates.close);
      String? opened;
      await open(tester, gateway, onDraft: (id) => opened = id);
      await tester.tap(find.text(gateway.fixture.source.address));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, make new agreement'));
      await tester.pump();
      gateway.updates.add([]);
      await tester.pumpAndSettle();
      expect(find.text('Nothing to renew yet'), findsOneWidget);
      gateway.response.complete({
        'agreementId': 'late-renewal',
        'status': 'draft',
      });
      await tester.pumpAndSettle();
      expect(opened, isNull);
    },
  );
  test(
    'draft serialization retains the immutable source link without claiming source document evidence',
    () {
      final draft = AgreementDraft.fromMap('renewed', {
        ...OfflineRenewalGateway().source.data,
        'renewalSourceId': 'source',
      });
      expect(draft.toMap()['renewalSourceId'], 'source');
      expect(draft.toMap()['agreementCopy'], isNull);
      expect(
        RenewalSource.available({
          ...OfflineRenewalGateway().source.data,
          'status': 'draft',
        }, 'ui-test-broker'),
        isFalse,
      );
    },
  );
}
