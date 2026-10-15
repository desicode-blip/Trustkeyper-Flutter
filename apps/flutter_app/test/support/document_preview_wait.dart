import 'package:flutter_test/flutter_test.dart';

Future<void> waitForDocumentPreview(
  WidgetTester tester, {
  bool upload = true,
  bool selectionOnly = false,
  String? reviewTitle,
}) async {
  final dialog = find.text(
    reviewTitle ??
        (selectionOnly
            ? 'Review selected file'
            : upload
            ? 'Review before uploading'
            : 'Private document'),
  );
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (dialog.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  expect(dialog, findsOneWidget);
}
