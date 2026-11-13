import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import 'tk2_agreement.dart';
import 'tk2_cloud.dart';
import 'tk2_deal.dart';
import 'tk2_deal_move.dart';
import 'tk2_send.dart';
import 'tk2_status.dart';
import 'tk2_store.dart';

export 'tk2_deal_move.dart';

// Screens for stages 1–6 of a deal (token → payments) and the helpers every
// deal screen shares. Stages 7–9 are in tk2_deal_move.dart.

Future<T?> dealPush<T>(BuildContext context, Widget screen) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));

const dealDemoPay = OnbBanner('Demo build: test payment. No money moves.', kind: 'wait', icon: Icons.science_outlined);

/// Opens the screen for one task (see [DealTask]).
Future<void> openDealTask(
  BuildContext context,
  Tk2Store store,
  Tk2Deal d,
  DealRole role,
  String key, {
  Future<void> Function(BuildContext context, Tk2Deal deal)? onDocs,
}) async {
  final id = key.contains(':') ? key.split(':').last : '';
  Future<void> save(DealRole r) => store.saveDeal(d, r);
  final Widget? screen = switch (key.split(':').first) {
    'token' => DealPay(
      title: 'Block this house',
      intro: 'Pay a token amount and the house is kept for you. No one else can take it.',
      lines: [('Token amount', d.token)],
      onPaid: () {
        d.t.addAll({'tokenPaid': true, 'tokenAt': DateTime.now().millisecondsSinceEpoch});
        return save(DealRole.tenant);
      },
    ),
    'review' => DealReviewDocs(store: store, deal: d, who: id == 't' ? DealRole.tenant : DealRole.owner),
    'terms' => DealTerms(store: store, deal: d),
    'reply' => DealAgreement(store: store, deal: d, role: role),
    'stamp' => DealStamp(store: store, deal: d),
    'sign' => DealSign(store: store, deal: d, role: role),
    'pay' => DealPay(
      title: 'Pay to move in',
      intro: 'One payment for everything. The keys are handed over after this.',
      lines: [
        ('Security deposit', d.deposit),
        ('First month rent', d.rent),
        if (d.maintenance > 0) ('First month maintenance', d.maintenance),
        if (d.brokerage > 0) ('Brokerage', d.brokerage),
        ('Agreement fee · your half', Tk2Deal.feeShare),
        ('Token already paid', -d.token),
      ],
      onPaid: () {
        d.t.addAll({'paid': true, 'paidAt': DateTime.now().millisecondsSinceEpoch});
        return save(DealRole.tenant);
      },
    ),
    'fee' => DealPay(
      title: 'Pay before the keys',
      intro: 'One payment. The keys are handed over to the tenant after this.',
      lines: [
        if (d.o['brokPaid'] != true && d.ownerBrokerage > 0) ('Brokerage', d.ownerBrokerage),
        if (d.o['feePaid'] != true) ('Agreement fee · your half', Tk2Deal.feeShare),
      ],
      onPaid: () {
        final at = DateTime.now().millisecondsSinceEpoch;
        if (d.o['feePaid'] != true) d.o.addAll({'feePaid': true, 'feeAt': at});
        d.o.addAll({'brokPaid': true, 'paidAt': at});
        return save(DealRole.owner);
      },
    ),
    'feeEarly' => DealPay(
      title: 'Agreement fee',
      intro: 'The rent agreement costs ${Tk2Store.money(Tk2Deal.agreementFee)}: stamp paper, drafting and e-sign. You and the tenant pay half each.',
      lines: const [('Agreement fee · your half', Tk2Deal.feeShare)],
      onPaid: () {
        d.o.addAll({'feePaid': true, 'feeAt': DateTime.now().millisecondsSinceEpoch});
        return save(DealRole.owner);
      },
    ),
    'handover' => DealHandover(store: store, deal: d),
    'check' => DealCheck(store: store, deal: d),
    'edit' => DealEditApprove(store: store, deal: d, role: role),
    'quote' || 'approve' || 'fixed' || 'payrepair' => DealRepair(store: store, deal: d, role: role, id: id),
    'raise' => DealRaise(store: store, deal: d),
    'playbook' => DealPlaybook(store: store, deal: d),
    'soc' => DealSocietyStep(store: store, deal: d, role: role, index: int.parse(id)),
    _ => null,
  };
  if (key == 'docs') return onDocs?.call(context, d);
  if (screen != null) await dealPush(context, screen);
}

