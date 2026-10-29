import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/broker_property_repository.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_property_screen.dart';

BrokerProperty sampleProperty({String id = 'saved-property'}) => BrokerProperty(
  id: id,
  address: 'Flat 402, Phoenix Towers',
  rooms: '2 BHK',
  floor: 4,
  totalFloors: 5,
  furnishing: 'Semi',
  sizeSqFt: 1150,
  facing: 'North',
  carParking: 1,
  bikeParking: 1,
  inventory: {
    'Fan': 3,
    'Light': 6,
    'AC': 1,
    'Geyser': 2,
    'Cupboard': 2,
    'Bed': 0,
    'Chimney': 1,
  },
);

class MemoryPropertyRepository implements BrokerPropertyRepository {
  List<BrokerProperty> properties = [];
  List<BrokerProperty> saved = [];
  bool failSave = false;
  int watchCalls = 0;

  @override
  Stream<List<BrokerProperty>> watchProperties() {
    watchCalls++;
    return Stream.value(properties);
  }

  @override
  Future<BrokerProperty> save(BrokerProperty property) async {
    if (failSave) throw StateError('permission-denied');
    final stored = BrokerProperty.fromMap(
      property.id.isEmpty ? 'new-property' : property.id,
      property.toMap(),
    );
    saved.add(stored);
    return stored;
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> captureScreen(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  expect(tester.takeException(), isNull);
  if (!const bool.fromEnvironment('WRITE_UI_CAPTURES')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final capture = await boundary.toImage(pixelRatio: 1);
    final bytes = await capture.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('../../output/ui-audit/native');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    capture.dispose();
  });
}

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

  test('property fields round-trip without fabricated people or inventory', () {
    final sample = sampleProperty();
    final restored = BrokerProperty.fromMap(sample.id, sample.toMap());
    expect(restored.toMap(), sample.toMap());
    expect(restored.validationError, isNull);
    expect(restored.inventory['Chimney'], 1);
    expect(() => restored.inventory['Fan'] = 9, throwsUnsupportedError);
    final empty = BrokerProperty.fromMap('legacy', {});
    expect(empty.address, isEmpty);
    expect(empty.inventory, isEmpty);
    expect(empty.validationError, isNotNull);
  });

  test(
    'validation blocks impossible counts and incomplete property details',
    () {
      final data = sampleProperty().toMap();
      for (final change in [
        {'rooms': '9 BHK'},
        {'furnishing': 'Unknown'},
        {'floor': -1},
        {'floor': 6},
        {'totalFloors': 201},
        {'sizeSqFt': -20},
        {'sizeSqFt': double.infinity},
        {'carParking': -1},
        {'bikeParking': 101},
        {'facing': 'Unknown'},
        {
          'inventory': {'Fan': -1},
        },
        {
          'inventory': {'Fan': 101},
        },
      ]) {
        expect(
          BrokerProperty.fromMap('invalid', {
            ...data,
            ...change,
          }).validationError,
          isNotNull,
          reason: change.toString(),
        );
      }
      expect(
        BrokerProperty.fromMap('ground-floor', {
          ...data,
          'floor': 0,
          'totalFloors': 0,
          'sizeSqFt': null,
        }).validationError,
        isNull,
      );
    },
  );

