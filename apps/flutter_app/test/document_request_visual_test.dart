import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/ui_test_main.dart';
import 'package:trustkeyper/src/features/document_requests/data/document_request_repository.dart';
import 'package:trustkeyper/src/features/document_requests/presentation/document_link_dialog.dart';
import 'package:trustkeyper/src/features/document_requests/presentation/recipient_document_screen.dart';
import 'document_request_test.dart' as fixture;
import 'inline_documents_test.dart' show fixtureImage;

class ArtboardRecipient extends fixture.RecipientFake {
  @override
  Future<DocumentRequestInfo> read(String token) async => DocumentRequestInfo({
    ...fixture
        .information(
          verified: verified,
          status: received ? 'added' : 'seen',
          paper: 'all',
        )
        .data,
    'partyName': 'Rajesh Kumar',
    'brokerName': 'Rahul',
    'phone': '+919988776655',
    'address': 'Phoenix Towers 402',
  });
}

void main() {
  testWidgets(
    'render real owner link, upload hub, Aadhaar, bank and share dialog against approved artboards',
    (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader('Roboto')
            ..addFont(rootBundle.load('assets/fonts/Roboto-400.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Roboto-500.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Roboto-600.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Roboto-700.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final boundary = GlobalKey();
      final gateway = ArtboardRecipient();
      Future<void> open() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              home: RecipientDocumentScreen(
                key: ValueKey(gateway.verified),
                token: fixture.token,
                gateway: gateway,
                pickFile: (_) async => fixtureImage(),
                reviewFile: (_) async => true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/images/trustkeyper-logo-approved.png'),
            boundary.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        final renderer =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await renderer.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '../../output/ui-audit/build32-ui-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      }

      await open();
      await capture('owner-link');
      gateway.verified = true;
      await open();
      await capture('owner-link-existing');
      await tester.tap(find.text('Continue with +919988776655'));
      await tester.pumpAndSettle();
      await capture('owner-upload');
      await tester.tap(find.text('Photo').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Front'));
      await tester.pumpAndSettle();
      await capture('owner-aadhaar');
      await tester.tap(find.byTooltip('Back to documents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      await capture('owner-bank');
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const DocumentLinkDialog(
                      paper: 'Aadhaar card',
                      name: 'Rajesh Kumar',
                      phone: '+91 99887 76655',
                      email: 'rajesh.kumar@gmail.com',
                    ),
                  ),
                  child: const Text('Show share'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show share'));
      await tester.pumpAndSettle();
      await capture('share-dialog');
      final brokerApp = UiTestApp();
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: brokerApp));
      brokerApp.router.go('/ui-test/broker-owner-links');
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/trustkeyper-logo-approved.png'),
          boundary.currentContext!,
        ),
      );
      await tester.pumpAndSettle();
      await capture('broker-owner-papers');
      for (final label in ['Owner 1', 'Owner 2']) {
        expect(
          (tester.renderObject(find.text(label)) as RenderParagraph)
              .didExceedMaxLines,
          isFalse,
          reason: '$label must not be shortened in the approved-width view.',
        );
      }
      await tester.tap(find.byTooltip('Send link').first);
      await tester.pumpAndSettle();
      await capture('broker-share-dialog');
    },
  );
}
