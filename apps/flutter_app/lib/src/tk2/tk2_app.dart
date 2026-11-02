import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/primary_button.dart';
import '../features/broker/presentation/broker_property_screen.dart';
import 'tk2_customer.dart';
import 'tk2_listing.dart';
import 'tk2_store.dart';
import 'tk2_visits.dart';
import 'tk2_widgets.dart';

/// TrustKeeper 2: the broker's property shelf. Add a property, share it in
/// one tap, customers book a paid visit (fee held until the visit happens).
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
  void initState() {
    super.initState();
    store.load();
  }

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'TrustKeeper 2',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    ),
    routerConfig: router,
  );
}

GoRouter buildTk2Router(Tk2Store store) => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => Tk2Gate(store: store)),
    GoRoute(
      path: '/add',
      builder: (context, state) => BrokerPropertyScreen(
        repository: Tk2PropertyRepository(store),
        startNew: true,
        showStepLabel: false,
        doneLabel: 'Next: rent and photos',
        onSelected: (property) => context.pushReplacement('/listing/${property.id}?new=1'),
      ),
    ),
    GoRoute(
      path: '/edit/:id',
      builder: (context, state) {
        final listing = store.listing(state.pathParameters['id']!);
        return BrokerPropertyScreen(
          repository: Tk2PropertyRepository(store),
          initialProperty: listing?.property,
          showStepLabel: false,
          doneLabel: 'Next: rent and photos',
          onSelected: (property) => context.pushReplacement('/listing/${property.id}'),
        );
      },
    ),
    GoRoute(
      path: '/listing/:id',
      builder: (context, state) => Tk2ListingForm(store: store, id: state.pathParameters['id']!, isNew: state.uri.queryParameters['new'] == '1'),
    ),
    GoRoute(path: '/p/:id', builder: (context, state) => Tk2PropertyDetail(store: store, id: state.pathParameters['id']!)),
    GoRoute(path: '/customer/:id', builder: (context, state) => Tk2CustomerPage(store: store, id: state.pathParameters['id']!)),
    GoRoute(path: '/customer/:id/book', builder: (context, state) => Tk2BookVisit(store: store, id: state.pathParameters['id']!)),
    GoRoute(path: '/booked/:visitId', builder: (context, state) => Tk2Booked(store: store, visitId: state.pathParameters['visitId']!)),
  ],
);

/// First open: ask the broker's name. Then the shelf.
class Tk2Gate extends StatelessWidget {
  const Tk2Gate({required this.store, super.key});
  final Tk2Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      if (!store.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: store.hasName ? Tk2Shell(key: const ValueKey('shell'), store: store) : Tk2Welcome(key: const ValueKey('welcome'), store: store),
      );
    },
  );
}

class Tk2Welcome extends StatefulWidget {
  const Tk2Welcome({required this.store, super.key});
  final Tk2Store store;

  @override
  State<Tk2Welcome> createState() => _Tk2WelcomeState();
}

class _Tk2WelcomeState extends State<Tk2Welcome> {
  final name = TextEditingController();
  final phone = TextEditingController();
  String? error;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  void _start() {
    if (name.text.trim().length < 2) {
      setState(() => error = 'Type your name');
      return;
    }
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty && digits.length != 10) {
      setState(() => error = 'Type the 10 digit number, or leave it empty');
      return;
    }
    widget.store.setBroker(name.text, digits.isEmpty ? '' : '+91 $digits');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        children: [
          Tk2Appear(
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(28)),
              child: const Icon(Icons.home_work_outlined, size: 44, color: AppColors.primaryDark),
            ),
          ),
          const SizedBox(height: 28),
          const Tk2Appear(
            index: 1,
            child: Tk2Title('Welcome to TrustKeeper', subtitle: 'Keep all your properties in one place. Share one in a tap. Get paid visits.'),
          ),
          const SizedBox(height: 32),
          Tk2Appear(
            index: 2,
            child: Column(
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() => error = null),
                  decoration: const InputDecoration(labelText: 'Your name'),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() => error = null),
                  decoration: const InputDecoration(labelText: 'Your phone (optional)', prefixText: '+91 ', helperText: 'Customers see it in the messages you share.'),
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 15)),
          ],
          const SizedBox(height: 28),
          PrimaryButton(label: 'Start', onPressed: _start),
        ],
      ),
    ),
  );
}

