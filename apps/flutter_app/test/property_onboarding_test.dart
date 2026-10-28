import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trustkeyper/src/features/broker/data/property_onboarding.dart';
import 'package:trustkeyper/src/features/broker/presentation/onboarding_agreement_screens.dart';
import 'package:trustkeyper/src/features/broker/presentation/onboarding_house_screens.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fee summary reads in simple words', () {
    expect(const AgreementAnswers(feeType: 'days', feeValue: 15).feeSummary(30000), contains('15 days of rent'));
    expect(const AgreementAnswers(feeType: 'percent', feeValue: 5).feeSummary(30000), contains('₹ 1500'));
    expect(const AgreementAnswers(feeType: 'fixed', feeValue: 2000).feeSummary(30000), contains('every month'));
    expect(const AgreementAnswers(feeType: 'once', feeValue: 5000).feeSummary(30000), contains('one time'));
    expect(const AgreementAnswers(feeType: 'daysMonthly', feeValue: 3).feeSummary(30000), contains('3 days of rent every month'));
    expect(const AgreementAnswers(feeType: 'daysMonthly', feeValue: 3).feeSummary(30000), contains('₹ 3000'));
    expect(const AgreementAnswers(feeType: 'none').feeSummary(30000), contains('No fee'));
    expect(const AgreementAnswers(feeType: 'later').feeSummary(30000), contains('every deal'));
    expect(const AgreementAnswers(feeType: 'none').feeHasNoAmount, isTrue);
    expect(const AgreementAnswers(feeType: 'later').payWayText, 'Decided on every deal');
  });

  test('journey: papers, agreement, signing, ready', () async {
    final store = PropertyOnboardingStore();
    await store.load();
    final item = await store.create(
      ownerName: 'Ravi Kumar',
      channel: 'whatsapp',
      contact: '9876543210',
    );
    expect(item.phase, OnboardingPhase.papers);
    await store.testOwnerSendsPapers(item.id);
    expect(store.byId(item.id)!.needYouCount, greaterThan(0));
    expect(store.byId(item.id)!.allPapersDone, isFalse);
    await store.testFixAllPapers(item.id);
    expect(store.byId(item.id)!.allPapersDone, isTrue);
    await store.update(item.id, (i) => i.copyWith(phase: OnboardingPhase.preparing));
    await store.testDraftReady(item.id);
    expect(store.byId(item.id)!.phase, OnboardingPhase.review);
    await store.testOwnerAsksChange(item.id);
    expect(store.byId(item.id)!.waitingChanges, 1);
    await store.testNextPrintStep(item.id);
    await store.testNextPrintStep(item.id);
    expect(store.byId(item.id)!.phase, OnboardingPhase.signing);
    await store.testOwnerSigns(item.id);
    expect(store.byId(item.id)!.ownerSigned, isTrue);
  });

  test('same owner new house reuses ID proofs; new owner copies nothing', () async {
    final store = PropertyOnboardingStore();
    await store.load();
    final first = await store.create(ownerName: 'Ravi Kumar', channel: 'whatsapp', contact: '9876543210');
    await store.testOwnerSendsPapers(first.id);
    await store.testFixAllPapers(first.id);
    final old = store.byId(first.id)!;

    final same = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com', carryFrom: old);
    expect(same.paper(PaperKeys.aadhaar).status, PaperStatus.approved);
    expect(same.paper(PaperKeys.phone).status, PaperStatus.approved);
    expect(same.paper(PaperKeys.email).status, PaperStatus.approved);
    expect(same.paper(PaperKeys.address).status, PaperStatus.waiting);
    expect(same.paper(PaperKeys.bank).status, PaperStatus.waiting);

    final fresh = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'other@example.com');
    expect(fresh.paper(PaperKeys.aadhaar).status, PaperStatus.waiting);
    expect(fresh.paper(PaperKeys.phone).status, PaperStatus.waiting);
    expect(fresh.paper(PaperKeys.email).status, PaperStatus.approved);
  });

  test('requests survive an app restart', () async {
    final a = PropertyOnboardingStore();
    await a.load();
    final item = await a.create(ownerName: 'Sita Devi', channel: 'email', contact: 'sita@example.com');
    final b = PropertyOnboardingStore();
    await b.load();
    expect(b.byId(item.id)?.ownerName, 'Sita Devi');
  });

  testWidgets('house page shows papers and a Test only card', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'whatsapp', contact: '9876543210');
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (c, s) => PropertySetupScreen(id: item.id)),
      GoRoute(path: '/broker/onboarding/:id/paper/:key', builder: (c, s) => const SizedBox()),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Setting up'), findsOneWidget);
    await tester.dragUntilVisible(find.text('TEST ONLY'), find.byType(Scrollable).first, const Offset(0, -300));
    expect(find.text('TEST ONLY'), findsOneWidget);
    expect(find.text('Stop this request'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('signing rejects a wrong code', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'r@example.com');
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => SignScreen(id: item.id))]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send me a code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('Sign now'));
    await tester.pumpAndSettle();
    expect(find.text('This code is wrong. Try again.'), findsOneWidget);
    expect(store.byId(item.id)!.brokerSigned, isFalse);
    await tester.binding.setSurfaceSize(null);
  });

  test('two owners: own papers, own status, all must be approved and sign', () async {
    final store = PropertyOnboardingStore();
    await store.load();
    final item = await store.create(
      ownerName: 'Ravi Kumar',
      channel: 'email',
      contact: 'ravi@example.com',
      coOwners: [CoOwner(name: 'Sita Devi', channel: 'whatsapp', contact: '9123456780')],
    );
    expect(item.ownerCount, 2);
    expect(item.ownerFirstAt(1), 'Sita');
    // Sita's WhatsApp number is already known; Aadhaar and email are waiting.
    expect(item.paperAt(1, PaperKeys.phone).status, PaperStatus.approved);
    expect(item.paperAt(1, PaperKeys.aadhaar).status, PaperStatus.waiting);
    expect(item.allPapersDone, isFalse);

    await store.testOwnerSendsPapers(item.id, owner: 1);
    var now = store.byId(item.id)!;
    expect(now.ownerPapersDone(1), isTrue);
    expect(now.ownerPapersDone(0), isFalse);
    expect(now.allPapersDone, isFalse);

    // Owner 1 still has to give the house papers: all must be approved.
    await store.testFixAllPapers(item.id);
    now = store.byId(item.id)!;
    expect(now.allPapersDone, isTrue);

    // Remove / add edge cases.
    await store.addOwner(item.id, CoOwner(name: 'Mohan Lal', channel: 'email', contact: 'mohan@example.com'));
    now = store.byId(item.id)!;
    expect(now.ownerCount, 3);
    expect(now.allPapersDone, isFalse);
    await store.removeOwner(item.id, 2);
    expect(store.byId(item.id)!.allPapersDone, isTrue);
    await store.removeOwner(item.id, 0); // main owner cannot be removed
    expect(store.byId(item.id)!.ownerCount, 2);

    // Signing: the house is ready only when everybody signed.
    await store.update(item.id, (i) => i.copyWith(phase: OnboardingPhase.signing, brokerSigned: true));
    await store.testOwnerSigns(item.id, owner: 0);
    expect(store.byId(item.id)!.phase, OnboardingPhase.signing);
    await store.testOwnerSigns(item.id, owner: 1);
    expect(store.byId(item.id)!.phase, OnboardingPhase.ready);
  });

  test('an extra owner we already know keeps approved ID proofs; old saves still load', () async {
    final store = PropertyOnboardingStore();
    await store.load();
    final first = await store.create(
      ownerName: 'Sita Devi',
      channel: 'email',
      contact: 'sita@example.com',
    );
    await store.testOwnerSendsPapers(first.id);
    await store.testFixAllPapers(first.id);
    final second = await store.create(
      ownerName: 'Ravi Kumar',
      channel: 'email',
      contact: 'ravi@example.com',
      coOwners: [CoOwner(name: 'Sita Devi', channel: 'email', contact: 'sita@example.com')],
    );
    expect(second.paperAt(1, PaperKeys.aadhaar).status, PaperStatus.approved);
    final old = PropertyOnboarding.fromJson({
      ...second.toJson(),
      'coOwners': null,
      'otherOwners': ['Mohan Lal · +91 9988776655'],
    });
    expect(old.coOwners.single.channel, 'whatsapp');
    expect(old.coOwners.single.contact, '9988776655');
  });

  testWidgets('house page with two owners shows a tab for each owner', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(
      ownerName: 'Ravi Kumar',
      channel: 'whatsapp',
      contact: '9876543210',
      coOwners: [CoOwner(name: 'Sita Devi', channel: 'email', contact: 'sita@example.com')],
    );
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (c, s) => PropertySetupScreen(id: item.id)),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.textContaining('Owner 1'), findsOneWidget);
    expect(find.textContaining('Owner 2'), findsOneWidget);
    expect(find.text('House address'), findsOneWidget); // Owner 1 tab has house papers
    await tester.tap(find.textContaining('Owner 2'));
    await tester.pumpAndSettle();
    expect(find.text('House address'), findsNothing);
    expect(find.text('Aadhaar card'), findsOneWidget);
    expect(find.textContaining('House documents come from Ravi'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('agreement stage: read full agreement, call team, owner and broker', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com');
    await store.update(item.id, (i) => i.copyWith(phase: OnboardingPhase.preparing));
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (c, s) => PropertySetupScreen(id: item.id)),
      GoRoute(path: '/broker/onboarding/:id/agreement', builder: (c, s) => OwnerAgreementScreen(id: s.pathParameters['id']!)),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Documents'), findsOneWidget); // stage name
    expect(find.text('Call our agreement team'), findsOneWidget);
    expect(find.textContaining('papers'), findsNothing);
    await tester.tap(find.text('Read the full agreement'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Full agreement'), findsOneWidget);
    expect(find.text('Who signs'), findsOneWidget);
    expect(find.text('Ravi Kumar'), findsWidgets);
    expect(find.text('Broker'), findsWidgets);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('fee number box opens right under the picked option', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com');
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => AgreementQuestionsScreen(id: item.id))]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Percent of rent'));
    await tester.pumpAndSettle();
    final field = tester.getTopLeft(find.byType(TextField)).dy;
    expect(field, greaterThan(tester.getTopLeft(find.text('Percent of rent')).dy));
    expect(field, lessThan(tester.getTopLeft(find.text('Fixed amount')).dy));
    await tester.tap(find.text('No fee'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });
}
