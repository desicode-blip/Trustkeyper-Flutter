import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/approved_auth_widgets.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import '../tk2/tk2_cloud.dart';
import '../tk2/tk2_deal.dart';
import '../tk2/tk2_deal_page.dart';
import '../tk2/tk2_link.dart';
import '../tk2/tk2_store.dart';
import 'tkweb_deal.dart';
import 'tkweb_owner.dart';
import 'tkweb_keyboard.dart';
import 'tkweb_session.dart';
import 'tkweb_tenant.dart';

/// What the WhatsApp link opened: a property (#p-…), an owner invite (#owner-…), or nothing.
sealed class TkwStart {
  const TkwStart();

  /// Reads the link once at start. The page never writes the address bar.
  static Future<TkwStart> fromFragment(String fragment) async {
    try {
      // Backend links: #l-<listing id> (tenant), #i-<invite id> (owner).
      final sync = Tk2Store.instance.sync;
      if (sync != null && fragment.startsWith('l-')) {
        final listing = await sync.openListing(fragment.substring(2));
        if (listing == null) return const TkwOpenHome(gone: true);
        await Tk2Store.instance.putListing(listing);
        return TkwOpenProperty(listing.id);
      }
      if (sync != null && fragment.startsWith('i-')) {
        final id = fragment.substring(2);
        return RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(id) ? TkwOpenOwner('', '', inviteId: id) : const TkwOpenHome(gone: true);
      }
      // Deal links from the broker's reminders: #d-ID (backend), #deal-… (demo).
      if (sync != null && fragment.startsWith('d-')) {
        final id = fragment.substring(2);
        final d = !TkwSession.instance.signedIn ? null : await sync.openDeal(id).catchError((Object _) => null);
        return TkwOpenDeal(id, d == null ? null : sync.roleIn(d), signedIn: d != null);
      }
      // Payload links belong to the local demo. Cloud builds only accept ids.
      if (sync != null) return TkwOpenHome(gone: fragment.isNotEmpty);
      if (fragment.startsWith('deal-')) {
        final j = jsonDecode(tk2Base32Decode(fragment.substring(5))) as Map<String, dynamic>;
        final role = j['r'] == 'owner' ? DealRole.owner : DealRole.tenant;
        final store = Tk2Store.instance;
        final d = Tk2Deal.fromJson(Map<String, dynamic>.from(j['d'] as Map));
        // This person's own part on this device is newer than the link's copy.
        final mine = store.deal(d.id)?.part(role);
        if (mine != null && mine.isNotEmpty) {
          d.part(role)
            ..clear()
            ..addAll(mine);
        }
        if (j['l'] is Map && store.listing(d.listingId) == null) await store.putListing(tk2ListingFromPublic(Map<String, dynamic>.from(j['l'] as Map)));
        await store.putDeal(d);
        TkwSession.instance.roles[d.id] = Tk2Deal.who(role);
        await TkwSession.instance.save();
        store.brokerName = d.brokerName;
        store.brokerPhone = d.brokerPhone;
        return TkwOpenDeal(d.id, role, signedIn: TkwSession.instance.signedIn);
      }
      if (fragment.startsWith('p-')) {
        final listing = tk2ListingFromPublic(jsonDecode(tk2Base32Decode(fragment.substring(2))) as Map<String, dynamic>);
        await Tk2Store.instance.putListing(listing);
        final j = jsonDecode(tk2Base32Decode(fragment.substring(2))) as Map<String, dynamic>;
        final broker = j['bn'] as String? ?? '';
        if (broker.isNotEmpty) Tk2Store.instance.brokerName = broker;
        Tk2Store.instance.brokerPhone = j['bp'] as String? ?? '';
        return TkwOpenProperty(listing.id);
      }
      if (fragment.startsWith('owner')) {
        final j = fragment.length > 6 ? jsonDecode(tk2Base32Decode(fragment.substring(6))) as Map<String, dynamic> : const <String, dynamic>{};
        return TkwOpenOwner(j['bn'] as String? ?? '', j['h'] as String? ?? '');
      }
      if (fragment == 'sample') {
        _sampleBroker();
        return const TkwOpenProperty('sample');
      }
    } catch (_) {
      // A broken link falls back to the start page.
    }
    return const TkwOpenHome();
  }
}

class TkwOpenProperty extends TkwStart {
  const TkwOpenProperty(this.listingId);
  final String listingId;
}

class TkwOpenOwner extends TkwStart {
  const TkwOpenOwner(this.brokerName, this.houseName, {this.inviteId});
  final String brokerName;
  final String houseName;
  final String? inviteId;
}

class TkwOpenDeal extends TkwStart {
  const TkwOpenDeal(this.dealId, this.role, {required this.signedIn});
  final String dealId;
  final DealRole? role;
  final bool signedIn;
}

class TkwOpenHome extends TkwStart {
  const TkwOpenHome({this.gone = false});

  /// The link's house or invite was removed.
  final bool gone;
}

/// Tenant and owner web app (opened from WhatsApp links). Same design system,
/// screens and slide transitions as the TrustKeyper apps.
class TkWebApp extends StatefulWidget {
  const TkWebApp({required this.start, super.key});
  final TkwStart start;

  @override
  State<TkWebApp> createState() => _TkWebAppState();
}