/// Home and Visits, with a bottom bar.
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
        final upcoming = store.upcoming.length;
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFD),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: tab == 0
                ? Tk2Home(key: const ValueKey('home'), store: store, onSeeVisits: () => setState(() => tab = 1))
                : Tk2Visits(key: const ValueKey('visits'), store: store, onShare: () => setState(() => tab = 0)),
          ),
          floatingActionButton: tab == 0
              ? FloatingActionButton.extended(
                  onPressed: () => context.push('/add'),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add),
                  label: const Text('Add property', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            backgroundColor: Colors.white,
            indicatorColor: AppColors.primarySoft,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Properties'),
              NavigationDestination(
                icon: Badge(isLabelVisible: upcoming > 0, label: Text('$upcoming'), child: const Icon(Icons.event_outlined)),
                selectedIcon: Badge(isLabelVisible: upcoming > 0, label: Text('$upcoming'), child: const Icon(Icons.event)),
                label: 'Visits',
              ),
            ],
          ),
        );
      },
    );
  }
}

class Tk2Home extends StatefulWidget {
  const Tk2Home({required this.store, required this.onSeeVisits, super.key});
  final Tk2Store store;
  final VoidCallback onSeeVisits;

  @override
  State<Tk2Home> createState() => _Tk2HomeState();
}

class _Tk2HomeState extends State<Tk2Home> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_sampleNotice);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sampleNotice());
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('Your first property is in. We removed the example.'),
    ));
  }

  Future<void> _editProfile() async {
    final store = widget.store;
    final name = TextEditingController(text: store.brokerName);
    final phone = TextEditingController(text: store.brokerPhone.replaceAll('+91 ', ''));
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + MediaQuery.of(sheet).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Your details', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
            const SizedBox(height: 16),
            TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your name')),
            const SizedBox(height: 14),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Your phone', prefixText: '+91 ')),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Save', onPressed: () => Navigator.pop(sheet, true)),
          ],
        ),
      ),
    );
    if (save == true && name.text.trim().length >= 2) {
      final digits = phone.text.replaceAll(RegExp(r'\D'), '');
      await store.setBroker(name.text, digits.length == 10 ? '+91 $digits' : '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final shown = store.shown;
    final sample = store.listings.isEmpty;
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Tk2Appear(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Namaste,', style: TextStyle(fontSize: 17, color: AppColors.muted)),
                          Text(store.brokerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 28, height: 34 / 28, fontWeight: FontWeight.w700, color: AppColors.heading)),
                        ],
                      ),
                    ),
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _editProfile,
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primarySoft,
                        child: Text(tk2Initials(store.brokerName), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            sliver: SliverToBoxAdapter(
              child: Tk2Appear(
                index: 1,
                child: Row(
                  children: [
                    _stat(sample ? '0' : '${store.listings.length}', sample || store.listings.length != 1 ? 'Properties' : 'Property', Icons.home_work_outlined, null),
                    const SizedBox(width: 10),
                    _stat('${store.upcoming.length}', 'Visits booked', Icons.event_outlined, widget.onSeeVisits),
                    const SizedBox(width: 10),
                    _stat(Tk2Store.money(store.heldTotal + store.releasedTotal), 'Visit fees', Icons.account_balance_wallet_outlined, widget.onSeeVisits),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 20, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Text(sample ? 'How it looks' : 'Your properties', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading)),
            ),
          ),
          if (sample)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Tk2Appear(
                  index: 2,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(16)),
                    child: const Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: AppColors.primaryDark),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This is an example. Add your first property and it goes away.',
                            style: TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.primaryDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
            sliver: SliverList.separated(
              itemCount: shown.length,
              separatorBuilder: (context, i) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                final l = shown[i];
                return Tk2Appear(
                  key: ValueKey(l.id),
                  index: i + 2,
                  child: Tk2PropertyCard(
                    listing: l,
                    visits: store.visitsFor(l.id).where((v) => v.upcoming).length,
                    onOpen: () => context.push('/p/${l.id}'),
                    onShare: () => showTk2Share(context, store, l),
                    onCustomerView: () => context.push('/customer/${l.id}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, IconData icon, VoidCallback? onTap) => Expanded(
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: AppColors.primaryDark),
              const SizedBox(height: 8),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.heading)),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
            ],
          ),
        ),
      ),
    ),
  );
}
