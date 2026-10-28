import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_templates.dart';
import 'package:trustkeyper/src/features/broker/data/property_onboarding.dart';
import 'package:trustkeyper/src/features/broker/presentation/onboarding_agreement_screens.dart';
import 'package:trustkeyper/src/features/broker/presentation/onboarding_house_screens.dart';
import 'package:trustkeyper/src/features/broker/presentation/onboarding_start_screens.dart';

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
    expect(const AgreementAnswers(feeType: 'days', feeValue: 15, payWay: 'cut').payWayText, "We deduct it from the first month's rent");
    expect(const AgreementAnswers(feeType: 'percent', feeValue: 5, payWay: 'cut').payWayText, "We deduct it from every month's rent");
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
    // The agreement is not written yet, so there is nothing to read.
    expect(find.text('Read the full agreement'), findsNothing);
    expect(find.text('Read full agreement'), findsNothing);
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

  testWidgets('questions stage has one button only', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com');
    await store.update(item.id, (i) => i.copyWith(phase: OnboardingPhase.questions));
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => PropertySetupScreen(id: item.id))]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Next: collaboration details'), findsOneWidget);
    expect(find.text('Read the full agreement'), findsNothing);
    expect(find.text('Skip agreement'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('how the owner pays: one time fee only allows deduct; monthly allows deduct or direct', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com');
    await store.update(item.id, (i) => i.copyWith(phase: OnboardingPhase.questions));
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => AgreementQuestionsScreen(id: item.id))]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Days of rent, one time'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '15');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("We deduct it from the first month's rent"), findsOneWidget);
    expect(find.text('Owner pays you directly'), findsOneWidget);
    expect(find.text('Owner pays once, at signing'), findsOneWidget);
    expect(find.textContaining('Not available now'), findsNWidgets(2));
    await tester.tap(find.text('Owner pays you directly')); // cannot be picked
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('monthly fee: deduct from every month or direct, nothing else', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com');
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => AgreementQuestionsScreen(id: item.id))]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Percent of rent'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("We deduct it from every month's rent"), findsOneWidget);
    expect(find.text('Owner pays you directly'), findsOneWidget);
    expect(find.text('Owner pays once, at signing'), findsNothing);
    expect(find.textContaining('Not available now'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });

  test('changing a part after the first draft is remembered, can be undone, and asks the owner again', () async {
    final store = PropertyOnboardingStore();
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com');
    await store.update(item.id, (i) => i.copyWith(
      phase: OnboardingPhase.review,
      draftNo: 1,
      answers: const AgreementAnswers(feeType: 'percent', feeValue: 5, payWay: 'cut'),
    ));
    // Not sent yet: remembered as a change, same draft.
    await store.changeAgreementPart(item.id, 'fee', const AgreementAnswers(feeType: 'percent', feeValue: 4, payWay: 'cut'));
    var now = store.byId(item.id)!;
    expect(now.answers.feeValue, 4);
    expect(now.edits.single.group, 'fee');
    expect(now.draftNo, 1);
    // Changing it back to the first draft removes the change.
    await store.changeAgreementPart(item.id, 'fee', const AgreementAnswers(feeType: 'percent', feeValue: 5, payWay: 'cut'));
    expect(store.byId(item.id)!.edits, isEmpty);
    // Sent and agreed: a new draft, the owner must say yes again.
    await store.update(item.id, (i) => i.copyWith(draftSent: true, ownerAgreedFinal: true));
    await store.changeAgreementPart(item.id, 'dates', const AgreementAnswers(startDate: '2026-12-01', months: 6));
    now = store.byId(item.id)!;
    expect(now.draftNo, 2);
    expect(now.draftSent, isFalse); // Draft 2 waits for Send for signing
    expect(now.ownerAgreedFinal, isFalse);
    expect(now.versions.last.summary, contains('Start date and length'));
    await store.undoAgreementPart(item.id, 'dates');
    now = store.byId(item.id)!;
    expect(now.edits, isEmpty);
    expect(now.answers.months, 11);
    expect(now.draftNo, 2); // still the same unsent draft
    // Send Draft 2, then change again: Draft 3.
    await store.update(item.id, (i) => i.copyWith(draftSent: true));
    await store.changeAgreementPart(item.id, 'dates', const AgreementAnswers(startDate: '2026-12-01', months: 6));
    now = store.byId(item.id)!;
    expect(now.draftNo, 3);
    expect(now.draftSent, isFalse);
    await store.undoAgreementPart(item.id, 'dates');
    // Survives a restart.
    await store.changeAgreementPart(item.id, 'notes', const AgreementAnswers(notes: 'No pets'));
    final again = PropertyOnboardingStore();
    await again.load();
    expect(again.byId(item.id)!.edits.single.group, 'notes');
  });

  testWidgets('agreement reader: edit, what to change, change the fee, green change, undo', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com');
    await store.update(item.id, (i) => i.copyWith(
      phase: OnboardingPhase.review,
      draftNo: 1,
      answers: const AgreementAnswers(feeType: 'percent', feeValue: 5, payWay: 'cut', startDate: '2026-12-01'),
    ));
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (c, s) => OwnerAgreementScreen(id: item.id)),
      GoRoute(path: '/broker/onboarding/:id/edit', builder: (c, s) => AgreementEditScreen(id: s.pathParameters['id']!, part: s.uri.queryParameters['part'] ?? 'fee')),
      GoRoute(path: '/broker/onboarding/:id/sent', builder: (c, s) => AgreementSentScreen(id: s.pathParameters['id']!)),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Send for signing'), findsOneWidget);
    expect(find.textContaining('equivalent to 5% of the total monthly consideration', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('What to change?'), findsOneWidget);
    expect(find.text('Your fee'), findsOneWidget);
    expect(find.text('Start date and length'), findsOneWidget);
    await tester.tap(find.text('Your fee'));
    await tester.pumpAndSettle();
    expect(find.text('Editing agreement'), findsOneWidget);
    expect(find.text('Nothing changed yet'), findsOneWidget);
    expect(find.text('Back to agreement'), findsOneWidget);
    // Change 5 to 4 and save.
    await tester.enterText(find.byType(TextField), '4');
    await tester.pumpAndSettle();
    expect(find.text('Save and see agreement'), findsOneWidget);
    await tester.tap(find.text('Save and see agreement'));
    await tester.pumpAndSettle();
    expect(store.byId(item.id)!.answers.feeValue, 4);
    expect(find.text('1 change'), findsOneWidget);
    expect(find.text('Green = just changed'), findsOneWidget);
    // See all, then undo.
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.byId(item.id)!.answers.feeValue, 5);
    expect(store.byId(item.id)!.edits, isEmpty);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('edit screen: leaving with unsaved changes asks first; empty fee shows a red box', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com');
    await store.update(item.id, (i) => i.copyWith(
      phase: OnboardingPhase.review,
      draftNo: 1,
      answers: const AgreementAnswers(feeType: 'percent', feeValue: 5, payWay: 'cut', startDate: '2026-12-01'),
    ));
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => AgreementEditScreen(id: item.id, part: 'fee'))]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save and see agreement'));
    await tester.pumpAndSettle();
    expect(find.text('Type a number'), findsOneWidget);
    expect(find.text('Fix the red box to save'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(store.byId(item.id)!.answers.feeValue, 5); // nothing was saved
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('send confirm names every owner; sent screen says what happens next', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(
      ownerName: 'Ravi Kumar',
      channel: 'email',
      contact: 'ravi@example.com',
      coOwners: [CoOwner(name: 'Sita Devi', channel: 'email', contact: 'sita@example.com')],
    );
    await store.update(item.id, (i) => i.copyWith(phase: OnboardingPhase.review, draftNo: 1));
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (c, s) => OwnerAgreementScreen(id: item.id)),
      GoRoute(path: '/broker/onboarding/:id/sent', builder: (c, s) => AgreementSentScreen(id: s.pathParameters['id']!)),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send for signing'));
    await tester.pumpAndSettle();
    expect(find.text('Send to these 2 people for signing?'), findsOneWidget);
    await tester.tap(find.text('No, go back'));
    await tester.pumpAndSettle();
    expect(store.byId(item.id)!.draftSent, isFalse);
    await tester.tap(find.text('Send for signing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, send for signing'));
    await tester.pumpAndSettle();
    expect(store.byId(item.id)!.draftSent, isTrue);
    expect(find.text('Agreement sent'), findsOneWidget);
    expect(find.text('Go to home'), findsOneWidget);
    expect(find.text('Go to this house'), findsNothing);
    expect(find.text('What happens next'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('agreement ready: tick page, Next, then Send for signing + two read buttons', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com');
    await store.update(item.id, (i) => i.copyWith(phase: OnboardingPhase.preparing));
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => PropertySetupScreen(id: item.id))]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Making your agreement'), findsOneWidget);
    await store.testDraftReady(item.id);
    await tester.pumpAndSettle();
    expect(store.byId(item.id)!.agreementJustReady, isTrue);
    expect(find.text('Your agreement is ready'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsWidgets);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Send for signing'), findsNothing);
    expect(find.text('Read full agreement'), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Send for signing'), findsOneWidget);
    expect(find.text('Read full agreement'), findsOneWidget);
    expect(find.text('Read only key points'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('Versions'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('after sending: status first, Make changes, small links at the end', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com');
    await store.update(item.id, (i) => i.copyWith(
      phase: OnboardingPhase.review,
      draftNo: 2,
      draftSent: true,
      draftSentAt: DateTime.now().millisecondsSinceEpoch,
      answers: const AgreementAnswers(feeType: 'percent', feeValue: 5, payWay: 'cut', startDate: '2026-12-01'),
    ));
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => PropertySetupScreen(id: item.id))]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Draft 2 status'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Opened'), findsOneWidget);
    expect(find.text('Answer'), findsOneWidget);
    expect(find.text('Make changes'), findsOneWidget);
    expect(find.text('Read full agreement'), findsOneWidget);
    // Quiet links are below the status card.
    expect(tester.getTopLeft(find.text('Changes')).dy, greaterThan(tester.getTopLeft(find.text('Answer')).dy));
    expect(tester.getTopLeft(find.text('Versions')).dy, greaterThan(tester.getTopLeft(find.text('Answer')).dy));
    // Make changes opens the part picker (the new draft itself is covered by the store test).
    await tester.tap(find.text('Make changes'));
    await tester.pumpAndSettle();
    expect(find.text('What to change?'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('owner details: contact box only after Email or WhatsApp, cursor in it, right keypad', (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => const OnboardNewScreen())]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Owner 1 details'), findsOneWidget);
    // Only the name box at first.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Mobile number'), findsNothing);
    expect(find.text('Email Address'), findsNothing);
    // WhatsApp: number box appears, has the cursor, number keypad.
    await tester.tap(find.text('WhatsApp'));
    await tester.pumpAndSettle();
    final phone = tester.widget<TextField>(find.widgetWithText(TextField, 'Mobile number'));
    expect(phone.focusNode!.hasFocus, isTrue);
    expect(phone.keyboardType, TextInputType.number);
    // Email: email box instead, has the cursor, letters keypad with @.
    await tester.tap(find.text('Email · best'));
    await tester.pumpAndSettle();
    expect(find.text('Mobile number'), findsNothing);
    final mail = tester.widget<TextField>(find.widgetWithText(TextField, 'Email Address'));
    expect(mail.focusNode!.hasFocus, isTrue);
    expect(mail.keyboardType, TextInputType.emailAddress);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('waiting for papers: broker can add collaboration details now', (tester) async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com');
    await tester.binding.setSurfaceSize(const Size(440, 956));
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (c, s) => PropertySetupScreen(id: item.id)),
      GoRoute(path: '/broker/onboarding/:id/questions', builder: (c, s) => AgreementQuestionsScreen(id: s.pathParameters['id']!)),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(store.byId(item.id)!.phase, OnboardingPhase.papers);
    expect(find.text('Add collaboration details'), findsOneWidget);
    await tester.tap(find.text('Add collaboration details'));
    await tester.pumpAndSettle();
    expect(find.text('What is your fee?'), findsOneWidget);
    // Save details while papers are still coming: phase stays papers.
    await store.update(item.id, (i) => i.copyWith(answers: const AgreementAnswers(feeType: 'percent', feeValue: 5, payWay: 'cut', startDate: '2026-12-01')));
    router.go('/');
    await tester.pumpAndSettle();
    expect(store.byId(item.id)!.phase, OnboardingPhase.papers);
    await tester.scrollUntilVisible(find.text('Collaboration details'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Collaboration details'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Change collaboration details'), findsOneWidget);
    // Owner sends everything: one tap makes the agreement (no questions again).
    await store.testFixAllPapers(item.id);
    await tester.pumpAndSettle();
    expect(store.byId(item.id)!.allPapersDone, isTrue);
    await tester.tap(find.text('Make the agreement'));
    await tester.pump(const Duration(milliseconds: 600)); // spinner never settles
    expect(store.byId(item.id)!.phase, OnboardingPhase.preparing);
    await tester.binding.setSurfaceSize(null);
  });

  test('home notices: ready to review, then under review by the owner', () async {
    final store = PropertyOnboardingStore.instance;
    await store.load();
    final item = await store.create(ownerName: 'Ravi Kumar', channel: 'email', contact: 'ravi@example.com');
    await store.testDraftReady(item.id);
    expect(store.byId(item.id)!.agreementJustReady, isTrue);
    expect(store.byId(item.id)!.homeTitle, 'Agreement is ready');
    await store.update(item.id, (i) => i.copyWith(readyAck: true, draftSent: true, draftSentAt: DateTime.now().millisecondsSinceEpoch));
    final sent = store.byId(item.id)!;
    expect(sent.agreementJustReady, isFalse);
    expect(sent.underOwnerReview, isTrue);
    expect(sent.homeTitle, 'Agreement under review');
  });

  test('the right agreement template is picked from the fee and the owner', () {
    AgreementTemplate? pick(AgreementAnswers a, {bool nri = false, bool us = true}) =>
        AgreementTemplates.pick(a, isNri: nri, brokerIsTrustkeyper: us).template;
    expect(pick(const AgreementAnswers(feeType: 'percent', feeValue: 5)), AgreementTemplates.monthlyPercent);
    expect(pick(const AgreementAnswers(feeType: 'daysMonthly', feeValue: 3, payWay: 'cut')), AgreementTemplates.monthlyDays);
    expect(pick(const AgreementAnswers(feeType: 'days', feeValue: 15, payWay: 'cut')), AgreementTemplates.yearlyDays);
    expect(pick(const AgreementAnswers(feeType: 'percent', feeValue: 8), nri: true), AgreementTemplates.nri);
    expect(pick(const AgreementAnswers(feeType: 'percent', feeValue: 5), us: false), isNull);
    expect(pick(const AgreementAnswers(feeType: 'fixed', feeValue: 2000)), isNull);
    expect(pick(const AgreementAnswers(feeType: 'none')), isNull);
    // 3 days a month needs rent on our app.
    final clash = AgreementTemplates.pick(const AgreementAnswers(feeType: 'daysMonthly', feeValue: 3, payWay: 'direct'), isNri: false, brokerIsTrustkeyper: true);
    expect(clash.warning, isNotNull);
    expect(AgreementTemplates.yearlyDays.exportUrl.toString(), contains('12Duaqq-_kU3H_915GM3mLh0mIp2dbcYgniTnHQCjNZ0'));
    expect(AgreementTemplates.monthlyPercent.exportUrl.toString(), contains('alt=media')); // Word file in Drive
    expect(AgreementTemplates.monthlyDays.exportUrl, isNull); // link not shared yet
  });
}
