import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/routing/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/approved_navigation.dart';
import '../core/widgets/primary_button.dart';
import '../features/account/presentation/account_screens.dart';
import '../features/auth/presentation/approved_auth_widgets.dart';
import '../features/auth/presentation/auth_screens.dart';
import '../features/broker/data/agreement_progress_repository.dart';
import '../features/broker/data/broker_repository.dart';
import '../features/broker/presentation/broker_draft_cards.dart';
import '../features/broker/presentation/approved_broker_home.dart';
import '../features/broker/presentation/broker_property_screen.dart';
import '../tkweb/tkweb_auth.dart';
import 'tk2_cloud.dart';
import 'tk2_customer.dart';
import 'tk2_deal.dart';
import 'tk2_deal_page.dart';
import 'tk2_account.dart';
import 'tk2_designs.dart';
import 'tk2_invite.dart';
import 'tk2_token.dart';
import 'tk2_listing.dart';
import 'tk2_money.dart';
import 'tk2_notes.dart';
import 'tk2_store.dart';
import 'tk2_visits.dart';

/// TrustKeeper 2: the main app's splash, welcome carousel, login look and
/// broker home, with a property list, one-tap share and paid visits.
class TrustKeeper2App extends StatefulWidget {
  const TrustKeeper2App({this.store, super.key});
  final Tk2Store? store;

  @override
  State<TrustKeeper2App> createState() => _TrustKeeper2AppState();
}

class _TrustKeeper2AppState extends State<TrustKeeper2App> {
  late final Tk2Store store = widget.store ?? Tk2Store.instance;
  late final GoRouter router = buildTk2Router(store);

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(title: 'TrustKeeper 2', debugShowCheckedModeBanner: false, theme: AppTheme.light, routerConfig: router);
}

GoRouter buildTk2Router(Tk2Store store) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => SplashScreen(
        nextRoute: () async {
          await store.load();
          // Backend on: the login decides; the saved profile comes from Firestore.
          if (store.sync != null) {
            if (Tk2Cloud.uid == null) return '/onboarding';
            return await store.sync!.startBroker() ? '/home' : '/onboarding';
          }
          return store.hasName ? '/home' : '/onboarding';
        },
      ),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => OnboardingScreen(initialPage: int.tryParse(state.uri.queryParameters['page'] ?? '') ?? 0),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) =>
          Tk2Login(store: store, onBack: state.uri.queryParameters['from'] == 'onboarding' ? () => context.go('/onboarding?page=3') : null),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => Tk2Shell(store: store),
    ),
    // Name first, then the main app's "Onboard property" choice. "Add manually" saves
    // into TrustKeeper 2 and then asks rent and details.
    GoRoute(path: '/add', redirect: (context, state) => '/broker/property/manual'),
    GoRoute(path: '/broker', redirect: (context, state) => '/home'),
    // Rent agreements are not in TrustKeeper 2 yet.
    GoRoute(path: '/broker/start', redirect: (context, state) => '/home'),
    ...brokerPropertyRoutes(
      manual: (context, state) => BrokerPropertyScreen(
        repository: Tk2PropertyRepository(store),
        showStepLabel: false,
        askThings: false,
        startNew: true,
        askHowToAdd: true,
        ownerLink: store.ownerLink,
        inviteOwner: showTk2OwnerInvite,
        doneLabel: 'Next: rent',
        onSelected: (property) => context.pushReplacement('/listing/${property.id}?new=1'),
      ),
    ),
    GoRoute(
      path: '/edit/:id',
      builder: (context, state) => BrokerPropertyScreen(
        repository: Tk2PropertyRepository(store),
        initialProperty: store.listing(state.pathParameters['id']!)?.property,
        showStepLabel: false,
        askThings: false,
        doneLabel: 'Next: rent',
        onSelected: (property) => context.pushReplacement('/listing/${property.id}'),
      ),
    ),
    GoRoute(
      path: '/listing/:id',
      builder: (context, state) => Tk2ListingForm(store: store, id: state.pathParameters['id']!, isNew: state.uri.queryParameters['new'] == '1'),
    ),
    GoRoute(
      path: '/p/:id',
      builder: (context, state) => Tk2DesignDetail(store: store, id: state.pathParameters['id']!, design: state.uri.queryParameters['d'] ?? 'a'),
    ),
    GoRoute(
      path: '/customer/:id',
      builder: (context, state) => Tk2CustomerPage(store: store, id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/customer/:id/book',
      builder: (context, state) => Tk2BookVisit(store: store, id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/booked/:visitId',
      builder: (context, state) => Tk2Booked(store: store, visitId: state.pathParameters['visitId']!),
    ),
  ],
);

/// "Log in or sign up": phone number, then the 6-digit code. A known account
/// goes straight to Home with "Welcome back"; a new one is asked its name.
/// A new or different account starts on a clean phone (nothing left from
/// the last person).
class Tk2Login extends StatefulWidget {
  const Tk2Login({required this.store, this.onBack, super.key});
  final Tk2Store store;
  final VoidCallback? onBack;