/// Take a photo or pick one (or a video). With the backend on it is uploaded
/// and the authenticated path comes back; in the demo build it is the local file.
Future<String?> dealPickPhoto(BuildContext context, Tk2Deal d, {bool video = false}) async {
  final source = kIsWeb
      ? ImageSource.gallery
      : await showModalBottomSheet<ImageSource>(
          context: context,
          showDragHandle: true,
          backgroundColor: Colors.white,
          builder: (sheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tk2SheetRow(
                    leading: const Icon(Icons.photo_camera_outlined, size: 28, color: AppColors.primaryDark),
                    title: video ? 'Record a video' : 'Take a photo',
                    onTap: () => Navigator.of(sheet).pop(ImageSource.camera),
                  ),
                  tk2SheetRow(
                    leading: const Icon(Icons.photo_library_outlined, size: 28, color: AppColors.primaryDark),
                    title: 'Choose from the phone',
                    onTap: () => Navigator.of(sheet).pop(ImageSource.gallery),
                  ),
                ],
              ),
            ),
          ),
        );
  if (source == null) return null;
  try {
    final picker = ImagePicker();
    final file = video
        ? await picker.pickVideo(source: source, maxDuration: const Duration(minutes: 5))
        : await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (file == null) return null;
    return Tk2Cloud.on ? await Tk2Cloud.uploadDealFile(d.id, file.path) : file.path;
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not add it. Try again.')));
    return null;
  }
}

/// A photo from a deal: a web address, or a file picked on this device.
/// Photos added on someone else's phone in the demo build show a placeholder.
class DealPhoto extends StatefulWidget {
  const DealPhoto(this.path, {this.size = 76, super.key});
  final String path;
  final double size;

  @override
  State<DealPhoto> createState() => _DealPhotoState();
}

class _DealPhotoState extends State<DealPhoto> {
  late Future<Uint8List>? bytes = _load();

  Future<Uint8List>? _load() => Tk2Cloud.isPrivateFile(widget.path) ? Tk2Cloud.readPrivateFile(widget.path) : null;

  @override
  void didUpdateWidget(DealPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path) bytes = _load();
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    const placeholder = Icon(Icons.image_outlined, color: AppColors.muted);
    Widget none(BuildContext _, Object _, StackTrace? _) => placeholder;
    final Widget photo;
    if (bytes != null) {
      photo = FutureBuilder<Uint8List>(
        future: bytes,
        builder: (context, snapshot) => snapshot.hasData ? Image.memory(snapshot.data!, fit: BoxFit.cover, errorBuilder: none) : placeholder,
      );
    } else if (!Tk2Cloud.on && (path.startsWith('http') || path.startsWith('blob:'))) {
      photo = Image.network(path, fit: BoxFit.cover, errorBuilder: none);
    } else if (!Tk2Cloud.on && !kIsWeb && path.isNotEmpty && path != 'demo') {
      photo = Image.file(File(path), fit: BoxFit.cover, errorBuilder: none);
    } else {
      photo = placeholder;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: widget.size,
        height: widget.size,
        color: AppColors.surfaceMuted,
        child: photo,
      ),
    );
  }
}

Future<void> saveTk2PrivateFile(BuildContext context, String path, {int maxBytes = 10 * 1024 * 1024}) async {
  try {
    final bytes = await Tk2Cloud.readPrivateFile(path, maxBytes: maxBytes);
    await FilePicker.saveFile(fileName: path.split('/').last, bytes: bytes);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the file. Try again.')));
  }
}

/// "Add photo" row that turns green once a photo is in.
class DealPhotoRow extends StatelessWidget {
  const DealPhotoRow({required this.title, required this.path, required this.onPick, this.subtitle, this.need = false, super.key});
  final String title;
  final String? subtitle;
  final String path;
  final bool need;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: OnbRow(
      icon: path.isEmpty ? Icons.add_a_photo_outlined : Icons.check,
      tone: path.isEmpty ? (need ? 'need' : 'info') : 'ok',
      title: title,
      subtitle: path.isEmpty ? (need ? 'Add this to continue' : subtitle) : 'Added · tap to change',
      trailing: path.isEmpty ? null : DealPhoto(path, size: 44),
      onTap: onPick,
    ),
  );
}

Widget dealHeading(String text) => Padding(
  padding: const EdgeInsets.only(top: 18, bottom: 10),
  child: Text(
    text,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading),
  ),
);

Widget dealText(String text) => Text(
  text,
  style: const TextStyle(fontSize: 15.5, height: 22 / 15.5, color: AppColors.body),
);

/// On/off line with plain words.
class DealSwitch extends StatelessWidget {
  const DealSwitch({required this.title, required this.value, required this.onChanged, this.subtitle, super.key});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    value: value,
    onChanged: onChanged,
    activeTrackColor: AppColors.primary,
    title: Text(title, style: const TextStyle(fontSize: 16, color: AppColors.heading)),
    subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(fontSize: 13.5, color: AppColors.muted)),
  );
}

