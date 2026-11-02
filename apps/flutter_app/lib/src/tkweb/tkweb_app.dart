import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/approved_auth_widgets.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import '../tk2/tk2_link.dart';
import '../tk2/tk2_store.dart';
import 'tkweb_owner.dart';
import 'tkweb_session.dart';
import 'tkweb_tenant.dart';

/// What the WhatsApp link opened: a property (#p-…), an owner invite (#owner-…), or nothing.
sealed class TkwStart {
  const TkwStart();

  /// Reads the link once at start. The page never writes the address bar.
  static Future<TkwStart> fromFragment(String fragment) async {
    try {
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
  const TkwOpenOwner(this.brokerName, this.houseName);
  final String brokerName;
  final String houseName;
}

class TkwOpenHome extends TkwStart {
  const TkwOpenHome();
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
    TkwOpenOwner(:final brokerName, :final houseName) => TkwOwnerInvite(brokerName: brokerName, houseName: houseName),
    TkwOpenHome() => const TkwHome(),
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
    final mq = MediaQuery.of(context);
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
  const TkwHome({super.key});

  @override
  Widget build(BuildContext context) => ApprovedAuthScaffold(
    showBack: false,
    header: const ApprovedLoginHero(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Welcome to TrustKeyper', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 8),
        const Text(
          'Tenants and house owners open these pages from a WhatsApp link.',
          style: TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.muted),
        ),
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
      ],
    ),
  );
}

/// Demo broker for the example property (real links carry the broker's name and number).
void _sampleBroker() {
  final store = Tk2Store.instance;
  if (store.brokerName.isEmpty) store.brokerName = 'Suresh Kumar';
  if (store.brokerPhone.isEmpty) store.brokerPhone = '+91 98480 12345';
}
