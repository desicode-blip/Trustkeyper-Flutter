import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/document_requests/presentation/document_request_widgets.dart';

void main() {
  testWidgets(
    'document action exposes one accessible button and both tap areas work',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentRoundAction(
              glyph: 'camera',
              label: 'Add',
              onTap: () => taps++,
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Add'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add'));
      await tester.pump();
      expect(taps, 2);
      semantics.dispose();
    },
  );

  testWidgets('disabled document action stays non-interactive', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DocumentRoundAction(
            glyph: 'pencil',
            label: 'Type',
            onTap: null,
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Type'), findsOneWidget);
    expect(tester.widget<InkWell>(find.byType(InkWell).first).onTap, isNull);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