// ------------------------------------------------------------------ paying

/// One payment screen for the token, the move-in payment, the owner's half of
/// the agreement fee and a repair. Test payment until Razorpay is connected.
class DealPay extends StatefulWidget {
  const DealPay({required this.title, required this.intro, required this.lines, required this.onPaid, super.key});
  final String title;
  final String intro;

  /// Label and rupees; a negative amount is something already paid.
  final List<(String, int)> lines;
  final Future<void> Function() onPaid;

  @override
  State<DealPay> createState() => _DealPayState();
}

class _DealPayState extends State<DealPay> {
  bool busy = false;

  int get total => widget.lines.fold(0, (sum, l) => sum + l.$2);

  Future<void> _pay() async {
    setState(() => busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 900)); // like a real gateway
    await widget.onPaid();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => OnbPage(
    title: widget.title,
    onBack: () => Navigator.of(context).maybePop(),
    footer: [PrimaryButton(label: 'Pay ${Tk2Store.money(total)}', icon: Icons.chevron_right, loading: busy, onPressed: busy || Tk2Cloud.on ? null : _pay)],
    children: [
      dealText(widget.intro),
      const SizedBox(height: 16),
      OnbCard(
        child: Column(
          children: [
            for (final l in widget.lines) OnbKeyValue(l.$1, l.$2 < 0 ? '− ${Tk2Store.money(-l.$2)}' : Tk2Store.money(l.$2), last: widget.lines.length == 1),
            if (widget.lines.length > 1) OnbKeyValue('To pay now', Tk2Store.money(total), last: true),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (Tk2Cloud.on)
        const OnbBanner('Payments are unavailable during the staging pilot.', kind: 'wait', icon: Icons.info_outline)
      else
        dealDemoPay,
    ],
  );
}

/// What the tenant paid to move in.
class DealReceipt extends StatelessWidget {
  const DealReceipt({required this.deal, required this.role, super.key});
  final Tk2Deal deal;
  final DealRole role;

  @override
  Widget build(BuildContext context) => OnbPage(
    title: 'Payments',
    subtitle: deal.title,
    onBack: () => Navigator.of(context).maybePop(),
    children: [
      const OnbBanner('Paid', kind: 'ok', icon: Icons.check_circle_outline),
      const SizedBox(height: 14),
      OnbCard(
        child: Column(
          children: [
            OnbKeyValue('Token', Tk2Store.money(deal.token)),
            OnbKeyValue('Security deposit', Tk2Store.money(deal.deposit)),
            OnbKeyValue('First month rent', Tk2Store.money(deal.rent + deal.maintenance)),
            if (deal.brokerage > 0 && role != DealRole.owner) OnbKeyValue('Brokerage', Tk2Store.money(deal.brokerage)),
            OnbKeyValue('Agreement fee', '${Tk2Store.money(Tk2Deal.feeShare)} tenant · ${Tk2Store.money(Tk2Deal.feeShare)} owner', last: true),
          ],
        ),
      ),
    ],
  );
}

/// Broker: the deal broke before signing. Who backed out decides the token.
Future<void> showDealEnd(BuildContext context, Tk2Store store, Tk2Deal d) async {
  final by = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheet) {
      Widget row(String by, String title) {
        final s = Tk2Deal.tokenSplit(d.token, by);
        final paid = d.t['tokenPaid'] == true;
        return tk2SheetRow(
          leading: Icon(by == 'owner' ? Icons.home_work_outlined : Icons.person_off_outlined, size: 28, color: AppColors.primaryDark),
          title: title,
          sub: !paid
              ? 'No token was paid'
              : by == 'owner'
              ? '${Tk2Store.money(s.tenant)} token goes back to the tenant'
              : 'Token is kept: ${Tk2Store.money(s.owner)} to the owner, ${Tk2Store.money(s.broker)} to you',
          onTap: () => Navigator.of(sheet).pop(by),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tk2SheetTitle('Who backed out?', 'The house goes back on the market.'),
              row('owner', 'The owner backed out'),
              row('tenant', 'The tenant backed out'),
            ],
          ),
        ),
      );
    },
  );
  if (by == null || !context.mounted) return;
  final sure = await onbConfirm(
    context,
    title: 'End this deal?',
    message: 'This cannot be undone. ${d.nameOf(DealRole.tenant)} and ${d.nameOf(DealRole.owner)} are told.',
    yes: 'End the deal',
    danger: true,
  );
  if (sure) await store.endDeal(d, by);
}

