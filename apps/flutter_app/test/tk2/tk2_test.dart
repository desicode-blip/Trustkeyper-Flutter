import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/tk2/tk2_link.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trustkeyper/src/features/broker/data/broker_property_repository.dart';
import 'package:trustkeyper/src/tk2/tk2_app.dart';
import 'package:trustkeyper/src/tk2/tk2_designs.dart';
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
      expect(b.shareText(b.listings.single), contains('$tk2WebApp#p-'));
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

    test('brokerage: saved, shown to customers only when set', () async {
      final store = Tk2Store.forTest();
      await store.load();
      final none = Tk2Listing.example.copyWith(brokerage: 0);
      expect(none.brokerageText, 'No brokerage');
      expect(store.shareText(none), isNot(contains('Brokerage')));
      final some = Tk2Listing.example.copyWith(brokerage: 30000);
      expect(store.shareText(some), contains('Brokerage ₹30,000'));
      expect(Tk2Listing.fromJson(some.toJson()).brokerage, 30000);
    });

    test('visit hours: 7 am – 11 pm by default; outside the broker hours is closed', () {
      final l = Tk2Listing.example;
      expect(Tk2Listing.visitHours.first, 7);
      expect(Tk2Listing.visitHours.last, 23);
      expect(Tk2Listing.visitHours.every(l.slotOpen), isTrue);
      final narrow = l.copyWith(visitFrom: 10, visitTo: 18);
      expect(narrow.slotOpen(9), isFalse);
      expect(narrow.slotOpen(10), isTrue);
      expect(narrow.slotOpen(18), isTrue);
      expect(narrow.slotOpen(19), isFalse);
      expect(Tk2Listing.fromJson(narrow.toJson()).visitFrom, 10);
    });

    test('who can rent: Anyone ticks/unticks all; old values still load', () {
      final all = {...Tk2Listing.tenantTypes};
      expect(Tk2Listing.toggleTenant(all, 'Anyone'), isEmpty);
      expect(Tk2Listing.toggleTenant(<String>{}, 'Anyone'), all);
      final noCo = Tk2Listing.toggleTenant(all, 'Companies');
      expect(Tk2Listing.tenantText(noCo), 'Family, Bachelor male, Bachelor female');
      expect(Tk2Listing.tenantText(Tk2Listing.toggleTenant(noCo, 'Companies')), 'Anyone');
      expect(Tk2Listing.tenantSet('Bachelors'), {'Bachelor male', 'Bachelor female'});
      expect(Tk2Listing.tenantSet('Anyone'), all);
    });

    test('brokerage from rent; visit days', () {
      expect(Tk2Listing.brokerageFor(30000, 30), 30000);
      expect(Tk2Listing.brokerageFor(30000, 15), 15000);
      final l = Tk2Listing.example.copyWith(brokerage: 15000, brokerageDays: 15, visitDays: 'weekends');
      expect(l.brokerageText, '15 days rent · ₹15,000');
      expect(l.dayOpen(DateTime(2026, 11, 7)), isTrue); // Saturday
      expect(l.dayOpen(DateTime(2026, 11, 9)), isFalse); // Monday
      expect(Tk2Listing.fromJson(l.toJson()).visitDays, 'weekends');
    });

    test('property link carries only public details', () {
      final l = Tk2Listing.example;
      final link = tk2PropertyLink(l, 'Suresh');
      final b32 = link.split('#p-').last;
      expect(RegExp(r'^[a-z2-7]+$').hasMatch(b32), isTrue);
      final json = jsonEncode(tk2PublicPayload(l, 'Suresh'));
      expect(tk2Base32(json), b32);
      expect(json, isNot(contains('402')));
      expect(json, isNot(contains(l.ownerName.isEmpty ? '~none~' : l.ownerName)));
      expect(tk2Base32('hi'), 'nbuq');
    });

    test('visit money: no-show half to broker, customer cancel 98% within 5 min', () {
      final now = DateTime(2026, 11, 2, 10);
      final v = Tk2Visit(id: 'v', listingId: 'x', customerName: 'R', customerPhone: '', at: 0, fee: 150, code: '1234', createdAt: now.millisecondsSinceEpoch);
      expect(v.withStatus(VisitStatus.noShow).brokerShare, 75);
      expect(v.withStatus(VisitStatus.noShow).customerRefund, 0);
      expect(v.withStatus(VisitStatus.cancelled).customerRefund, 150);
      expect(v.withStatus(VisitStatus.customerCancelled).customerRefund, 147);
      expect(v.customerCanCancel(now.add(const Duration(minutes: 4))), isTrue);
      expect(v.customerCanCancel(now.add(const Duration(minutes: 6))), isFalse);
    });

    test('address parts: flat stays private, society and area are shown', () async {
      final store = Tk2Store.forTest();
      await store.load();
      final saved = await store.saveProperty(BrokerProperty(id: '', name: 'Mine', address: 'Flat 9B, Green Park, Kondapur, Hyderabad', flat: 'Flat 9B', society: 'Green Park', area: 'Kondapur', city: 'Hyderabad', rooms: '2 BHK', floor: 2, totalFloors: 5, furnishing: 'Semi'));
      final l = store.listing(saved.id)!;
      expect(l.door, 'Flat 9B');
      expect(l.society, 'Green Park');
      expect(l.locality, 'Kondapur, Hyderabad');
      expect(store.shareText(l), isNot(contains('9B')));
      expect(jsonEncode(tk2PublicPayload(l, 'S')), isNot(contains('9B')));
    });

    test('brokerage: owner part stays private, tenant part is public', () {
      final l = Tk2Listing.example.copyWith(brokeragePayer: 'Both', ownerBrokerage: 12345, brokerage: 16000);
      expect(jsonEncode(tk2PublicPayload(l, 'S')), isNot(contains('12345')));
      expect(Tk2Listing.fromJson(l.toJson()).ownerBrokerage, 12345);
      expect(Tk2Listing.daysFor(32000, 32000), 30);
      expect(Tk2Listing.daysFor(32000, 16000), 15);
      expect(Tk2Listing.daysFor(32000, 5000), 0);
      // Old saves without a payer: tenant paid if there was an amount.
      final old = l.toJson()..remove('brokeragePayer');
      expect(Tk2Listing.fromJson(old).brokeragePayer, 'Tenant');
    });

    test('card heading is never empty (old properties without society)', () {
      final old = Tk2Listing(id: 'x', property: BrokerProperty(id: 'x', name: 'Green Villa', address: '', rooms: '2.5 BHK', floor: 1, totalFloors: 2, furnishing: 'Semi'));
      // Never the broker's own label ("Green Villa"); falls back to rooms.
      expect(tk2CardHeading(old), '2.5 BHK property');
      expect(tk2CardHeading(old.copyWith(locality: 'Kondapur, Hyderabad')), 'Kondapur');
      expect(tk2CardHeading(old.copyWith(society: 'My Home Avatar', locality: 'Kondapur')), 'My Home Avatar');
      final bare = Tk2Listing(id: 'y', property: BrokerProperty(id: 'y', address: '', rooms: '1 BHK', floor: 0, totalFloors: 0, furnishing: 'Empty'));
      expect(tk2CardHeading(bare), '1 BHK property');
    });

    test('public address drops house numbers', () {
      final l = Tk2Listing(id: 'z', property: BrokerProperty(id: 'z', name: 'VIVID', address: 'Flat 1203, 12th floor, Vivid Heights, Kondapur, Hyderabad', rooms: '3 BHK', floor: 12, totalFloors: 20, furnishing: 'Full'));
      expect(tk2PublicAddress(l), 'Vivid Heights, Kondapur, Hyderabad');
      expect(tk2CardHeading(l), 'Kondapur');
      expect(tk2CardHeading(l.copyWith(society: 'Vivid Heights')), 'Vivid Heights');
      expect(tk2PublicAddress(Tk2Listing(id: 'h', property: BrokerProperty(id: 'h', address: 'H.No 5-6-7, Road 3, Jubilee Hills', rooms: '2 BHK', floor: 0, totalFloors: 1, furnishing: 'Semi'))), 'Jubilee Hills');
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
    // Only designs E and B on home; door number never on cards.
    expect(find.text('Sri Sai Residency'), findsOneWidget); // E heading
    expect(find.text('2 BHK · ₹32,000 + ₹3,000 maintenance'), findsOneWidget); // B title
    expect(find.text('Sri Sai Residency, Madhapur, Hyderabad'), findsNWidgets(2)); // address line on both
    expect(find.textContaining('Flat 402'), findsNothing);
    expect(find.text('Example'), findsNothing);

    await tester.tap(find.text('Sri Sai Residency'));
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
    await tester.scrollUntilVisible(find.widgetWithText(TextField, 'Your phone'), 200, scrollable: find.byType(Scrollable).last);
    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Ravi');
    await tester.enterText(find.widgetWithText(TextField, 'Your phone'), '9000000000');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Pay ₹150 and book'), 200, scrollable: find.byType(Scrollable).last);
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
    for (final d in ['e', 'b']) {
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

  testWidgets('Add property opens the main app Onboard property journey', (tester) async {
    tester.view.physicalSize = const Size(1800, 2532); // test font is wider than Roboto
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = Tk2Store.forTest();
    await store.load();
    await store.setBroker('Suresh', '+91 9876543210');
    final router = buildTk2Router(store)..go('/home');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add property'));
    await tester.pumpAndSettle();
    // Name first, then the choice.
    expect(find.text('Add new property'), findsWidgets);
    await tester.enterText(find.byType(TextField).first, 'Flat 402, Madhapur');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Onboard property'), findsOneWidget);
    expect(find.text('Send link to owner'), findsOneWidget);
    await tester.tap(find.text('Add manually'));
    await tester.pumpAndSettle();
    expect(find.text('Onboard property'), findsNothing);
    // Back goes one screen at a time: details way → choice → name.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Onboard property'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
    expect(find.text('Give it a name you will remember.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add manually'));
    await tester.pumpAndSettle();
    expect(find.text('Things in the house. Tap + or −.'), findsNothing);
    // "Go to home" from the journey lands on TrustKeeper 2 home.
    router.go('/broker');
    await tester.pumpAndSettle();
    expect(find.text('Namaste, Suresh'), findsOneWidget);
  });
}
