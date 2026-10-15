import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/presentation/paper_party_tabs.dart';
import 'package:trustkeyper/src/features/broker/presentation/party_document_header.dart';

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Roboto');
    for (final weight in [400, 500, 600, 700]) {
      fonts.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await fonts.load();
  });
  for (final owner in [true, false]) {
    for (final width in [363.4, 390.0]) {
      testWidgets(
        'both ${owner ? 'owner' : 'tenant'} tabs stay inside phone width $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      PaperPartyTabs(
                        owner: owner,
                        count: 2,
                        selected: 0,
                        onSelected: (_) {},
                      ),
                      PartyDocumentHeader(
                        name: 'TEST Person',
                        contact:
                            '99887 76655 · test.owner.with.long.address@test.invalid',
                        complete: true,
                        onEdit: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final index in [1, 2]) {
            final bounds = tester.getRect(
              find.text('${owner ? 'Owner' : 'Tenant'} $index'),
            );
            expect(bounds.left, greaterThanOrEqualTo(24));
            expect(bounds.right, lessThanOrEqualTo(width - 24));
          }
          final contact = tester.widget<Text>(
            find.textContaining('99887 76655'),
          );
          expect(contact.maxLines, 1);
          expect(contact.overflow, TextOverflow.ellipsis);
          expect(find.text('All done'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