// --------------------------------------------------------------- documents

/// Broker: what one person sent. Approve, or ask again with a note.
class DealReviewDocs extends StatefulWidget {
  const DealReviewDocs({required this.store, required this.deal, required this.who, super.key});
  final Tk2Store store;
  final Tk2Deal deal;
  final DealRole who;

  @override
  State<DealReviewDocs> createState() => _DealReviewDocsState();
}

class _DealReviewDocsState extends State<DealReviewDocs> {
  final note = TextEditingController();
  bool asking = false;
  String? error;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Tk2Deal get d => widget.deal;

  Future<void> _answer(bool ok) async {
    final who = Tk2Deal.who(widget.who);
    if (!ok && note.text.trim().length < 3) return setState(() => error = 'Say what to send again');
    d.b['docsOk'] = {...Map<String, dynamic>.from(d.b['docsOk'] as Map? ?? const {}), who: ok};
    if (!ok) {
      d.b['redo'] = {
        ...Map<String, dynamic>.from(d.b['redo'] as Map? ?? const {}),
        who: {'note': note.text.trim(), 'at': DateTime.now().millisecondsSinceEpoch},
      };
    }
    await widget.store.saveDeal(d, DealRole.broker);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final part = d.part(widget.who);
    final docs = Map<String, dynamic>.from(part['docs'] as Map? ?? const {});
    final details = Map<String, dynamic>.from(part['details'] as Map? ?? const {});
    final first = d.nameOf(widget.who).split(' ').first;
    return OnbPage(
      title: "$first's documents",
      subtitle: widget.who == DealRole.tenant ? 'Tenant' : 'Owner',
      onBack: () => Navigator.of(context).maybePop(),
      footer: [
        PrimaryButton(label: asking ? 'Ask $first again' : 'Documents are fine', icon: asking ? null : Icons.check, onPressed: () => _answer(!asking)),
        if (!asking) ...[const SizedBox(height: 10), OnbSecondaryButton(label: 'Something is wrong', onPressed: () => setState(() => asking = true))],
      ],
      children: [
        if (docs.isEmpty) const OnbBanner('Documents received.', kind: 'ok', icon: Icons.check_circle_outline),
        for (final e in docs.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OnbRow(
              icon: Icons.description_outlined,
              title: e.key,
              subtitle: Tk2Cloud.isPrivateFile('${e.value}') ? 'Tap to save' : 'Received',
              tone: 'ok',
              chevron: Tk2Cloud.isPrivateFile('${e.value}'),
              onTap: Tk2Cloud.isPrivateFile('${e.value}') ? () => saveTk2PrivateFile(context, '${e.value}') : null,
            ),
          ),
        if (details.isNotEmpty) ...[
          const SizedBox(height: 6),
          OnbCard(
            child: Column(
              children: [
                for (final (i, e) in details.entries.where((e) => '${e.value}'.isNotEmpty).indexed)
                  OnbKeyValue(
                    const {'email': 'Email', 'address': 'Current address', 'work': 'Work', 'people': 'People moving in'}[e.key] ?? e.key,
                    '${e.value}',
                    last: i == details.entries.where((e) => '${e.value}'.isNotEmpty).length - 1,
                  ),
              ],
            ),
          ),
        ],
        if (!Tk2Cloud.on) ...[
          const SizedBox(height: 12),
          const OnbBanner('Demo build: the files stay on their phone. You see them here once the backend is on.', kind: 'wait', icon: Icons.science_outlined),
        ],
        if (asking) ...[
          const SizedBox(height: 16),
          OnbTextField(
            label: 'What should $first send again?',
            controller: note,
            maxLines: 3,
            capitalization: TextCapitalization.sentences,
            error: error,
            onChanged: (_) => setState(() => error = null),
          ),
        ],
      ],
    );
  }
}

// --------------------------------------------------------------- agreement

const _itemIdeas = [
  'Fans and lights',
  'Geyser',
  'Air conditioner',
  'Wardrobe',
  'Chimney',
  'Stove',
  'Fridge',
  'Washing machine',
  'Bed',
  'Sofa',
  'Dining table',
  'TV',
  'Water purifier',
  'Shoe rack',
  'Mirror',
];

/// Broker: fill the deal terms once; the app writes the agreement from
/// TrustKeyper's template. Sending again makes a new version.
class DealTerms extends StatefulWidget {
  const DealTerms({required this.store, required this.deal, super.key});
  final Tk2Store store;
  final Tk2Deal deal;

  @override
  State<DealTerms> createState() => _DealTermsState();
}