  @override
  State<Tk2Login> createState() => _Tk2LoginState();
}

class _Tk2LoginState extends State<Tk2Login> {
  final name = TextEditingController();
  final phone = TextEditingController();
  String? nameError;
  String? phoneError;
  String dial = '+91';
  bool sending = false;

  /// Set once the code is right and the number is new: the name step.
  String? newNumber;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    setState(
      () => phoneError = PhoneCountry.valid(dial, digits) ? null : (dial == '+91' ? 'Enter a valid 10-digit mobile number' : 'Enter a valid phone number'),
    );
    if (phoneError != null) return;
    final number = PhoneCountry.format(dial, digits);
    final store = widget.store;
    final sync = store.sync;
    if (sync != null) {
      setState(() => sending = true);
      final failed = await Tk2Cloud.sendCode(number);
      if (!mounted) return;
      setState(() {
        sending = false;
        phoneError = failed;
      });
      if (failed != null) return;
    }
    // The code (in the demo build it is 123456). Android may verify on its own.
    var verified = sync != null && Tk2Cloud.uid != null;
    if (!verified) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (screen) => TkwOtp(
            destination: number,
            onVerified: () async {
              verified = true;
              Navigator.of(screen).pop();
            },
          ),
        ),
      );
    }
    if (!verified || !mounted) return;
    setState(() => sending = true);
    final sameAsBefore = store.brokerPhone == number && store.hasName;
    // Someone else (or a new account) on this phone: start clean.
    if (!sameAsBefore) await store.forgetDevice();
    final returning = sync != null ? await sync.startBroker() : sameAsBefore;
    if (!mounted) return;
    setState(() => sending = false);
    if (returning) return _home('Welcome back, ${tk2FirstName(store.brokerName)}');
    setState(() => newNumber = number);
  }

  Future<void> _saveName() async {
    setState(() => nameError = name.text.trim().length < 2 ? 'Type your name' : null);
    if (nameError != null) return;
    setState(() => sending = true);
    await widget.store.setBroker(name.text, newNumber!);
    if (!mounted) return;
    _home('Welcome, ${tk2FirstName(name.text)}');
  }

  /// Home, with a short greeting that goes away by itself.
  void _home(String hello) {
    final messenger = ScaffoldMessenger.of(context);
    context.go('/home');
    messenger.showSnackBar(SnackBar(content: Text(hello), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final askName = newNumber != null;
    return PopScope(
      canPop: !askName,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && askName) setState(() => newNumber = null);
      },
      child: ApprovedAuthScaffold(
        showBack: false,
        header: ApprovedLoginHero(onBack: askName ? () => setState(() => newNumber = null) : widget.onBack),
        bodyPadding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
        footer: PrimaryButton(label: 'Continue', icon: Icons.chevron_right, loading: sending, onPressed: sending ? null : (askName ? _saveName : _continue)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: askName
              ? [
                  Text('What is your name?', style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 6),
                  const Text(
                    'Tenants and owners see it on the links you send.',
                    style: TextStyle(fontSize: 15.5, height: 22 / 15.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    key: const ValueKey('name'),
                    controller: name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _saveName(),
                    onChanged: (_) => setState(() => nameError = null),
                    decoration: InputDecoration(labelText: 'Your name', prefixIcon: const Icon(Icons.person_outline), errorText: nameError),
                  ),
                ]
              : [
                  Text('Log in or sign up', style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 6),
                  const Text(
                    'We send a 6-digit code to this number.',
                    style: TextStyle(fontSize: 15.5, height: 22 / 15.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 18),
                  ApprovedPhoneField(controller: phone, error: phoneError, dialCode: dial, onDialCodeChanged: (c) => setState(() => dial = c)),
                ],
        ),
      ),
    );
  }
}

/// "Aman" from "Aman Maheshwari".
String tk2FirstName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.first.isEmpty ? 'there' : parts.first;
}

/// Main app's floating bottom bar: Home · Visits · Payments · Profile.
class Tk2Shell extends StatefulWidget {
  const Tk2Shell({required this.store, super.key});
  final Tk2Store store;

  @override
  State<Tk2Shell> createState() => _Tk2ShellState();
}