class _TkWebAppState extends State<TkWebApp> {
  late final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (context, state) => _first(widget.start))],
  );

  static Widget _first(TkwStart start) => switch (start) {
    TkwOpenProperty(:final listingId) => TkwProperty(listingId: listingId),
    TkwOpenOwner(:final brokerName, :final houseName, :final inviteId) => TkwOwnerInvite(brokerName: brokerName, houseName: houseName, inviteId: inviteId),
    TkwOpenDeal(:final dealId, :final role, :final signedIn) =>
      signedIn && role != null ? TkwDeal(dealId: dealId, role: role) : TkwDealStart(dealId: dealId, role: role),
    TkwOpenHome(:final gone) => TkwHome(gone: gone),
  };

  @override
  Widget build(BuildContext context) {
    const slide = CupertinoPageTransitionsBuilder();
    return MaterialApp.router(
      title: 'TrustKeyper',
      debugShowCheckedModeBanner: false,
      // Same slide-in for every new screen, on every phone and computer.
      theme: AppTheme.light.copyWith(pageTransitionsTheme: PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: slide})),
      routerConfig: router,
      builder: (context, child) => TkwFrame(child: child ?? const SizedBox()),
    );
  }
}

/// Phone-width column. On a computer the app sits in the middle on a soft background.
class TkwFrame extends StatelessWidget {
  const TkwFrame({required this.child, super.key});
  final Widget child;

  static const maxWidth = 460.0;

  @override
  Widget build(BuildContext context) {
    tkwWatchKeyboard();
    // The keyboard height from the browser becomes the normal keyboard inset,
    // so every screen's footer button rises with the keyboard.
    return ValueListenableBuilder<double>(
      valueListenable: tkwKeyboard,
      builder: (context, keyboard, _) {
        final base = MediaQuery.of(context);
        final mq = keyboard > base.viewInsets.bottom ? base.copyWith(viewInsets: base.viewInsets.copyWith(bottom: keyboard)) : base;
        return MediaQuery(
          data: mq,
          child: Builder(builder: (context) => _framed(context, mq)),
        );
      },
    );
  }

  Widget _framed(BuildContext context, MediaQueryData mq) {
    if (mq.size.width <= maxWidth + 40) return child;
    final width = min(mq.size.width, maxWidth);
    return ColoredBox(
      color: const Color(0xFFEEF2F7),
      child: Center(
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: AppColors.heading.withValues(alpha: 0.08), blurRadius: 40, offset: const Offset(0, 12))],
          ),
          child: MediaQuery(
            data: mq.copyWith(size: Size(width, mq.size.height)),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}

/// Opened without a link: pick a sample journey (also the demo reset).
class TkwHome extends StatelessWidget {
  const TkwHome({this.gone = false, super.key});
  final bool gone;

  @override
  Widget build(BuildContext context) => ApprovedAuthScaffold(
    showBack: false,
    header: const ApprovedLoginHero(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Welcome to TrustKeyper', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(
          gone ? 'This link is no longer active. Ask your broker for a new one.' : 'Tenants and house owners open these pages from a WhatsApp link.',
          style: const TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.muted),
        ),
        // Back on the plain address: this person's houses in progress.
        ListenableBuilder(
          listenable: Tk2Store.instance,
          builder: (context, _) {
            final mine = [
              for (final d in Tk2Store.instance.deals)
                if (TkwSession.instance.signedIn && TkwSession.instance.roleIn(d) != null && TkwSession.instance.roleIn(d) != DealRole.broker) d,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (mine.isNotEmpty) const SizedBox(height: 18),
                for (final d in mine)
                  Tk2DealCard(
                    deal: d,
                    role: TkwSession.instance.roleIn(d)!,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TkwDeal(dealId: d.id, role: TkwSession.instance.roleIn(d)!),
                        settings: const RouteSettings(name: 'deal'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        // Live site: no demo journeys, just the note above.
        if (!Tk2Cloud.on) ..._demo(context),
      ],
    ),
  );

  List<Widget> _demo(BuildContext context) => [
        const SizedBox(height: 22),
        OnbRow(
          icon: Icons.home_outlined,
          title: 'See a property',
          subtitle: 'What a tenant sees from the broker\'s link',
          onTap: () {
            _sampleBroker();
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TkwProperty(listingId: 'sample')));
          },
        ),
        const SizedBox(height: 12),
        OnbRow(
          icon: Icons.add_home_outlined,
          title: 'Add a house as the owner',
          subtitle: 'What an owner sees from the broker\'s invite',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const TkwOwnerInvite(brokerName: 'Suresh Kumar', houseName: ''),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: TextButton(
            onPressed: () async {
              await TkwSession.instance.reset();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('Demo reset. Start again.')));
              }
            },
            child: const Text('Start the demo again'),
          ),
        ),
        const SizedBox(height: 8),
        const OnbBanner('Demo build: codes, payments and e-sign are tests. Nothing is sent or charged.', kind: 'wait', icon: Icons.science_outlined),
  ];
}

/// Demo broker for the example property (real links carry the broker's name and number).
void _sampleBroker() {
  final store = Tk2Store.instance;
  if (store.brokerName.isEmpty) store.brokerName = 'Suresh Kumar';
  if (store.brokerPhone.isEmpty) store.brokerPhone = '+91 98480 12345';
}
