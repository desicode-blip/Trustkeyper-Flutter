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
import 'tk2_customer.dart';
import 'tk2_designs.dart';
import 'tk2_listing.dart';
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
  Widget build(BuildContext context) => MaterialApp.router(title: 'TrustKeeper 2', debugShowCheckedModeBanner: false, theme: AppTheme.light, routerConfig: router);
}

GoRouter buildTk2Router(Tk2Store store) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => SplashScreen(
        nextRoute: () async {
          await store.load();
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
      builder: (context, state) => Tk2Login(store: store, onBack: state.uri.queryParameters['from'] == 'onboarding' ? () => context.go('/onboarding?page=3') : null),
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

/// Same look as the main app's "Log in or sign up". In this test build it
/// keeps the name and number on the phone (no OTP yet).
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

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    setState(() {
      nameError = name.text.trim().length < 2 ? 'Type your name' : null;
      phoneError = PhoneCountry.valid(dial, digits) ? null : (dial == '+91' ? 'Enter a valid 10-digit mobile number' : 'Enter a valid phone number');
    });
    if (nameError != null || phoneError != null) return;
    await widget.store.setBroker(name.text, PhoneCountry.format(dial, digits));
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) => ApprovedAuthScaffold(
    showBack: false,
    header: ApprovedLoginHero(onBack: widget.onBack),
    bodyPadding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
    footer: PrimaryButton(label: 'Continue', icon: Icons.chevron_right, onPressed: _continue),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Log in or sign up', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 18),
        TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => nameError = null),
          decoration: InputDecoration(labelText: 'Your name', prefixIcon: const Icon(Icons.person_outline), errorText: nameError),
        ),
        const SizedBox(height: 14),
        ApprovedPhoneField(controller: phone, error: phoneError, dialCode: dial, onDialCodeChanged: (c) => setState(() => dial = c)),
      ],
    ),
  );
}

/// Main app's floating bottom bar: Home · Visits · Profile.
class Tk2Shell extends StatefulWidget {
  const Tk2Shell({required this.store, super.key});
  final Tk2Store store;

  @override
  State<Tk2Shell> createState() => _Tk2ShellState();
}

class _Tk2ShellState extends State<Tk2Shell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final profile = BrokerProfile(displayName: store.brokerName, email: '', phone: store.brokerPhone, approvalStatus: 'approved');
        final pages = [
          Tk2Home(store: store, profile: profile, onOpenProfile: () => setState(() => tab = 2), onOpenVisits: () => setState(() => tab = 1)),
          Tk2Visits(store: store, onShare: () => setState(() => tab = 0)),
          AccountProfilePanel(
            name: store.brokerName,
            phone: store.brokerPhone,
            role: 'broker',
            gateway: null,
            onLogout: () async {
              await store.setBroker('', '');
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
            labels: const ['Home', 'Visits', 'Profile'],
            icons: const ['home', 'records', 'profile'],
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
  const Tk2Home({required this.store, required this.profile, required this.onOpenProfile, required this.onOpenVisits, super.key});
  final Tk2Store store;
  final BrokerProfile profile;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenVisits;

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
    return ApprovedBrokerHome(
      profile: widget.profile,
      approvalPending: false,
      onOpenProfile: widget.onOpenProfile,
      showBankPrompt: false,
      // Onboarding in progress (owner link sent, papers, agreement) – same panel as the main app.
      savedDrafts: BrokerDraftSection(repository: _NoAgreementDrafts()),
      trailing: Badge(
        isLabelVisible: upcoming > 0,
        label: Text('$upcoming'),
        child: IconButton(
          tooltip: 'Visits',
          onPressed: widget.onOpenVisits,
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
                child: HomeTile(icon: 'bank', label: 'Fees ${Tk2Store.money(store.releasedTotal)}', onPressed: widget.onOpenVisits),
              ),
            ],
          ),
        ],
      ),
      below: [
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
        const SizedBox(height: 2),
        const Text('Two designs we are finalising: E and B. Tap to see the page.', style: TextStyle(fontSize: 14, color: AppColors.muted)),
        Tk2DesignShowcase(store: store),
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