  for (final width in [440.0, 320.0]) {
    testWidgets(
      'property journey at ${width.toInt()}px saves entered facts and preserves failed drafts',
      (tester) async {
        tester.view.physicalSize = Size(width, width == 440 ? 956 : 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = MemoryPropertyRepository();
        final boundary = GlobalKey();
        BrokerProperty? handedOff;
        final router = GoRouter(
          initialLocation: '/property',
          routes: [
            GoRoute(
              path: '/property',
              builder: (context, state) =>
                  BrokerPropertyScreen(repository: repository),
            ),
            GoRoute(
              path: '/broker/agreement',
              builder: (context, state) {
                handedOff = state.extra as BrokerProperty;
                return const Text('Owner details');
              },
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
            builder: (context, child) => RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                ),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (width == 440) {
          await captureScreen(tester, boundary, 'property-picker');
        }
        await tapVisible(tester, find.text('Add new property'));
        // 1. Name the property (required).
        expect(find.text('Give it a name you will remember.'), findsOneWidget);
        await tapVisible(tester, find.text('Next'));
        expect(find.text('Type a name for the property'), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('property-name')), 'Phoenix flat');
        await tapVisible(tester, find.text('Next'));
        // 2. How to add details: manual is first and picked.
        expect(find.text('Add details myself'), findsOneWidget);
        expect(find.text('Upload sale deed'), findsOneWidget);
        expect(find.text('Upload old rent agreement'), findsOneWidget);
        await tapVisible(tester, find.text('Upload sale deed'));
        await tapVisible(tester, find.text('Next'));
        expect(find.text('Reading a sale deed is coming soon'), findsOneWidget);
        await tapVisible(
          tester,
          find.descendant(of: find.byType(BottomSheet), matching: find.text('Add details myself')),
        );
        // 3. The usual details.
        expect(find.text('Tell us about the property.'), findsOneWidget);
        if (width == 440) {
          await captureScreen(tester, boundary, 'property-address-empty');
        }
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull,
        );
        await tester.enterText(
          find.byKey(const ValueKey('property-address')),
          'Flat 402, Phoenix Towers',
        );
        await tester.enterText(
          find.byKey(const ValueKey('property-size')),
          '1150',
        );
        await tapVisible(tester, find.text('North'));
        await tapVisible(tester, find.byTooltip('Increase Car parking'));
        await tapVisible(tester, find.byTooltip('Increase Bike parking'));
        await tapVisible(tester, find.text('Next'));
        await tapVisible(tester, find.text('Next'));
        expect(find.text('Choose the rooms'), findsOneWidget);
        await tapVisible(tester, find.text('2 BHK'));
        await tapVisible(tester, find.text('Semi'));
        for (int count = 0; count < 4; count++) {
          await tapVisible(tester, find.byTooltip('Increase Floor'));
        }
        for (int count = 0; count < 5; count++) {
          await tapVisible(tester, find.byTooltip('Increase Total floors'));
        }
        if (width == 440) {
          await captureScreen(tester, boundary, 'property-rooms');
        }
        await tapVisible(tester, find.text('Next'));
        await tapVisible(tester, find.byTooltip('Decrease Fan'));
        await tapVisible(tester, find.byTooltip('Increase Fan'));
        await tapVisible(tester, find.text('Add other item'));
        await tester.enterText(find.byType(TextField), 'Chimney');
        await tapVisible(tester, find.text('Add'));
        if (width == 440) {
          await captureScreen(tester, boundary, 'property-inventory');
        }
        repository.failSave = true;
        await tapVisible(tester, find.text('Save property'));
        expect(find.text('Property added'), findsNothing);
        expect(
          find.textContaining('Could not save your property'),
          findsOneWidget,
        );
        expect(find.text('Chimney'), findsOneWidget);
        expect(repository.saved, isEmpty);
        repository.failSave = false;
        await tapVisible(tester, find.text('Save property'));
        expect(find.text('Property added'), findsOneWidget);
        expect(repository.saved.single.address, 'Flat 402, Phoenix Towers');
        expect(repository.saved.single.name, 'Phoenix flat');
        expect(repository.saved.single.floor, 4);
        expect(repository.saved.single.totalFloors, 5);
        expect(repository.saved.single.inventory['Fan'], 1);
        expect(repository.saved.single.inventory['Chimney'], 1);
        expect(repository.watchCalls, 1);
        if (width == 440) {
          await captureScreen(tester, boundary, 'property-saved');
        }
        await tapVisible(tester, find.text('Next: Owner'));
        expect(handedOff?.id, 'new-property');
        expect(handedOff?.sizeSqFt, 1150);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'existing property search and back editing retain the saved values',
    (tester) async {
      final repository = MemoryPropertyRepository()
        ..properties = [sampleProperty()];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrokerPropertyScreen(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My properties (1)'), findsOneWidget);
      await tapVisible(tester, find.text('Search & select a property'));
      await tester.enterText(find.byType(TextField), 'phoenix');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Flat 402, Phoenix Towers'));
      expect(find.text('3 Fan'), findsOneWidget);
      await tapVisible(tester, find.text('Back'));
      expect(find.text('Chimney'), findsOneWidget);
      await tapVisible(tester, find.text('Save property'));
      expect(repository.saved.single.id, 'saved-property');
      expect(repository.saved.single.toMap(), sampleProperty().toMap());
      expect(tester.takeException(), isNull);
    },
  );
}
