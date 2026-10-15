import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_web_entry_screen.dart';

void main() {
  testWidgets(
    'mobile download and app-open use the correct package without including OTP or private links',
    (tester) async {
      final links = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrokerWebEntryScreen(
            phone: '+919999999999',
            openLink: (uri) async {
              links.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Brokers use the TrustKeyper app'), findsOneWidget);
      await tester.tap(find.text('Get it on Google Play'));
      await tester.pumpAndSettle();
      expect(links.single.toString(), brokerPlayStoreUrl);
      await tester.tap(find.text('I have the app · Open it'));
      await tester.pumpAndSettle();
      expect(links.last.scheme, 'intent');
      expect(
        links.last.toString(),
        contains('package=com.trustkeyper.mobile;'),
      );
      expect(links.last.toString(), isNot(contains('uitest')));
    },
  );
  testWidgets(
    'desktop displays a real QR encoding the exact Play link and opens a truthful WhatsApp composer',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final links = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrokerWebEntryScreen(
            phone: '+919999999999',
            openLink: (uri) async {
              links.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.semanticsLabel, brokerPlayStoreUrl);
      expect(qr.size, 220);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Send link to my phone'));
      await tester.pumpAndSettle();
      expect(links.single.host, 'wa.me');
      expect(links.single.path, '/919999999999');
      expect(
        links.single.queryParameters['text'],
        contains(brokerPlayStoreUrl),
      );
      expect(find.text('Link sent'), findsNothing);
    },
  );
  testWidgets(
    'failed launch shows recoverable error rather than successful delivery',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: BrokerWebEntryScreen(openLink: (_) async => false)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get it on Google Play'));
      await tester.pumpAndSettle();
      expect(
        find.text('The link could not be opened. Try again.'),
        findsOneWidget,
      );
    },
  );
}
