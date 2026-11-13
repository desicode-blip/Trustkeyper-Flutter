import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/tk2/tk2_link.dart';
import 'package:trustkeyper/src/features/auth/presentation/approved_auth_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trustkeyper/src/features/broker/data/broker_property_repository.dart';
import 'package:trustkeyper/src/tk2/tk2_app.dart';
import 'package:trustkeyper/src/tk2/tk2_designs.dart';
import 'package:trustkeyper/src/tk2/tk2_account.dart';
import 'package:trustkeyper/src/tk2/tk2_sort.dart';
import 'package:trustkeyper/src/tk2/tk2_cloud.dart';
import 'package:trustkeyper/src/tk2/tk2_store.dart';
import 'package:trustkeyper/src/tk2/tk2_sync.dart';
import 'package:trustkeyper/src/tk2/tk2_token.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Tk2Store', () {
    test('shows the example until the first own property, then removes it', () async {
      final store = Tk2Store.forTest();
      await store.load();
      expect(store.shown.single.sample, isTrue);
      final saved = await store.saveProperty(
        BrokerProperty(id: '', name: 'Villa 7', address: 'Kondapur', rooms: '3 BHK', floor: 1, totalFloors: 2, furnishing: 'Full', inventory: {}),
      );
      expect(store.sampleJustRemoved, isTrue);
      expect(store.shown.single.id, saved.id);
      expect(store.shown.single.sample, isFalse);
    });

    test('visit fee is held, released only with the right code, refunded on cancel', () async {
      final store = Tk2Store.forTest();
      await store.load();
      final v = await store.bookVisit(listingId: 'sample', name: 'Ravi', phone: '+91 9000000000', at: DateTime.now().add(const Duration(days: 1)));
      expect(store.heldTotal, 150);
      expect(await store.confirmVisit(v.id, '0000' == v.code ? '1111' : '0000'), 'wrong');
      expect(store.heldTotal, 150);
      // Code works only from 24 h before to 24 h after the visit time.
      expect(await store.confirmVisit(v.id, v.code, now: DateTime.now().subtract(const Duration(hours: 1))), 'window');
      expect(await store.confirmVisit(v.id, v.code), isNull);
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
      await a.saveProperty(
        BrokerProperty(id: '', name: 'Flat 1', address: 'Gachibowli', rooms: '1 BHK', floor: 2, totalFloors: 5, furnishing: 'Empty', inventory: {}),
      );
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

    test('account: main app profile screens save to the phone; delete wipes it', () async {
      final store = Tk2Store.forTest();
      await store.load();
      await store.setBroker('Suresh', '+91 98480 12345');
      final account = Tk2AccountGateway(store);
      await account.save({'displayName': 'Suresh Kumar', 'city': 'Hyderabad'});
      expect(store.brokerName, 'Suresh Kumar');
      expect((await account.read()).text('city'), 'Hyderabad');
      final challenge = await account.requestEmail('s@example.com');
      expect(() => account.verifyEmail('s@example.com', challenge, '000000'), throwsStateError);
      await account.verifyEmail('s@example.com', challenge, Tk2AccountGateway.demoCode);
      expect((await account.read()).flag('emailVerified'), isTrue);
      expect((await account.closure())['canClose'], isTrue);
      await account.close(reason: 'test', note: '');
      expect(store.brokerName, isEmpty);
      expect((await account.read()).text('email'), isEmpty);
    });

    test('turn off: rented → remind 10 months after rent start; other → from today; on again clears', () async {
      final store = Tk2Store.forTest();
      await store.load();
      final p = await store.saveProperty(
        BrokerProperty(id: '', name: 'Villa 7', address: 'Kondapur', rooms: '3 BHK', floor: 1, totalFloors: 2, furnishing: 'Full', inventory: {}),
      );
      final today = DateTime(2026, 11, 3);
      await store.deactivate(p.id, reason: 'Rented out by someone else', rentStart: DateTime(2026, 10, 1), now: today);
      expect(store.isActive(p.id), isFalse);
      expect(DateTime.fromMillisecondsSinceEpoch(store.inactive(p.id)!.remindAt), DateTime(2027, 8, 1));
      expect(store.remindersDue(DateTime(2027, 7, 31)), isEmpty);
      expect(store.remindersDue(DateTime(2027, 8, 1)).single.id, p.id);
      await store.remindLater(p.id, now: DateTime(2027, 8, 2));
      expect(store.remindersDue(DateTime(2027, 8, 3)), isEmpty);
      await store.activate(p.id);
      expect(store.isActive(p.id), isTrue);
      await store.deactivate(p.id, reason: 'Owner cancelled the tie-up', now: DateTime(2028, 1, 31));
      expect(DateTime.fromMillisecondsSinceEpoch(store.inactive(p.id)!.remindAt), DateTime(2028, 11, 30)); // 31 Nov → 30 Nov
      final again = Tk2Store.forTest();
      await again.load();
      expect(again.inactive(p.id)?.reason, 'Owner cancelled the tie-up');
    });

    test('sort and filter: BHK numbers, 4.5+, furnishing, active', () async {
      expect(
        [
          for (final r in ['1 RK', '1 BHK', '2.5 BHK', '4+ BHK']) tk2Bhk(r),
        ],
        [0.5, 1, 2.5, 4.5],
      );
      final store = Tk2Store.forTest();
      await store.load();
      Future<Tk2Listing> add(String rooms, int rent, String furnishing) async {
        final p = await store.saveProperty(
          BrokerProperty(id: '', name: rooms, address: 'Kondapur', rooms: rooms, floor: 1, totalFloors: 2, furnishing: furnishing, inventory: {}),
        );
        final l = store.listing(p.id)!.copyWith(rent: rent);
        await store.putListing(l);
        return l;
      }

      final a = await add('1 BHK', 15000, 'Empty');
      final b = await add('2.5 BHK', 30000, 'Semi');
      final c = await add('4+ BHK', 90000, 'Full');
      List<String> ids(Tk2ListFilter f) => [for (final l in f.apply(store.listings, store)) l.id];
      expect(ids(const Tk2ListFilter(sort: 'rentLow')), [a.id, b.id, c.id]);
      expect(ids(const Tk2ListFilter(sort: 'bhkHigh')), [c.id, b.id, a.id]);
      expect(ids(Tk2ListFilter(bhk: {4.5})), [c.id]);
      expect(ids(Tk2ListFilter(bhk: {1, 2.5}, sort: 'rentLow')), [a.id, b.id]);
      expect(ids(const Tk2ListFilter(furnishing: {'Semi'})), [b.id]);
      await store.deactivate(b.id, reason: 'Owner is using it');
      expect(ids(const Tk2ListFilter(status: 'off')), [b.id]);
      expect(Tk2ListFilter(bhk: {1}, status: 'off').count, 2);
    });

    test('visit time: any minute inside the window, 1 hour ahead, rounded to 5 minutes', () {
      final l = Tk2Listing.example.copyWith(visitFrom: 9, visitTo: 20, visitDays: 'all');
      final now = DateTime(2026, 11, 4, 16, 42);
      expect(l.earliestVisit(now, now), DateTime(2026, 11, 4, 17, 45));
      expect(l.earliestVisit(DateTime(2026, 11, 5), now), DateTime(2026, 11, 5, 9));
      expect(l.earliestVisit(now, DateTime(2026, 11, 4, 19, 30)), isNull); // 8:30 pm is past 8 pm
      expect(l.visitTimeOk(DateTime(2026, 11, 5, 16, 35), now), isTrue);
      expect(l.visitTimeOk(DateTime(2026, 11, 5, 20, 5), now), isFalse);
      expect(l.visitTimeOk(DateTime(2026, 11, 4, 17, 10), now), isFalse);
    });

    test('rent negotiable: off by default, shown on the rent line, travels in the link', () {
      final l = Tk2Listing.example;
      expect(l.rentNegotiable, isFalse);
      final n = l.copyWith(rentNegotiable: true);
      expect(n.rentLine, endsWith('· negotiable'));
      expect(Tk2Listing.fromJson(n.toJson()).rentNegotiable, isTrue);
      expect(tk2ListingFromPublic(tk2PublicPayload(n, 'S').cast<String, dynamic>()).rentNegotiable, isTrue);
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

    test('backend public listing: only fields the Firestore rules allow; no door, owner, keys or note', () {
      final l = Tk2Listing.example.copyWith(
        door: 'B-1204',
        ownerName: 'Hari Rao',
        ownerPhone: '+91 90000 12345',
        keys: 'With security',
        note: 'Gate code 4455',
        photos: ['/var/mobile/x.jpg', 'https://firebasestorage.googleapis.com/p.jpg'],
      );
      final doc = Tk2Cloud.publicDoc(l, brokerUid: 'b1', brokerName: 'Suresh', brokerPhone: '+91 98480 12345', active: true, ownerUid: 'o1', inviteId: 'i1');
      final text = jsonEncode({...doc}..remove('updatedAt'));
      for (final secret in ['B-1204', 'Hari', '90000 12345', 'With security', '4455', '/var/mobile']) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      expect(doc['ph'], ['https://firebasestorage.googleapis.com/p.jpg']);
      // Same list as publicOnly() in firestore.rules: keep them in step.
      final rules = File('../../firestore.rules').readAsStringSync();
      final allowed = RegExp(
        r"publicOnly\(\) \{\s*return request\.resource\.data\.keys\(\)\.hasOnly\(\[([^\]]+)\]\)",
      ).firstMatch(rules)!.group(1)!.split(',').map((k) => k.trim().replaceAll("'", '')).toSet();
      expect(allowed.containsAll(doc.keys), isTrue, reason: '${doc.keys.toSet().difference(allowed)}');
    });

    test('owner-added house: owner name, number and keys fill the broker block; the broker\'s own entries win', () {
      final answers = {
        'keys': 'Security',
        'keyName': 'Ramu',
        'keyPhone': '+91 90000 11111',
        'keyNote': 'Ask at gate 2',
        'ownerName': 'Lakshmi',
        'ownerContact': '+91 90000 77777',
      };
      final filled = tk2WithOwnerAnswers(Tk2Listing.example.copyWith(ownerName: '', ownerPhone: '', keys: '', note: ''), answers);
      expect(filled.ownerName, 'Lakshmi');
      expect(filled.ownerPhone, '+91 90000 77777');
      expect(filled.keys, 'With security');
      expect(filled.note, 'Keys: Security · Ramu · +91 90000 11111\nAsk at gate 2');
      final mine = tk2WithOwnerAnswers(Tk2Listing.example.copyWith(ownerName: 'Hari', keys: 'Lockbox', note: 'mine'), answers);
      expect([mine.ownerName, mine.keys, mine.note], ['Hari', 'Lockbox', 'mine']);
      expect(tk2WithOwnerAnswers(Tk2Listing.example.copyWith(ownerPhone: ''), {'ownerContact': 'a@b.co'}).ownerPhone, '');
    });

    test('token: broker default fills new properties; each property can differ; link carries it', () async {
      final store = Tk2Store.forTest();
      await store.load();
      expect(store.defaultToken, 15000);
      await store.setDefaultToken(20000);
      final p = await store.saveProperty(
        BrokerProperty(id: '', name: 'A', address: 'Flat 1, Madhapur', rooms: '2 BHK', floor: 1, totalFloors: 2, furnishing: 'Empty', inventory: {}),
      );
      final l = store.listing(p.id)!;
      expect(l.token, 20000);
      await store.saveListing(l.copyWith(token: 25000));
      expect(store.listing(p.id)!.token, 25000);
      // Changing the default later leaves saved properties alone.
      await store.setDefaultToken(10000);
      expect(store.listing(p.id)!.token, 25000);
      final back = tk2ListingFromPublic(tk2PublicPayload(store.listing(p.id)!, 'S'));
      expect(back.token, 25000);
      // Old saves and links without a token use the fallback.
      expect(Tk2Listing.fromJson(const {'id': 'x'}).tokenOr(15000), 15000);
      expect(tk2TokenError('').$2, 'Type the token amount');
      expect(tk2TokenError('15000'), (15000, null));
    });

    test('visit money: no-show half to broker, customer cancel 98% within 5 min', () {
      final now = DateTime(2026, 11, 2, 10);
      final v = Tk2Visit(id: 'v', listingId: 'x', customerName: 'R', customerPhone: '', at: 0, fee: 150, code: '1234', createdAt: now.millisecondsSinceEpoch);
      expect(v.withStatus(VisitStatus.noShow).brokerShare, 75);
      expect(v.withStatus(VisitStatus.noShow).customerRefund, 0);
      expect(v.withStatus(VisitStatus.cancelled).customerRefund, 150);
      expect(v.withStatus(VisitStatus.customerCancelled).customerRefund, 147);
      expect(v.inRefundWindow(now.add(const Duration(minutes: 4))), isTrue);
      expect(v.inRefundWindow(now.add(const Duration(minutes: 6))), isFalse);
      // Late cancel: no refund; broker was told in advance, so nothing for him either.
      expect(v.withStatus(VisitStatus.customerCancelledLate).customerRefund, 0);
      expect(v.withStatus(VisitStatus.customerCancelledLate).brokerShare, 0);
      expect(v.withStatus(VisitStatus.customerCancelledLate).feeStatus, 'kept');
    });

    test('customer can cancel late (no refund); gate pass is saved', () async {
      final store = Tk2Store.forTest();
      await store.load();
      final v = await store.bookVisit(listingId: 'sample', name: 'Ravi', phone: '', at: DateTime.now().add(const Duration(days: 1)));
      await store.addGatePass(v.id, 'pass.jpg');
      expect(store.visits.single.gatePass, 'pass.jpg');
      expect(await store.customerCancel(v.id, now: DateTime.now().add(const Duration(minutes: 10))), isTrue);
      expect(store.visits.single.status, VisitStatus.customerCancelledLate);
      expect(await store.customerCancel(v.id), isFalse);
    });

    test('address parts: flat stays private, society and area are shown', () async {
      final store = Tk2Store.forTest();
      await store.load();
      final saved = await store.saveProperty(
        BrokerProperty(
          id: '',
          name: 'Mine',
          address: 'Flat 9B, Green Park, Kondapur, Hyderabad',
          flat: 'Flat 9B',
          society: 'Green Park',
          area: 'Kondapur',
          city: 'Hyderabad',
          rooms: '2 BHK',
          floor: 2,
          totalFloors: 5,
          furnishing: 'Semi',
        ),
      );
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

    test('who can rent label: no "only"; male + female = Bachelor', () {
      expect(Tk2Listing.tenantLabel('Anyone'), 'Anyone can rent');
      expect(Tk2Listing.tenantLabel('Bachelor female'), 'Bachelor female');
      expect(Tk2Listing.tenantLabel('Bachelor male, Bachelor female'), 'Bachelor');
      expect(Tk2Listing.tenantLabel('Family, Bachelor male, Bachelor female'), 'Family, Bachelor');
      expect(Tk2Listing.example.copyWith(tenants: 'Family').rules, isNot(contains('only')));
    });

    test('send: new number is saved once and listed for next time', () async {
      final store = Tk2Store.forTest();
      await store.load();
      await store.sendListing('x', name: 'Ravi', phone: '+91 98765 43210', whatsapp: true, sms: true);
      await store.sendListing('x', name: 'Ravi K', phone: '+919876543210', whatsapp: true, sms: false);
      expect(store.contacts.length, 1);
      expect(store.contacts.single.name, 'Ravi K');
      // Email is remembered for next time, even when a later send has none.
      await store.sendListing('x', name: 'Ravi K', phone: '+91 98765 43210', email: 'ravi@example.com', whatsapp: false, sms: false, byEmail: true);
      await store.sendListing('x', name: 'Ravi K', phone: '+91 98765 43210', whatsapp: true, sms: false);
      expect(store.contacts.single.email, 'ravi@example.com');
    });

    test('phone: India needs 10 digits, other countries 6 to 14', () {
      expect(PhoneCountry.valid('+91', '9876543210'), isTrue);
      expect(PhoneCountry.valid('+91', '987654321'), isFalse);
      expect(PhoneCountry.valid('+971', '501234567'), isTrue);
      expect(PhoneCountry.format('+91', '9876543210'), '+91 98765 43210');
      expect(PhoneCountry.format('+44', '7700900123'), '+44 7700900123');
    });

    test('visit days: Every day <-> all seven; any days can be picked; old saves still read', () {
      expect(Tk2Listing.toggleVisitDay({1, 2, 3, 4, 5, 6, 7}, 0), isEmpty);
      expect(Tk2Listing.toggleVisitDay(<int>{}, 0), {1, 2, 3, 4, 5, 6, 7});
      final six = Tk2Listing.toggleVisitDay({1, 2, 3, 4, 5, 6, 7}, 3);
      expect(Tk2Listing.visitDayText(six), '1,2,4,5,6,7');
      expect(Tk2Listing.visitDayText(Tk2Listing.toggleVisitDay(six, 3)), 'all');
      expect(Tk2Listing.visitDaySet('weekends'), {6, 7});
      final l = Tk2Listing.example.copyWith(visitDays: '2,4');
      expect(l.dayOpen(DateTime(2026, 11, 3)), isTrue); // Tuesday
      expect(l.dayOpen(DateTime(2026, 11, 4)), isFalse); // Wednesday
    });

    test('card heading is never empty (old properties without society)', () {
      final old = Tk2Listing(
        id: 'x',
        property: BrokerProperty(id: 'x', name: 'Green Villa', address: '', rooms: '2.5 BHK', floor: 1, totalFloors: 2, furnishing: 'Semi'),
      );
      // Never the broker's own label ("Green Villa"); falls back to rooms.
      expect(tk2CardHeading(old), '2.5 BHK property');
      expect(tk2CardHeading(old.copyWith(locality: 'Kondapur, Hyderabad')), 'Kondapur');
      expect(tk2CardHeading(old.copyWith(society: 'My Home Avatar', locality: 'Kondapur')), 'My Home Avatar');
      final bare = Tk2Listing(
        id: 'y',
        property: BrokerProperty(id: 'y', address: '', rooms: '1 BHK', floor: 0, totalFloors: 0, furnishing: 'Empty'),
      );
      expect(tk2CardHeading(bare), '1 BHK property');
    });

    test('public address drops house numbers', () {
      final l = Tk2Listing(
        id: 'z',
        property: BrokerProperty(
          id: 'z',
          name: 'VIVID',
          address: 'Flat 1203, 12th floor, Vivid Heights, Kondapur, Hyderabad',
          rooms: '3 BHK',
          floor: 12,
          totalFloors: 20,
          furnishing: 'Full',
        ),
      );
      expect(tk2PublicAddress(l), 'Vivid Heights, Kondapur, Hyderabad');
      expect(tk2CardHeading(l), 'Kondapur');
      expect(tk2CardHeading(l.copyWith(society: 'Vivid Heights')), 'Vivid Heights');
      expect(
        tk2PublicAddress(
          Tk2Listing(
            id: 'h',
            property: BrokerProperty(id: 'h', address: 'H.No 5-6-7, Road 3, Jubilee Hills', rooms: '2 BHK', floor: 0, totalFloors: 1, furnishing: 'Semi'),
          ),
        ),
        'Jubilee Hills',
      );
    });

    test('money in Indian style', () {
      expect(Tk2Store.money(150), '₹150');
      expect(Tk2Store.money(32000), '₹32,000');
      expect(Tk2Store.money(1250000), '₹12,50,000');
    });
  });

  testWidgets('welcome → example home → customer books → broker gets paid', (tester) async {
    tester.view.physicalSize = const Size(1800, 2532); // test font is wider than Roboto (4 tabs)
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
    // Home shows Design B only; door number never on cards.
    expect(find.text('Sri Sai Residency'), findsNothing); // no repeated society line
    expect(find.textContaining('2 BHK  ·  ₹32,000/m', findRichText: true), findsOneWidget); // B title
    expect(find.text('Sri Sai Residency, Madhapur, Hyderabad'), findsOneWidget); // address line
    expect(find.textContaining('Flat 402'), findsNothing);
    expect(find.text('Example'), findsNothing);

    await tester.ensureVisible(find.text('Sri Sai Residency, Madhapur, Hyderabad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sri Sai Residency, Madhapur, Hyderabad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only you')); // Design B page: private details tab
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

    // The wheel starts on the earliest time of the day picked: today if it is
    // still open, else tomorrow morning – either way within 24 hours, so the
    // visit code works when the broker types it.
    final now = DateTime.now();
    final day = Tk2Listing.example.earliestVisit(now, now) != null ? now : now.add(const Duration(days: 1));
    await tester.tap(find.text('${day.day}').first);
    await tester.pumpAndSettle();
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
    expect(find.text('₹150 held · add gate pass'), findsOneWidget);

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
    tester.view.physicalSize = const Size(1800, 2532); // test font is wider than Roboto (4 tabs)
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
    // Then the usual token, pre-filled with ₹15,000.
    expect(find.text('Your token amount'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Token amount'), '');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Type the token amount'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Token amount'), '20000');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(store.defaultToken, 20000);
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

  testWidgets('owner invite: closing the how-to-send sheet sends and saves nothing', (tester) async {
    tester.view.physicalSize = const Size(1800, 2532);
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
    await tester.enterText(find.byType(TextField).first, 'Flat 402');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send link to owner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Full name *'), 'Hari Rao');
    await tester.tap(find.text('WhatsApp').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Mobile number'), '+12025550123');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to Hari'));
    // The button spins while the sheet is open, so pump instead of settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Send the invite to Hari'), findsOneWidget);
    expect(find.text('+12025550123'), findsOneWidget);
    // Close without picking: still on the check screen, nothing sent.
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
    expect(find.text('Request sent'), findsNothing);
    expect(find.text('Send to Hari'), findsOneWidget);
    // Picking a way sends it.
    await tester.tap(find.text('Send to Hari'));
    // The button spins while the sheet is open, so pump instead of settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Copy link'));
    // Saving the onboarding uses real storage, so let it finish outside fake time.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Request sent'), findsOneWidget);
    expect(find.textContaining('Paste the invite to Hari'), findsOneWidget);
  });
}
