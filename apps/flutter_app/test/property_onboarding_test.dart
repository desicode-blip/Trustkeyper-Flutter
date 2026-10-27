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
}
