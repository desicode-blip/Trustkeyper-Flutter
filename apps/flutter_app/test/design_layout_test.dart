import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/core/widgets/approved_navigation.dart';
import 'package:trustkeyper/src/features/auth/presentation/auth_screens.dart';
import 'package:trustkeyper/src/features/auth/presentation/login_method.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_start_screen.dart';
import 'package:trustkeyper/src/features/broker/data/broker_repository.dart';
import 'package:trustkeyper/src/features/broker/presentation/approved_broker_home.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Roboto');
    for (final weight in [400, 500, 600, 700]) {
      loader.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  final screens = <String, Widget>{
    'onboarding': const OnboardingScreen(),
    'login': const LoginScreen(),
    'otp': const OtpScreen(
      destination: '9999999999',
      method: LoginMethod.phone,
    ),
    'roles': const RoleSelectionScreen(),
    'profile': const ProfileSetupScreen(),
    'approval-pending': const BrokerApprovalScreen(),
    'approval-verified': const BrokerApprovalScreen(
      phoneVerified: true,
      emailVerified: true,
    ),
    'paused': const AccountPausedScreen(),
    'broker-start': const BrokerStartScreen(),
    'broker-steps': const BrokerAgreementStepsScreen(),
    'broker-home': Scaffold(
      body: SafeArea(
        child: ApprovedBrokerHome(
          profile: const BrokerProfile(
            displayName: 'Rahul Sharma',
            email: '',
            phone: '',
            approvalStatus: 'approved',
          ),
          approvalPending: false,
          onOpenProfile: () {},
        ),
      ),
      bottomNavigationBar: ApprovedBrokerNavigation(
        selectedIndex: 0,
        onSelected: (index) {},
      ),
    ),
  };

  for (final entry in screens.entries) {
    for (final size in [const Size(440, 956), const Size(320, 640)]) {
      testWidgets(
        '${entry.key} fits ${size.width.toInt()}px without overflow',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(size.width == 320 ? 1.3 : 1),
                ),
                child: child!,
              ),
              home: RepaintBoundary(key: boundary, child: entry.value),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await precacheImage(
              const AssetImage('assets/images/trustkeyper-logo-approved.png'),
              boundary.currentContext!,
            );
          });
          await tester.pump();
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('WRITE_UI_CAPTURES') &&
              size.width == 440) {
            final rendering =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            debugDisableShadows = false;
            rendering.markNeedsPaint();
            await tester.pump();
            try {
              await tester.runAsync(() async {
                final capture = await rendering.toImage(pixelRatio: 1);
                final bytes = await capture.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final directory = Directory('../../output/ui-audit/native');
                await directory.create(recursive: true);
                await File(
                  '${directory.path}/${entry.key}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                capture.dispose();
              });
            } finally {
              debugDisableShadows = true;
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'role choice updates accessible selection and keeps its action at the bottom',
    (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const RoleSelectionScreen()),
      );
      await tester.pumpAndSettle();
      Finder selectedRole(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == label &&
            widget.properties.selected == true,
      );
      expect(selectedRole('Broker'), findsOneWidget);
      expect(
        tester.getTopLeft(find.widgetWithText(FilledButton, 'Continue')).dy,
        greaterThan(800),
      );
      await tester.tap(find.text('Property owner'));
      await tester.pumpAndSettle();
      expect(selectedRole('Property owner'), findsOneWidget);
      expect(selectedRole('Broker'), findsNothing);
      await tester.tap(find.text('Tenant'));
      await tester.pumpAndSettle();
      expect(selectedRole('Tenant'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('broker choices navigate to separate entry points', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, state) => const BrokerStartScreen(),
        ),
        GoRoute(
          path: '/broker/agreement/steps',
          builder: (context, state) => const Text('New agreement entry'),
        ),
        GoRoute(
          path: '/broker/renew',
          builder: (context, state) => const Text('Renewal entry'),
        ),
        GoRoute(
          path: '/broker/sign-only',
          builder: (context, state) => const Text('Sign-only entry'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    for (final choice in [
      ('New agreement', 'New agreement entry'),
      ('Renew agreement', 'Renewal entry'),
      ('Only get it signed', 'Sign-only entry'),
    ]) {
      router.go('/start');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(choice.$1));
      await tester.tap(find.text(choice.$1));
      await tester.pumpAndSettle();
      expect(find.text(choice.$2), findsOneWidget);
    }
  });

  for (final width in [440.0, 363.0, 320.0]) {
    testWidgets(
      'broker navigation keeps complete labels on one line at ${width.toInt()}px',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              bottomNavigationBar: ApprovedBrokerNavigation(
                selectedIndex: 0,
                onSelected: (index) => selected = index,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in ApprovedBrokerNavigation.labels) {
          final finder = find.text(label);
          expect(finder, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: finder, matching: find.byType(RichText)),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(paragraph.size.height, lessThanOrEqualTo(20));
          await tester.tap(finder);
          expect(selected, ApprovedBrokerNavigation.labels.indexOf(label));
        }
        expect(
          tester.getSize(find.byType(ApprovedBrokerNavigation)).height,
          lessThan(100),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('agreement introduction starts the property journey', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const BrokerAgreementStepsScreen(),
        ),
        GoRoute(
          path: '/broker/property',
          builder: (context, state) => const Text('Property journey'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pumpAndSettle();
    expect(find.text('5 easy steps'), findsOneWidget);
    expect(find.text('About 10 min'), findsOneWidget);
    await tester.tap(find.text("Let's start"));
    await tester.pumpAndSettle();
    expect(find.text('Property journey'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approval does not claim verification that has not happened', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const BrokerApprovalScreen(phoneVerified: true),
      ),
    );
    expect(find.text('Email verification is still needed'), findsOneWidget);
    expect(find.text('Phone and email verified'), findsNothing);
  });
}
