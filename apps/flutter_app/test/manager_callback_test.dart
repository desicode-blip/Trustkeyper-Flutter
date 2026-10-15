import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/callback_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/owner/presentation/manager_callback_screen.dart';

class InterruptedCallbackFixture extends OfflineCallbackFixture {
  final inputs = <Map<String, dynamic>>[];
  bool fail = true;
  @override
  Future<Map<String, dynamic>> record(Map<String, dynamic> input) async {
    inputs.add(Map<String, dynamic>.from(input));
    if (fail) throw StateError('Connection lost after save.');
    return super.record(input);
  }
}

Future<void> openCallback(
  WidgetTester tester,
  OfflineCallbackFixture fixture, {
  Future<bool> Function(Uri)? contactLauncher,
}) async {
  tester.view.physicalSize = const Size(363, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ManagerCallbackScreen(
        gateway: fixture,
        offline: contactLauncher == null,
        contactLauncher: contactLauncher,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> click(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final throwsError in [false, true]) {
    testWidgets(
      'unavailable contact app displays a recoverable error (throws=$throwsError)',
      (tester) async {
        final fixture = OfflineCallbackFixture(status: 'confirmed');
        await openCallback(
          tester,
          fixture,
          contactLauncher: (uri) async {
            expect(uri.scheme, 'tel');
            if (throwsError) throw StateError('No dialler available');
            return false;
          },
        );
        await click(tester, 'Call manager');
        expect(
          find.text('Could not open call. Use the contact shown below.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'rescheduling retains the actual topic and available requested window',
    (tester) async {
      final fixture = OfflineCallbackFixture(status: 'confirmed');
      (fixture.state['callback'] as Map)['topic'] = 'tenant';
      (fixture.state['callback'] as Map)['window'] = 'tomorrow_evening';
      await openCallback(tester, fixture);
      await click(tester, 'Change time');
      await click(tester, 'Call me');
      expect((fixture.state['callback'] as Map)['topic'], 'tenant');
      expect((fixture.state['callback'] as Map)['window'], 'tomorrow_evening');
      expect((fixture.state['callback'] as Map)['status'], 'requested');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editable topic and slot create a verified-phone request, not a confirmed appointment',
    (tester) async {
      final fixture = OfflineCallbackFixture();
      await openCallback(tester, fixture);
      await click(tester, 'Plan and fee');
      await click(tester, 'In 10 minutes');
      await click(tester, 'Call me');
      expect(fixture.lastAction, 'request');
      expect((fixture.state['callback'] as Map)['topic'], 'plan');
      expect((fixture.state['callback'] as Map)['window'], 'soon');
      expect((fixture.state['callback'] as Map)['status'], 'requested');
      expect(find.text('Call requested'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('actual confirmed manager, slot and reschedule remain separate', (
    tester,
  ) async {
    final fixture = OfflineCallbackFixture(status: 'confirmed');
    await openCallback(tester, fixture);
    expect(find.text('TEST Anita will call you'), findsOneWidget);
    expect(find.textContaining('11 Oct, 9:30 AM IST'), findsOneWidget);
    await click(tester, 'Change time');
    await click(tester, 'Tomorrow morning');
    await click(tester, 'Call me');
    expect((fixture.state['callback'] as Map)['status'], 'requested');
    expect((fixture.state['callback'] as Map)['scheduledAtMs'], isNull);
  });
  testWidgets('missed call records outcome and can request a new time', (
    tester,
  ) async {
    final fixture = OfflineCallbackFixture(status: 'missed');
    await openCallback(tester, fixture);
    expect(find.textContaining('TEST no answer'), findsOneWidget);
    await click(tester, 'Tomorrow morning');
    await click(tester, 'Call me again');
    expect((fixture.state['callback'] as Map)['status'], 'requested');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'changed backend version blocks edited form until explicit reload',
    (tester) async {
      final fixture = OfflineCallbackFixture();
      await openCallback(tester, fixture);
      await click(tester, 'Plan and fee');
      fixture.state['version'] = 2;
      fixture.changes.add(null);
      await tester.pumpAndSettle();
      expect(
        find.text('This request changed. Reload before saving.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Call me'));
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Call me'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is FilledButton,
                ),
              ),
            )
            .onPressed,
        isNull,
      );
      await click(tester, 'Reload changed request');
      await click(tester, 'Call me');
      expect(fixture.lastAction, 'request');
    },
  );
  testWidgets(
    'lost response retries identical operation without silently changing the form',
    (tester) async {
      final fixture = InterruptedCallbackFixture();
      await openCallback(tester, fixture);
      await click(tester, 'Call me');
      expect(find.text('Connection lost after save.'), findsOneWidget);
      fixture.fail = false;
      await click(tester, 'Retry same request');
      expect(fixture.inputs.length, 2);
      expect(fixture.inputs.first, fixture.inputs.last);
      expect(find.text('Call requested'), findsOneWidget);
    },
  );
  testWidgets('revoked login removes manager contact and the verified phone', (
    tester,
  ) async {
    final fixture = OfflineCallbackFixture();
    await openCallback(tester, fixture);
    fixture.changes.addError(
      StateError('Your login changed. Reopen this page.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('TEST Anita'), findsNothing);
    expect(find.text('+919000000001'), findsNothing);
    expect(find.text('Your login changed. Reopen this page.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
