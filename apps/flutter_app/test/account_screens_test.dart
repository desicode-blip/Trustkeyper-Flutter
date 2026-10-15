import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/account_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/account/data/account_gateway.dart';
import 'package:trustkeyper/src/features/account/presentation/account_restoration_queue.dart';
import 'package:trustkeyper/src/features/account/presentation/account_screens.dart';
import 'package:trustkeyper/src/features/auth/data/firebase_auth_service.dart';
import 'package:trustkeyper/src/features/auth/presentation/approved_auth_widgets.dart';
import 'package:trustkeyper/ui_test_main.dart';
import 'support/approved_fonts.dart';

class TestAccountGateway extends OfflineAccountGateway {
  int requests = 0, verifications = 0, closes = 0, reads = 0;
  bool wrongCode = false,
      failSave = false,
      failRead = false,
      uncertainClose = false;
  Completer<AccountProfileData>? delayed;
  Completer<String>? delayedEmail;
  @override
  Future<AccountProfileData> read() async {
    reads++;
    if (failRead) {
      throw const FirebaseAuthFailure('TEST connection unavailable.');
    }
    return delayed == null ? super.read() : delayed!.future;
  }

  @override
  Future<String> requestEmail(String email) async {
    requests++;
    return delayedEmail == null
        ? super.requestEmail(email)
        : delayedEmail!.future;
  }

  @override
  Future<void> verifyEmail(String email, String challenge, String code) async {
    verifications++;
    if (wrongCode) throw const FirebaseAuthFailure('The code is incorrect.');
    await super.verifyEmail(email, challenge, code);
  }

  @override
  Future<AccountProfileData> save(Map<String, dynamic> details) async {
    if (failSave) throw const FirebaseAuthFailure('TEST save unavailable.');
    return super.save(details);
  }

  @override
  Future<Map<String, dynamic>> close({
    required String reason,
    required String note,
  }) async {
    closes++;
    if (uncertainClose) return {'closed': false};
    return super.close(reason: reason, note: note);
  }
}