class _Tk2ShellState extends State<Tk2Shell> {
  int tab = 0;
  late final account = Tk2AccountGateway(widget.store);

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final profile = BrokerProfile(displayName: store.brokerName, email: '', phone: store.brokerPhone, approvalStatus: 'approved');
        final pages = [
          Tk2Home(
            store: store,
            profile: profile,
            onOpenProfile: () => setState(() => tab = 3),
            onOpenVisits: () => setState(() => tab = 1),
            onOpenPayments: () => setState(() => tab = 2),
          ),
          Tk2Visits(store: store, onShare: () => setState(() => tab = 0)),
          Tk2Payments(store: store),
          // The main app's profile, as is: My details, Bank, Language, Help,
          // Log out and Delete account, backed by the phone's store.
          AccountProfilePanel(
            name: store.brokerName,
            phone: store.brokerPhone,
            email: store.account['email'] as String? ?? '',
            bankName: store.account['bankName'] as String? ?? '',
            bankLast4: store.account['bankAccountLast4'] as String? ?? '',
            role: 'broker',
            gateway: account,
            extraRows: [
              (
                icon: 'money',
                title: 'Token amount',
                subtitle: '${Tk2Store.money(store.defaultToken)} · filled in for new properties',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (screen) => Tk2TokenScreen(store: store, onDone: () => Navigator.of(screen).pop()),
                  ),
                ),
              ),
            ],
            onSignedOut: () {
              if (context.mounted) context.go('/onboarding');
            },
          ),
        ];
        return Scaffold(
          body: SafeArea(
            child: IndexedStack(index: tab, children: pages),
          ),
          bottomNavigationBar: ApprovedBrokerNavigation(
            selectedIndex: tab,
            labels: const ['Home', 'Visits', 'Payments', 'Profile'],
            icons: const ['home', 'visits', 'payments', 'profile'],
            onSelected: (i) => setState(() => tab = i),
          ),
        );
      },
    );
  }
}

/// The main app's broker home, with "Add property" as the main action and
/// the property list below it.
class Tk2Home extends StatefulWidget {
  const Tk2Home({required this.store, required this.profile, required this.onOpenProfile, required this.onOpenVisits, required this.onOpenPayments, super.key});
  final Tk2Store store;
  final BrokerProfile profile;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenVisits;
  final VoidCallback onOpenPayments;

  @override
  State<Tk2Home> createState() => _Tk2HomeState();
}

class _Tk2HomeState extends State<Tk2Home> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_sampleNotice);
  }

  @override
  void dispose() {
    widget.store.removeListener(_sampleNotice);
    super.dispose();
  }

  void _sampleNotice() {
    final store = widget.store;
    if (!mounted || !store.sampleJustRemoved || store.listings.isEmpty || store.listings.first.rent == 0) return;
    store.clearSampleNotice();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your first property is in. We removed the example.')));
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final upcoming = store.upcoming.length;
    final unread = tk2UnreadNotes(store, DateTime.now());
    final earned = tk2MoneyTotals(store, tk2Ledger(store), DateTime.now()).received;
    return ApprovedBrokerHome(
      profile: widget.profile,
      approvalPending: false,
      onOpenProfile: widget.onOpenProfile,
      showBankPrompt: false,
      // Onboarding in progress (owner link sent, papers, agreement) – same panel as the main app.
      savedDrafts: BrokerDraftSection(repository: _NoAgreementDrafts()),
      trailing: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: IconButton(
          tooltip: 'Notifications',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Tk2Notifications(store: store))),
          icon: const Icon(Icons.notifications_none, color: AppColors.heading),
        ),
      ),
      actions: Column(
        children: [
          HomeTile(icon: 'house', label: 'Add property', primary: true, showArrow: true, onPressed: () => context.push('/add')),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: HomeTile(icon: 'tenants', label: upcoming > 0 ? 'Visits · $upcoming' : 'Visits', onPressed: widget.onOpenVisits),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: HomeTile(icon: 'bank', label: 'Fees ${Tk2Store.money(earned)}', onPressed: widget.onOpenPayments),
              ),
            ],
          ),
        ],
      ),
      below: [
        // Finalised houses: token paid (or asked for) → documents → agreement → keys.
        if (store.deals.isNotEmpty) ...[
          const SizedBox(height: 28),
          const Text(
            'Moving in',
            style: TextStyle(fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600, color: AppColors.heading),
          ),
          const SizedBox(height: 10),
          for (final d in store.deals.where((d) => d.ended == null || d == store.deals.first).take(5))
            Tk2DealCard(
              deal: d,
              role: DealRole.broker,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Tk2DealPage(store: store, dealId: d.id, role: DealRole.broker),
                ),
              ),
            ),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            Text(
              store.listings.isEmpty ? 'Example property' : 'Your properties',
              style: const TextStyle(fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600, color: AppColors.heading),
            ),
            const Spacer(),
            if (store.listings.isNotEmpty) Text('${store.listings.length}', style: const TextStyle(fontSize: 15, color: AppColors.muted)),
          ],
        ),
        if (store.listings.isEmpty) ...[
          const SizedBox(height: 4),
          const Text(
            'Add your first property and this example goes away.',
            style: TextStyle(fontSize: 14.5, height: 20 / 14.5, color: AppColors.muted),
          ),
        ],
        Tk2PropertyList(store: store),
      ],
    );
  }
}

/// TrustKeeper 2 has no saved rent-agreement drafts yet; only property
/// onboarding shows in the "Continue" panel.
class _NoAgreementDrafts implements AgreementProgressRepository {
  @override
  Stream<List<AgreementProgress>> watch() => Stream.value(const []);
  @override
  Future<AgreementProgress> load(String id) => Future.error(StateError('No drafts in TrustKeeper 2'));
  @override
  Future<int> save(AgreementProgress progress) async => 0;
  @override
  Future<void> remove(String id, int version) async {}
}
