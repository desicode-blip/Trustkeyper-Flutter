import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trustkeyper/src/features/broker/data/broker_property_repository.dart';
import 'package:trustkeyper/src/tk2/tk2_app.dart';
import 'package:trustkeyper/src/tk2/tk2_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Tk2Store', () {
    test('shows the example until the first own property, then removes it', () async {
      final store = Tk2Store.forTest();
      await store.load();
      expect(store.shown.single.sample, isTrue);
      final saved = await store.saveProperty(BrokerProperty(id: '', name: 'Villa 7', address: 'Kondapur', rooms: '3 BHK', floor: 1, totalFloors: 2, furnishing: 'Full', inventory: {}));
      expect(store.sampleJustRemoved, isTrue);
      expect(store.shown.single.id, saved.id);
      expect(store.shown.single.sample, isFalse);
    });

    test('visit fee is held, released only with the right code, refunded on cancel', () async {
      final store = Tk2Store.forTest();
      await store.load();
      final v = await store.bookVisit(listingId: 'sample', name: 'Ravi', phone: '+91 9000000000', at: DateTime.now().add(const Duration(days: 1)));
      expect(store.heldTotal, 150);
      expect(await store.confirmVisit(v.id, '0000' == v.code ? '1111' : '0000'), isFalse);
      expect(store.heldTotal, 150);
      expect(await store.confirmVisit(v.id, v.code), isTrue);
      expect(store.heldTotal, 0);
      expect(store.releasedTotal, 150);

      final w = await store.bookVisit(listingId: 'sample', name: 'Sita', phone: '', at: DateTime.now().add(const Duration(days: 2)));
      await store.closeVisit(w.id, VisitStatus.cancelled);
      expect(store.visits.firstWhere((x) => x.id == w.id).feeStatus, 'refunded');
      expect(store.releasedTotal, 150);
    });

    test('saves and loads again', () async {
      final a = Tk2Store.forTest();
      await a.load();
      await a.setBroker('Suresh', '+91 9876543210');
      await a.saveProperty(BrokerProperty(id: '', name: 'Flat 1', address: 'Gachibowli', rooms: '1 BHK', floor: 2, totalFloors: 5, furnishing: 'Empty', inventory: {}));
      final b = Tk2Store.forTest();
      await b.load();
      expect(b.brokerName, 'Suresh');
      expect(b.listings.single.name, 'Flat 1');
      expect(b.shareText(b.listings.single), contains('https://trustkeyper.com/v/'));
    });

    test('share text hides door and owner; fee 0 means free', () async {
      final store = Tk2Store.forTest();
      await store.load();
      final text = store.shareText(Tk2Listing.example);
      expect(text, contains('Sri Sai Residency'));
      expect(text, isNot(contains('Flat 402')));
      expect(text, isNot(contains('90000')));
      expect(Tk2Listing.example.copyWith(visitFee: 0).feeText, 'Free');
      expect(store.shareText(Tk2Listing.example.copyWith(visitFee: 0)), contains('(free)'));
    });

    test('money in Indian style', () {
      expect(Tk2Store.money(150), '₹150');
      expect(Tk2Store.money(32000), '₹32,000');
      expect(Tk2Store.money(1250000), '₹12,50,000');
    });
  });

  testWidgets('welcome → example home → customer books → broker gets paid', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = Tk2Store.forTest();
    await tester.pumpWidget(TrustKeeper2App(store: store));

    // Signed in already: the main app's splash goes straight to home.
    await store.load();
    await store.setBroker('Suresh Kumar', '+91 9876543210');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Namaste, Suresh'), findsOneWidget);
    expect(find.text('Add property'), findsOneWidget);
    expect(find.text('Example'), findsNWidgets(4));
    // 4 designs of the same example; the door number never shows on cards.
    expect(find.text('2 BHK · Sri Sai Residency'), findsNWidgets(3));
    expect(find.textContaining('Flat 402'), findsNothing);
    expect(find.text('₹32,000 + ₹3,000 maintenance'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('2 BHK · Sri Sai Residency').first, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 BHK · Sri Sai Residency').first);
    await tester.pumpAndSettle();
    // Broker-only block is on the page, with the banner.
    await tester.scrollUntilVisible(find.text('Complete address and details'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Flat 402'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customer view'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Customer view ·'), findsOneWidget);
    expect(find.textContaining('Flat 402'), findsNothing);
    await tester.tap(find.text('Book a visit · ₹150'));
    await tester.pumpAndSettle();

    // Tomorrow always has free slots.
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await tester.tap(find.text('${tomorrow.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('11:00 am'));
    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Ravi');
    await tester.enterText(find.widgetWithText(TextField, 'Your phone'), '9000000000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay ₹150 and book'));
    await tester.pumpAndSettle();
    expect(find.text('Test payment. No money moves in this build.'), findsOneWidget);
    await tester.tap(find.text('Pay ₹150'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Visit booked!'), findsOneWidget);
    final code = store.visits.single.code;

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visits').last);
    await tester.pumpAndSettle();
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.text('₹150 held'), findsOneWidget);

    await tester.tap(find.text('Ravi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visit done · get ₹150'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, code);
    await tester.pumpAndSettle();
    expect(find.text('₹150 yours'), findsOneWidget);
    expect(store.releasedTotal, 150);
  });

  testWidgets('login keeps name and number, then opens home', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = Tk2Store.forTest();
    await store.load();
    final router = buildTk2Router(store)..go('/login');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Log in or sign up'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Type your name'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Suresh Kumar');
    await tester.enterText(find.byType(TextField).last, '9876543210');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(store.brokerName, 'Suresh Kumar');
    expect(find.text('Namaste, Suresh'), findsOneWidget);
  });

  testWidgets('all 4 property page designs open, each with the private block', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = Tk2Store.forTest();
    await store.load();
    await store.setBroker('Suresh', '+91 9876543210');
    for (final d in ['a', 'b', 'c', 'd', 'e']) {
      final router = buildTk2Router(store)..go('/p/sample?d=$d');
      await tester.pumpWidget(MaterialApp.router(key: ValueKey(d), routerConfig: router));
      await tester.pumpAndSettle();
      if (d == 'b') {
        await tester.tap(find.text('Only you'));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(find.text('Complete address and details'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Complete address and details'), findsOneWidget, reason: 'design $d');
    }
  });
}