class _DealTermsState extends State<DealTerms> {
  late final Map<String, dynamic> t = widget.deal.defaultTerms(DateTime.now());
  late final items = [...widget.deal.items];
  late final c = {
    for (final k in ['address', 'ownerAddress', 'rent', 'deposit', 'months', 'lockIn', 'notice', 'dueDay', 'lateFee', 'refundDays', 'people'])
      k: TextEditingController(text: '${t[k] ?? ''}' == '0' && k == 'lateFee' ? '' : '${t[k] ?? ''}'),
  };
  late final owner = TextEditingController(text: widget.deal.ownerName);
  final other = TextEditingController();
  final note = TextEditingController();
  final bad = <String>{};

  Tk2Deal get d => widget.deal;

  @override
  void initState() {
    super.initState();
    final l = widget.store.listing(d.listingId);
    if (c['address']!.text.isEmpty && l != null) c['address']!.text = l.fullAddress;
  }

  @override
  void dispose() {
    for (final x in [...c.values, owner, other, note]) {
      x.dispose();
    }
    super.dispose();
  }

  int _n(String k) => int.tryParse(c[k]!.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  Map<String, dynamic> _terms() => {
    ...t,
    'address': c['address']!.text.trim(),
    'ownerAddress': c['ownerAddress']!.text.trim(),
    for (final k in ['rent', 'deposit', 'months', 'lockIn', 'notice', 'dueDay', 'lateFee', 'refundDays', 'people']) k: _n(k),
  };

  bool _check() {
    bad
      ..clear()
      ..addAll({
        if (c['address']!.text.trim().length < 8) 'address',
        if (owner.text.trim().length < 2) 'owner',
        if (_n('rent') <= 0) 'rent',
        if (_n('months') < 1 || _n('months') > 36) 'months',
        if (_n('dueDay') < 1 || _n('dueDay') > 28) 'dueDay',
        if (_n('people') < 1) 'people',
        if (items.isEmpty) 'items',
      });
    setState(() {});
    return bad.isEmpty;
  }

  /// A copy with the form's values, for the preview (nothing is saved).
  Tk2Deal _draft() => Tk2Deal.fromJson(d.toJson())
    ..ownerName = owner.text.trim()
    ..b['terms'] = _terms()
    ..b['items'] = [
      for (final i in items) {'n': i.name, 'c': i.count},
    ];

  Future<void> _send() async {
    if (!_check()) return;
    d.ownerName = owner.text.trim();
    d.sendVersion(_terms(), items, note: note.text.trim());
    await widget.store.saveDeal(d, DealRole.broker);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _field(String k, String label, {TextInputType keyboard = TextInputType.number, String? error, String? prefix, int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: OnbTextField(
      label: label,
      controller: c[k]!,
      keyboard: keyboard,
      prefix: prefix,
      maxLines: lines,
      formatters: keyboard == TextInputType.number ? [FilteringTextInputFormatter.digitsOnly] : null,
      capitalization: keyboard == TextInputType.number ? TextCapitalization.none : TextCapitalization.words,
      error: bad.contains(k) ? error : null,
      onChanged: (_) => setState(() => bad.remove(k)),
    ),
  );

  void _toggle(String name) => setState(() {
    bad.remove('items');
    final at = items.indexWhere((i) => i.name == name);
    at < 0 ? items.add((name: name, count: 1)) : items.removeAt(at);
  });

  void _count(int at, int by) => setState(() {
    final n = (items[at].count + by).clamp(0, 99);
    n == 0 ? items.removeAt(at) : items[at] = (name: items[at].name, count: n);
  });

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(t['start'] as String? ?? '') ?? DateTime.now();
    final asked = [
      for (final r in [DealRole.tenant, DealRole.owner])
        if (d.replyNote(r).isNotEmpty) '${d.nameOf(r).split(' ').first} asked: ${d.replyNote(r)}',
    ];
    return OnbPage(
      title: d.version == 0 ? 'Write the agreement' : 'Change the agreement',
      subtitle: d.version == 0 ? 'Fill these once. We write the agreement for you.' : 'Sending makes version ${d.version + 1}. Both reply again.',
      onBack: () => Navigator.of(context).maybePop(),
      footer: [
        PrimaryButton(label: 'Send to owner and tenant', icon: Icons.chevron_right, onPressed: _send),
        const SizedBox(height: 10),
        OnbSecondaryButton(
          label: 'See the agreement first',
          onPressed: () {
            if (_check()) dealPush(context, DealAgreementText(deal: _draft()));
          },
        ),
      ],
      children: [
        for (final a in asked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OnbBanner(a, kind: 'need', icon: Icons.edit_note),
          ),
        dealHeading('House and owner'),
        _field('address', 'Full address of the house *', keyboard: TextInputType.streetAddress, lines: 3, error: 'Type the full address with flat number'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OnbTextField(
            label: 'Owner name, as on Aadhaar *',
            controller: owner,
            capitalization: TextCapitalization.words,
            error: bad.contains('owner') ? "Type the owner's name" : null,
            onChanged: (_) => setState(() => bad.remove('owner')),
          ),
        ),
        _field('ownerAddress', "Owner's address", keyboard: TextInputType.streetAddress, lines: 2),
        dealHeading('Money'),
        _field('rent', 'Rent / month *', prefix: '₹ ', error: 'Type the rent'),
        _field('deposit', 'Security deposit', prefix: '₹ '),
        _field('dueDay', 'Rent due by (day of the month) *', error: 'Type a day from 1 to 28'),
        _field('lateFee', 'Late fee per day (leave empty for none)', prefix: '₹ '),
        dealHeading('Dates'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OnbRow(
            icon: Icons.event_outlined,
            title: 'Start date',
            subtitle: tk2DateOf(start),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: start,
                firstDate: DateTime.now().subtract(const Duration(days: 31)),
                lastDate: DateTime.now().add(const Duration(days: 366)),
              );
              if (picked != null) setState(() => t['start'] = picked.toIso8601String().substring(0, 10));
            },
          ),
        ),
        _field('months', 'How many months *', error: 'Type 1 to 36 months'),
        _field('lockIn', 'Minimum stay (months)'),
        _field('notice', 'Notice to leave (months)'),
        dealHeading('When the tenant leaves'),
        _field('refundDays', 'Deposit comes back within (days)'),
        DealSwitch(title: 'Painting is deducted from the deposit', value: t['paint'] == true, onChanged: (v) => setState(() => t['paint'] = v)),
        DealSwitch(title: 'Tenant cleans the house, or pays for it', value: t['clean'] == true, onChanged: (v) => setState(() => t['clean'] = v)),
        dealHeading('Who lives here'),
        _field('people', 'How many people at most *', error: 'Type how many people'),
        DealSwitch(title: 'Pets allowed', value: t['pets'] == true, onChanged: (v) => setState(() => t['pets'] = v)),
        dealHeading('Things in the house'),
        dealText('Tap what the owner gives with the house. The tenant checks each one at handover.'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in _itemIdeas)
              FilterChip(
                label: Text(name),
                selected: items.any((i) => i.name == name),
                onSelected: (_) => _toggle(name),
                showCheckmark: false,
                selectedColor: AppColors.primarySoft,
                side: BorderSide(color: items.any((i) => i.name == name) ? AppColors.primary : AppColors.border),
              ),
          ],
        ),
        if (bad.contains('items'))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Pick at least one thing', style: TextStyle(fontSize: 14, color: AppColors.error)),
          ),
        const SizedBox(height: 12),
        for (final (at, i) in items.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(i.name, style: const TextStyle(fontSize: 16, color: AppColors.heading)),
                ),
                IconButton(
                  tooltip: 'One less ${i.name}',
                  onPressed: () => _count(at, -1),
                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.primaryDark),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${i.count}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.heading),
                  ),
                ),
                IconButton(
                  tooltip: 'One more ${i.name}',
                  onPressed: () => _count(at, 1),
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.primaryDark),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OnbTextField(label: 'Something else', controller: other, capitalization: TextCapitalization.sentences),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: 'Add',
              onPressed: () {
                final name = other.text.trim();
                if (name.isEmpty || items.any((i) => i.name.toLowerCase() == name.toLowerCase())) return;
                other.clear();
                _toggle(name);
              },
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (d.version > 0) ...[
          dealHeading('What did you change?'),
          OnbTextField(label: 'A short note for the owner and tenant', controller: note, maxLines: 2, capitalization: TextCapitalization.sentences),
        ],
      ],
    );
  }
}

