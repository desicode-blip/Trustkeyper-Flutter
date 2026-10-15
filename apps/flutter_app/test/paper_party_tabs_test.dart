import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/broker/presentation/paper_party_tabs.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-400.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-500.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-600.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-700.ttf')))
        .load();
  });

  testWidgets(
    'selected owner stays centered as approved when changing owners',
    (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: StatefulBuilder(
                builder: (context, update) => PaperPartyTabs(
                  owner: true,
                  count: 2,
                  selected: selected,
                  onSelected: (index) => update(() => selected = index),
                ),
              ),
            ),
          ),
        ),
      );
      Finder chip(String label) => find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first;
      expect(tester.getCenter(chip('Owner 1')).dx, closeTo(220, 0.1));
      await tester.tap(find.text('Owner 2'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(tester.getCenter(chip('Owner 2')).dx, closeTo(220, 0.1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact document tabs allow reaching every tenant without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: StatefulBuilder(
                builder: (context, update) => PaperPartyTabs(
                  owner: false,
                  count: 5,
                  selected: selected,
                  onSelected: (index) => update(() => selected = index),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Tenant 5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tenant 5'));
      await tester.pumpAndSettle();
      expect(selected, 4);
      final selectedChip = find
          .ancestor(of: find.text('Tenant 5'), matching: find.byType(Container))
          .first;
      expect(tester.getCenter(selectedChip).dx, closeTo(160, 0.1));
      expect(tester.takeException(), isNull);
    },
  );
}