class RestorationFixture implements AccountRestorationGateway {
  final finished = <String>[], restored = <String>[];
  final requests = <Map<String, dynamic>>[
    {
      'uid': 'pending',
      'displayName': 'TEST pending',
      'status': 'closing',
      'restoreUntilMs': 0,
    },
    {
      'uid': 'closed',
      'displayName': 'TEST closed',
      'status': 'closed',
      'restoreUntilMs': DateTime.now().millisecondsSinceEpoch + 60000,
    },
    {
      'uid': 'expired',
      'displayName': 'TEST expired',
      'status': 'closed',
      'restoreUntilMs': 0,
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> pending() async => List.of(requests);
  @override
  Future<void> finishClosure(String uid) async {
    finished.add(uid);
    requests.removeWhere((value) => value['uid'] == uid);
  }

  @override
  Future<void> restore(String uid) async {
    restored.add(uid);
    requests.removeWhere((value) => value['uid'] == uid);
  }
}

Future<void> open(
  WidgetTester tester,
  Widget screen, {
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(440, 956));
  tester.view.devicePixelRatio = 1;
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: screen,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder field(String label) => find.byKey(ValueKey('account-field:$label'));
Future<void> tap(WidgetTester tester, String text) async {
  final found = find.text(text).last;
  await tester.ensureVisible(found);
  await tester.tap(found);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Widget profile(AccountGateway gateway, {VoidCallback? signedOut}) => Scaffold(
  body: SafeArea(
    child: AccountProfilePanel(
      name: 'Rahul Sharma',
      phone: '+919848011223',
      email: 'rahul.broker@example.invalid',
      role: 'broker',
      gateway: gateway,
      onSignedOut: signedOut,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadApprovedFonts);
  testWidgets(
    'changing account gateway during an email request clears busy and stale private challenge state',
    (tester) async {
      final previous = TestAccountGateway()..delayedEmail = Completer<String>();
      await open(tester, AccountDetailsScreen(gateway: previous));
      await tester.enterText(field('Email'), 'new@example.invalid');
      await tap(tester, 'Save');
      expect(previous.requests, 1);
      final next = TestAccountGateway();
      await open(tester, AccountDetailsScreen(gateway: next));
      expect(
        tester.widget<TextField>(field('Email')).controller!.text,
        'rahul.broker@example.invalid',
      );
      previous.delayedEmail!.complete('stale-email-code');
      await tester.pump();
      await tap(tester, 'Save');
      expect(next.saved.length, 1);
      expect(next.requests, 0);
      expect(find.text('Verify and save'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'name validation is inline once and valid details persist on reopening without changing verified phone',
    (tester) async {
      final gateway = TestAccountGateway();
      await open(tester, AccountDetailsScreen(gateway: gateway));
      await tester.enterText(field('Full name *'), '');
      await tap(tester, 'Save');
      expect(find.text('Enter your full name.'), findsOneWidget);
      expect(gateway.saved, isEmpty);
      await tester.enterText(field('Full name *'), 'TEST updated name');
      await tester.enterText(field('City'), 'TEST Hyderabad');
      await tap(tester, 'Save');
      expect(gateway.saved.single['displayName'], 'TEST updated name');
      expect(gateway.values['phone'], '+919848011223');
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, AccountDetailsScreen(gateway: gateway));
      expect(
        tester.widget<TextField>(field('Full name *')).controller!.text,
        'TEST updated name',
      );
      expect(find.text('Verified'), findsOneWidget);
    },
  );
  testWidgets(
    'invalid or removed login email remains inline and sends no OTP',
    (tester) async {
      final gateway = TestAccountGateway();
      await open(tester, AccountDetailsScreen(gateway: gateway));
      await tester.enterText(field('Email'), 'invalid');
      await tap(tester, 'Save');
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await tester.enterText(field('Email'), '');
      await tap(tester, 'Save');
      expect(
        find.text('Your verified login email cannot be removed here.'),
        findsOneWidget,
      );
      expect(gateway.requests, 0);
      expect(gateway.saved, isEmpty);
    },
  );
  testWidgets(
    'changed email must verify normal challenge; wrong OTP is inline and retry saves once',
    (tester) async {
      final gateway = TestAccountGateway()..wrongCode = true;
      await open(tester, AccountDetailsScreen(gateway: gateway));
      await tester.enterText(field('Email'), 'other@example.invalid');
      await tap(tester, 'Save');
      expect(gateway.requests, 1);
      expect(gateway.saved, isEmpty);
      await tap(tester, 'Verify and save');
      expect(
        find.text('Enter all six digits from your email.'),
        findsOneWidget,
      );
      tester
              .widget<ApprovedOtpInput>(find.byType(ApprovedOtpInput))
              .controller
              .text =
          '654321';
      await tap(tester, 'Verify and save');
      expect(find.text('The code is incorrect.'), findsOneWidget);
      expect(gateway.saved, isEmpty);
      gateway.wrongCode = false;
      await tap(tester, 'Verify and save');
      expect(gateway.saved.single['email'], 'other@example.invalid');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'retry after a successful OTP and failed profile write never consumes the OTP twice',
    (tester) async {
      final gateway = TestAccountGateway()..failSave = true;
      await open(tester, AccountDetailsScreen(gateway: gateway));
      await tester.enterText(field('Email'), 'new@example.invalid');
      await tap(tester, 'Save');
      tester
              .widget<ApprovedOtpInput>(find.byType(ApprovedOtpInput))
              .controller
              .text =
          '654321';
      await tap(tester, 'Verify and save');
      expect(gateway.verifications, 1);
      expect(find.text('TEST save unavailable.'), findsOneWidget);
      gateway.failSave = false;
      await tap(tester, 'Verify and save');
      expect(gateway.verifications, 1);
      expect(gateway.saved, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'read timeout offers retry; changing identity discards a late old profile result',
    (tester) async {
      final old = TestAccountGateway()
        ..delayed = Completer<AccountProfileData>();
      await open(tester, AccountDetailsScreen(gateway: old));
      await tester.pump(const Duration(seconds: 46));
      await tester.pump();
      expect(find.textContaining('taking too long'), findsOneWidget);
      final next = TestAccountGateway()
        ..values['displayName'] = 'TEST second user';
      await open(tester, AccountDetailsScreen(gateway: next));
      old.delayed!.complete(AccountProfileData(old.values));
      await tester.pump();
      expect(
        tester.widget<TextField>(field('Full name *')).controller!.text,
        'TEST second user',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'after verified email and failed save, changing back still needs a new OTP and a blank email is rejected',
    (tester) async {
      final gateway = TestAccountGateway()..failSave = true;
      await open(tester, AccountDetailsScreen(gateway: gateway));
      await tester.enterText(field('Email'), 'new@example.invalid');
      await tap(tester, 'Save');
      tester
              .widget<ApprovedOtpInput>(find.byType(ApprovedOtpInput))
              .controller
              .text =
          '654321';
      await tap(tester, 'Verify and save');
      expect(gateway.verifications, 1);
      await tester.enterText(field('Email'), '');
      await tester.pump();
      await tap(tester, 'Save');
      expect(
        find.text('Your verified login email cannot be removed here.'),
        findsOneWidget,
      );
      await tester.enterText(field('Email'), 'rahul.broker@example.invalid');
      await tester.pump();
      await tap(tester, 'Save');
      expect(gateway.requests, 2);
      expect(gateway.saved, isEmpty);
      tester
              .widget<ApprovedOtpInput>(find.byType(ApprovedOtpInput))
              .controller
              .text =
          '654321';
      gateway.failSave = false;
      await tap(tester, 'Verify and save');
      expect(gateway.verifications, 2);
      expect(gateway.saved.single['email'], 'rahul.broker@example.invalid');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('owner and tenant details omit broker-only RERA', (tester) async {
    await open(
      tester,
      AccountDetailsScreen(gateway: TestAccountGateway(), role: 'tenant'),
    );
    expect(field('RERA number (if you have)'), findsNothing);
  });
  testWidgets(
    'logout cancellation stays logged in and final confirmation signs out once',
    (tester) async {
      final gateway = TestAccountGateway();
      var signedOut = 0;
      await open(tester, profile(gateway, signedOut: () => signedOut++));
      await tap(tester, 'Log out');
      await tap(tester, 'No, stay');
      expect(gateway.loggedOut, false);
      await tap(tester, 'Log out');
      await tap(tester, 'Yes, log out');
      expect(gateway.loggedOut, true);
      expect(signedOut, 1);
    },
  );
  testWidgets(
    'three deletion confirmations and final consent are required; uncertain backend is never displayed as closed',
    (tester) async {
      final gateway = TestAccountGateway()..uncertainClose = true;
      await open(tester, profile(gateway));
      await tap(tester, 'Delete account');
      await tap(tester, 'Yes, delete');
      await tap(tester, 'Yes, I am sure');
      expect(gateway.closes, 0);
      await tap(tester, 'Close account');
      expect(gateway.closes, 0);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tap(tester, 'Close account');
      expect(gateway.closes, 1);
      expect(find.text('Your account is closed'), findsNothing);
      gateway.uncertainClose = false;
      await tap(tester, 'Close account');
      expect(find.text('Your account is closed'), findsOneWidget);
      await tap(tester, 'Close');
      expect(gateway.loggedOut, true);
    },
  );
  testWidgets(
    'standalone offline closure returns to gallery after successful close and logout',
    (tester) async {
      final app = UiTestApp();
      addTearDown(app.router.dispose);
      addTearDown(app.properties.dispose);
      await open(tester, app);
      app.router.go('/ui-test/account/close');
      await tester.pumpAndSettle();
      await tap(tester, 'Yes, delete');
      await tap(tester, 'Yes, I am sure');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tap(tester, 'Close account');
      await tap(tester, 'Close');
      await tester.pumpAndSettle();
      expect(find.text('TrustKeyper UI Test'), findsOneWidget);
      expect(find.byType(AccountClosureScreen), findsNothing);
    },
  );
  for (final stale in [false, true]) {
    testWidgets(
      'blocked or stale-login account cannot advance deletion: stale=$stale',
      (tester) async {
        final gateway = TestAccountGateway()
          ..blocked = !stale
          ..staleLogin = stale;
        await open(tester, profile(gateway));
        await tap(tester, 'Delete account');
        await tap(tester, 'Yes, delete');
        expect(find.text('Step 1 of 3'), findsOneWidget);
        expect(gateway.closes, 0);
        await tap(tester, 'Keep my account');
        expect(gateway.closed, false);
      },
    );
  }
  testWidgets(
    'bank read failure provides an actual retry rather than an endless loader',
    (tester) async {
      final gateway = TestAccountGateway()..failRead = true;
      await open(tester, AccountBankScreen(gateway: gateway));
      expect(find.text('TEST connection unavailable.'), findsOneWidget);
      gateway.failRead = false;
      await tap(tester, 'Retry');
      expect(find.text('State Bank of India'), findsOneWidget);
      expect(find.text('•••• •••• 7766'), findsOneWidget);
    },
  );
  testWidgets(
    'admin closure queue distinguishes finish, restore and expired review; all actions require confirmation',
    (tester) async {
      final gateway = RestorationFixture();
      await open(tester, AccountRestorationQueue(gateway: gateway));
      await tap(tester, 'Complete closure');
      await tap(tester, 'Cancel');
      expect(gateway.finished, isEmpty);
      await tap(tester, 'Complete closure');
      await tap(tester, 'Complete closure');
      expect(gateway.finished, ['pending']);
      await tap(tester, 'Restore');
      await tap(tester, 'Restore');
      expect(gateway.restored, ['closed']);
      expect(find.text('Review'), findsOneWidget);
    },
  );
  testWidgets(
    'approved help accordions expand to real guidance and do not overflow at large text',
    (tester) async {
      await open(tester, const AccountHelpScreen(), scale: 1.5);
      await tap(tester, 'Owner did not get the link');
      expect(
        find.textContaining('WhatsApp and SMS open a composer'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final entry in [
    'profile',
    'details',
    'help',
    'delete-dialog',
    'closure-warning',
    'closure-warning-confirmed',
  ]) {
    testWidgets('approved account visual regression: $entry', (tester) async {
      final gateway = TestAccountGateway();
      await open(tester, switch (entry) {
        'details' => AccountDetailsScreen(gateway: gateway),
        'help' => const AccountHelpScreen(),
        'closure-warning' || 'closure-warning-confirmed' =>
          AccountClosureScreen(gateway: gateway, initialStep: 2),
        _ => profile(gateway),
      });
      if (entry == 'delete-dialog') await tap(tester, 'Delete account');
      if (entry == 'closure-warning-confirmed') {
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/build45/account-$entry.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