/// The agreement for everyone: main terms, what changed, who said yes, and
/// (tenant and owner) "Looks good" or "Ask for a change".
class DealAgreement extends StatefulWidget {
  const DealAgreement({required this.store, required this.deal, required this.role, super.key});
  final Tk2Store store;
  final Tk2Deal deal;
  final DealRole role;

  @override
  State<DealAgreement> createState() => _DealAgreementState();
}

class _DealAgreementState extends State<DealAgreement> {
  Tk2Deal get d => widget.deal;
  bool get canReply => widget.role != DealRole.broker && d.replyOk(widget.role) == null && d.ended == null;

  Future<void> _reply(bool ok, [String note = '']) async {
    d.part(widget.role)['reply'] = {'v': d.version, 'ok': ok, if (!ok) 'note': note};
    await widget.store.saveDeal(d, widget.role);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _ask() async {
    final note = TextEditingController();
    String? error;
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, set) => Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tk2SheetTitle('Ask for a change', 'The broker changes it and sends it again.'),
              OnbTextField(
                label: 'What should change?',
                controller: note,
                maxLines: 3,
                capitalization: TextCapitalization.sentences,
                error: error,
                onChanged: (_) => set(() => error = null),
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                label: 'Send to the broker',
                onPressed: () => note.text.trim().length < 3 ? set(() => error = 'Say what should change') : Navigator.of(sheet).pop(note.text.trim()),
              ),
            ],
          ),
        ),
      ),
    );
    if (text != null) await _reply(false, text);
  }

  Widget _who(DealRole r) {
    final ok = d.replyOk(r);
    final name = r == widget.role ? 'You' : d.nameOf(r);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OnbRow(
        icon: d.signed(r) ? Icons.draw_outlined : (ok == true ? Icons.check : (ok == false ? Icons.edit_note : Icons.hourglass_top)),
        tone: ok == true ? 'ok' : (ok == false ? 'need' : 'wait'),
        chevron: false,
        title: '$name · ${Tk2Deal.who(r)}',
        subtitle: d.signed(r) ? 'Signed' : (ok == true ? 'Said yes' : (ok == false ? 'Asked for a change: ${d.replyNote(r)}' : 'Has not replied yet')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = d.terms;
    final labels = Tk2Deal.termLabels.keys.toList();
    return OnbPage(
      title: 'Rent agreement',
      subtitle: 'Version ${d.version} · ${d.title}',
      onBack: () => Navigator.of(context).maybePop(),
      footer: [
        if (canReply) ...[
          PrimaryButton(label: 'Looks good', icon: Icons.check, onPressed: () => _reply(true)),
          const SizedBox(height: 10),
          OnbSecondaryButton(label: 'Ask for a change', onPressed: _ask),
        ],
      ],
      children: [
        if (d.changes.isNotEmpty || (d.b['note'] as String? ?? '').isNotEmpty) ...[
          OnbCard(
            color: AppColors.warningSoft,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'What changed in this version',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.warning),
                ),
                const SizedBox(height: 6),
                if ((d.b['note'] as String? ?? '').isNotEmpty) Text(d.b['note'] as String, style: const TextStyle(fontSize: 15, color: AppColors.body)),
                for (final c in d.changes)
                  Text(
                    '• $c',
                    style: const TextStyle(fontSize: 15, height: 22 / 15, color: AppColors.body),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        OnbCard(
          child: Column(
            children: [
              OnbKeyValue('House', '${t['address'] ?? d.title}'),
              OnbKeyValue('Owner', d.nameOf(DealRole.owner)),
              OnbKeyValue('Tenant', d.nameOf(DealRole.tenant)),
              for (final k in labels)
                if (k != 'lateFee' || (t[k] as num? ?? 0) > 0)
                  OnbKeyValue(Tk2Deal.termLabels[k]!, k == 'start' ? tk2DateOf(DateTime.tryParse('${t[k]}') ?? DateTime.now()) : Tk2Deal.termText(k, t[k])),
              OnbKeyValue('Things in the house', d.items.map((i) => i.count > 1 ? '${i.count} ${i.name}' : i.name).join(', '), last: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OnbReadFullButton(
          label: 'Read the full agreement',
          onPressed: () => dealPush(context, DealAgreementText(deal: d)),
        ),
        dealHeading('Replies'),
        _who(DealRole.tenant),
        _who(DealRole.owner),
        if (widget.role != DealRole.broker && d.replyOk(widget.role) == null)
          dealText('Talk to the broker or the other person if you want something changed. Here you only say yes, or note what you asked for.'),
      ],
    );
  }
}

/// The full legal text, filled from the terms.
class DealAgreementText extends StatelessWidget {
  const DealAgreementText({required this.deal, super.key});
  final Tk2Deal deal;

  /// **bold** parts of one paragraph.
  static List<TextSpan> _spans(String line) {
    final parts = line.split('**');
    return [
      for (final (i, p) in parts.indexed)
        if (p.isNotEmpty)
          TextSpan(
            text: p,
            style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700, color: AppColors.heading) : null,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) => OnbPage(
    title: 'Full agreement',
    subtitle: deal.version == 0 ? 'Preview' : 'Version ${deal.version}',
    onBack: () => Navigator.of(context).maybePop(),
    children: [
      FutureBuilder<String>(
        future: Tk2Agreement.load(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final text = Tk2Agreement.fill(snap.data!, deal);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (Tk2Agreement.gaps(text) > 0) ...[
                const OnbBanner('Blank lines are details still to be filled.', kind: 'info', icon: Icons.info_outline),
                const SizedBox(height: 12),
              ],
              for (final p in text.split('\n\n'))
                if (p.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text.rich(
                      TextSpan(children: _spans(p.trim())),
                      style: const TextStyle(fontSize: 15, height: 23 / 15, color: AppColors.body),
                    ),
                  ),
            ],
          );
        },
      ),
    ],
  );
}

/// Broker: a photo of the stamp paper. Signing cannot start without it.
class DealStamp extends StatefulWidget {
  const DealStamp({required this.store, required this.deal, super.key});
  final Tk2Store store;
  final Tk2Deal deal;

  @override
  State<DealStamp> createState() => _DealStampState();
}

class _DealStampState extends State<DealStamp> {
  String photo = '';
  final number = TextEditingController();
  bool need = false;

  @override
  void dispose() {
    number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (photo.isEmpty) return setState(() => need = true);
    widget.deal.b.addAll({'stamp': photo, 'stampNo': number.text.trim()});
    await widget.store.saveDeal(widget.deal, DealRole.broker);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => OnbPage(
    title: 'Stamp paper',
    subtitle: 'Everyone said yes to version ${widget.deal.version}',
    onBack: () => Navigator.of(context).maybePop(),
    footer: [PrimaryButton(label: 'Save and open signing', icon: Icons.chevron_right, onPressed: _save)],
    children: [
      dealText('Buy the stamp paper for this agreement and add a clear photo of it. The owner and tenant can sign only after this.'),
      const SizedBox(height: 16),
      DealPhotoRow(
        title: 'Photo of the stamp paper',
        subtitle: 'The full page, easy to read',
        path: photo,
        need: need,
        onPick: () async {
          final p = await dealPickPhoto(context, widget.deal);
          if (p != null && mounted) {
            setState(() {
              photo = p;
              need = false;
            });
          }
        },
      ),
      OnbTextField(label: 'Stamp paper number (if printed on it)', controller: number, capitalization: TextCapitalization.characters),
      const SizedBox(height: 14),
      OnbBanner('Its cost is inside the ${Tk2Store.money(Tk2Deal.agreementFee)} agreement fee.', kind: 'info', icon: Icons.receipt_long_outlined),
    ],
  );
}

/// Tenant and owner sign. Test signing until Leegality e-sign is connected.
class DealSign extends StatefulWidget {
  const DealSign({required this.store, required this.deal, required this.role, super.key});
  final Tk2Store store;
  final Tk2Deal deal;
  final DealRole role;

  @override
  State<DealSign> createState() => _DealSignState();
}

class _DealSignState extends State<DealSign> {
  final name = TextEditingController();
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _sign() async {
    if (name.text.trim().length < 3) return setState(() => error = 'Type your full name to sign');
    widget.deal.part(widget.role).addAll({'signed': name.text.trim(), 'signedAt': DateTime.now().millisecondsSinceEpoch});
    await widget.store.saveDeal(widget.deal, widget.role);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.deal;
    final other = widget.role == DealRole.tenant ? DealRole.owner : DealRole.tenant;
    return OnbPage(
      title: 'Sign the agreement',
      subtitle: 'Version ${d.version} · on stamp paper',
      onBack: () => Navigator.of(context).maybePop(),
      footer: [PrimaryButton(label: 'Sign', icon: Icons.draw_outlined, onPressed: Tk2Cloud.on ? null : _sign)],
      children: [
        const OnbBanner('Final agreement. You and the other person both said yes.', kind: 'ok', icon: Icons.verified_outlined),
        const SizedBox(height: 12),
        OnbReadFullButton(
          label: 'Read the full agreement',
          onPressed: () => dealPush(context, DealAgreementText(deal: d)),
        ),
        const SizedBox(height: 16),
        dealText('${d.nameOf(other)} ${d.signed(other) ? 'has signed' : 'signs too'}. Everyone gets the signed copy when the last person signs.'),
        const SizedBox(height: 12),
        OnbTextField(
          label: 'Your full name',
          controller: name,
          capitalization: TextCapitalization.words,
          error: error,
          onChanged: (_) => setState(() => error = null),
        ),
        const SizedBox(height: 12),
        if (Tk2Cloud.on)
          const OnbBanner('Agreement signing is unavailable during the staging pilot.', kind: 'wait', icon: Icons.info_outline)
        else
          const OnbBanner('Demo build: the real e-sign link comes on WhatsApp and email.', kind: 'wait', icon: Icons.science_outlined),
      ],
    );
  }
}
