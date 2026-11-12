import 'tk2_store.dart';

/// The ten stages from "token paid" to "living there", always in this order.
enum DealStage { token, docs, draft, approval, signing, payment, handover, repairs, society, living }

enum DealRole { broker, tenant, owner }

const dealStageNames = {
  DealStage.token: 'Token paid',
  DealStage.docs: 'Documents',
  DealStage.draft: 'Agreement draft',
  DealStage.approval: 'Changes and approval',
  DealStage.signing: 'Stamp paper and signing',
  DealStage.payment: 'Payments',
  DealStage.handover: 'Key handover',
  DealStage.repairs: '7-day repair window',
  DealStage.society: 'Society move-in',
  DealStage.living: 'Living there',
};

/// One thing a person has to do now. [key] says which screen opens:
/// token · docs · review:t · review:o · terms · reply · stamp · sign · pay ·
/// fee · handover · check · edit · quote:ID · approve:ID · fixed:ID ·
/// payrepair:ID · raise · playbook · soc:N
typedef DealTask = ({String key, String label, DealStage stage});

/// One finalised house: everything after the tenant picks it, shared by the
/// broker (app), the tenant and the owner (web).
///
/// Each person writes only their own part: [b] broker, [t] tenant, [o] owner.
/// The Firestore rules enforce the same split (tk2Deals). The stage and
/// "who is holding it up" are worked out from the three parts, never stored.
class Tk2Deal {
  Tk2Deal({
    required this.id,
    required this.listingId,
    required this.title,
    required this.tenantName,
    required this.tenantPhone,
    required this.token,
    required this.rent,
    required this.deposit,
    required this.createdAt,
    this.brokerage = 0,
    this.maintenance = 0,
    this.brokerUid = '',
    this.tenantUid = '',
    this.ownerUid,
    this.ownerName = '',
    this.ownerPhone = '',
    this.brokerName = '',
    this.brokerPhone = '',
    Map<String, dynamic>? b,
    Map<String, dynamic>? t,
    Map<String, dynamic>? o,
  }) : b = b ?? {},
       t = t ?? {},
       o = o ?? {};

  final String id;
  final String listingId;

  /// Public title of the house ("2 BHK · Prestige Highfield").
  final String title;
  final String tenantName, tenantPhone;
  String ownerName, ownerPhone;
  final String brokerName, brokerPhone;
  final String brokerUid, tenantUid;
  String? ownerUid;

  /// Money fixed when the house was blocked. [maintenance] is per month, 0 when included in rent.
  final int token, rent, deposit, brokerage, maintenance;
  final int createdAt;

  /// Broker's, tenant's and owner's parts.
  final Map<String, dynamic> b, t, o;

  static const agreementFee = 500;
  static const feeShare = agreementFee ~/ 2;
  static const repairDays = 7;

  Map<String, dynamic> part(DealRole r) => switch (r) {
    DealRole.broker => b,
    DealRole.tenant => t,
    DealRole.owner => o,
  };

  static String who(DealRole r) => switch (r) {
    DealRole.broker => 'broker',
    DealRole.tenant => 'tenant',
    DealRole.owner => 'owner',
  };

  String nameOf(DealRole r) => switch (r) {
    DealRole.broker => brokerName.isEmpty ? 'Broker' : brokerName,
    DealRole.tenant => tenantName.isEmpty ? 'Tenant' : tenantName,
    DealRole.owner => ownerName.isEmpty ? 'Owner' : ownerName,
  };

  // ------------------------------------------------------------ small reads

  /// 'owner' or 'tenant' when the deal broke before signing, else null.
  String? get ended => b['ended'] as String?;
  int get version => b['v'] as int? ?? 0;
  Map<String, dynamic> get terms => Map<String, dynamic>.from(b['terms'] as Map? ?? const {});

  /// Things in the house (annexure): name and count.
  List<({String name, int count})> get items => [
    for (final i in (b['items'] as List? ?? const []))
      if (i is Map) (name: i['n'] as String? ?? '', count: (i['c'] as num?)?.toInt() ?? 1),
  ];

  Map<String, dynamic> _map(Map<String, dynamic> from, String key) => Map<String, dynamic>.from(from[key] as Map? ?? const {});

  /// Documents: a person sends them (`docsAt`), the broker approves (`docsOk`)
  /// or asks again with a note (`redo`), which stands until they send again.
  bool docsSent(DealRole r) => (part(r)['docsAt'] as int? ?? 0) > 0;
  bool docsOk(DealRole r) => _map(b, 'docsOk')[who(r)] == true;
  String redo(DealRole r) {
    final ask = _map(_map(b, 'redo'), who(r));
    return (ask['at'] as int? ?? 0) > (part(r)['docsAt'] as int? ?? 0) ? ask['note'] as String? ?? '' : '';
  }

  /// This person's reply to the current version: true yes, false asked for a change, null not yet.
  bool? replyOk(DealRole r) {
    final reply = _map(part(r), 'reply');
    return reply['v'] == version && version > 0 ? reply['ok'] as bool? : null;
  }

  String replyNote(DealRole r) => replyOk(r) == false ? _map(part(r), 'reply')['note'] as String? ?? '' : '';
  bool get approved => replyOk(DealRole.tenant) == true && replyOk(DealRole.owner) == true;
  bool signed(DealRole r) => (part(r)['signed'] as String? ?? '').isNotEmpty;
  bool get hasStamp => (b['stamp'] as String? ?? '').isNotEmpty;

  /// The handover record. A later change (key count, meter readings) counts
  /// only once both the owner and the tenant have approved it.
  Map<String, dynamic> get handover {
    final h = _map(b, 'handover');
    final e = edit;
    if (e != null && t['editOk'] == e['v'] && o['editOk'] == e['v']) h.addAll({'keys': e['keys'], 'meters': e['meters']});
    return h;
  }

  int get handoverAt => handover['at'] as int? ?? 0;

  /// Tenant's tick per annexure item: 'ok' or a note about what is wrong.
  Map<String, dynamic> get ticks => _map(t, 'items');
  bool get itemsChecked => items.every((i) => ticks.containsKey(i.name));

  /// A later change to the handover record waiting for owner and tenant.
  Map<String, dynamic>? get edit => b['edit'] is Map ? _map(b, 'edit') : null;
  bool editOk(DealRole r) => edit == null || part(r)['editOk'] == edit!['v'];

  // ---------------------------------------------------------------- money

  /// What the tenant pays to move in: deposit + first rent + brokerage +
  /// half the agreement fee, minus the token already paid.
  int get moveInTotal => deposit + rent + maintenance + brokerage + feeShare - token;

  /// Token when the deal breaks before signing: owner backs out → all of it
  /// back to the tenant; tenant backs out → half to the owner, half to the broker.
  static ({int tenant, int owner, int broker}) tokenSplit(int token, String endedBy) =>
      endedBy == 'owner' ? (tenant: token, owner: 0, broker: 0) : (tenant: 0, owner: token ~/ 2, broker: token - token ~/ 2);

  // -------------------------------------------------------------- repairs

  /// Repair requests the tenant raised, newest last, joined with the broker's
  /// quote and the owner's answer.
  List<Tk2Repair> get repairs => [
    for (final r in (t['repairs'] as List? ?? const []))
      if (r is Map) Tk2Repair(Map<String, dynamic>.from(r), _map(_map(b, 'quotes'), r['id'] as String), _map(_map(o, 'rep'), r['id'] as String)),
  ];

  bool repairWindowOpen(DateTime now) => handoverAt > 0 && now.millisecondsSinceEpoch < handoverAt + const Duration(days: repairDays).inMilliseconds;
  int repairDaysLeft(DateTime now) =>
      handoverAt == 0 ? 0 : (repairDays - now.difference(DateTime.fromMillisecondsSinceEpoch(handoverAt)).inDays).clamp(0, repairDays);

  /// Owner and tenant talking about one request (the broker reads along).
  List<({DealRole from, String text, int at})> chat(String repairId) {
    final all = <({DealRole from, String text, int at})>[
      for (final r in [DealRole.tenant, DealRole.owner])
        for (final m in (part(r)['msgs'] as List? ?? const []))
          if (m is Map && m['r'] == repairId) (from: r, text: m['text'] as String? ?? '', at: m['at'] as int? ?? 0),
    ];
    return all..sort((a, b) => a.at.compareTo(b.at));
  }

  // -------------------------------------------------------------- society

  String get societyName => _map(b, 'soc')['name'] as String? ?? '';
  List<Tk2SocietyStep> get societySteps {
    final steps = _map(b, 'soc')['steps'] as List? ?? const [];
    return [
      for (var i = 0; i < steps.length; i++)
        if (steps[i] is Map)
          Tk2SocietyStep(i, Map<String, dynamic>.from(steps[i] as Map), done: _map(part(_role((steps[i] as Map)['who'])), 'soc')['$i'] == true),
    ];
  }

  static DealRole _role(Object? who) => switch (who) {
    'tenant' => DealRole.tenant,
    'owner' => DealRole.owner,
    _ => DealRole.broker,
  };

  /// No society steps needed (stand-alone house), or all done.
  bool get societyDone => _map(b, 'soc')['none'] == true || (societySteps.isNotEmpty && societySteps.every((s) => s.done));

  // ---------------------------------------------------------------- stage

  bool _paid() => t['paid'] == true && o['feePaid'] == true;
  bool get handedOver => handoverAt > 0 && itemsChecked && t['keysOk'] == true;

  /// Where the deal stands (the first stage not finished yet).
  DealStage stage(DateTime now) {
    if (t['tokenPaid'] != true) return DealStage.token;
    if (!(docsOk(DealRole.tenant) && docsOk(DealRole.owner))) return DealStage.docs;
    if (version == 0) return DealStage.draft;
    if (!approved) return DealStage.approval;
    if (!(hasStamp && signed(DealRole.tenant) && signed(DealRole.owner))) return DealStage.signing;
    if (!_paid()) return DealStage.payment;
    if (!handedOver) return DealStage.handover;
    if (repairWindowOpen(now) || repairs.any((r) => r.open)) return DealStage.repairs;
    if (!societyDone) return DealStage.society;
    return DealStage.living;
  }

  /// done · now · later, for the tracker. Society runs beside handover and
  /// repairs: it opens as soon as everything is paid.
  String stageState(DealStage s, DateTime now) {
    final at = stage(now);
    if (s == DealStage.society && at.index >= DealStage.handover.index) return societyDone ? 'done' : 'now';
    if (s == DealStage.repairs && at == DealStage.society) return 'done';
    return s.index < at.index ? 'done' : (s == at ? 'now' : 'later');
  }

  /// What [r] has to do right now, most urgent first. Empty = waiting for others.
  List<DealTask> tasks(DealRole r, DateTime now) {
    if (ended != null) return const [];
    final at = stage(now);
    final out = <DealTask>[];
    void add(String key, String label, [DealStage? s]) => out.add((key: key, label: label, stage: s ?? at));
    final isBroker = r == DealRole.broker, isTenant = r == DealRole.tenant, isOwner = r == DealRole.owner;
    switch (at) {
      case DealStage.token:
        if (isTenant) add('token', 'Pay ${Tk2Store.money(token)} and block');
      case DealStage.docs:
        if (!isBroker && !docsOk(r) && (!docsSent(r) || redo(r).isNotEmpty)) add('docs', redo(r).isEmpty ? 'Upload your documents' : 'Upload documents again');
        if (isBroker) {
          for (final p in [DealRole.tenant, DealRole.owner]) {
            if (docsSent(p) && !docsOk(p) && redo(p).isEmpty) add('review:${who(p)[0]}', "Check ${nameOf(p).split(' ').first}'s documents");
          }
        }
      case DealStage.draft:
        if (isBroker) add('terms', 'Write the agreement');
      case DealStage.approval:
        if (!isBroker && replyOk(r) == null) add('reply', 'Read the agreement');
        if (isBroker && (replyOk(DealRole.tenant) == false || replyOk(DealRole.owner) == false)) add('terms', 'Change the agreement');
      case DealStage.signing:
        if (isBroker && !hasStamp) add('stamp', 'Add stamp paper photo');
        if (!isBroker && hasStamp && !signed(r)) add('sign', 'Sign the agreement');
      case DealStage.payment:
        if (isTenant && t['paid'] != true) add('pay', 'Pay ${Tk2Store.money(moveInTotal)} to move in');
        if (isOwner && o['feePaid'] != true) add('fee', 'Pay ${Tk2Store.money(feeShare)} agreement fee');
      case DealStage.handover:
        if (isBroker && handoverAt == 0) add('handover', 'Hand over the keys');
        if (isTenant && handoverAt > 0) add('check', 'Check the house and keys');
      case DealStage.repairs || DealStage.society || DealStage.living:
        break;
    }
    if (handoverAt > 0) {
      if (!isBroker && !editOk(r)) add('edit', 'Approve a change to the handover', DealStage.handover);
      for (final x in repairs.where((x) => x.open)) {
        final step = x.waitingOn;
        if (step == r) add('${x.taskKey}:${x.id}', x.taskLabel, DealStage.repairs);
      }
      if (isTenant && handedOver && repairWindowOpen(now)) add('raise', 'Report something broken', DealStage.repairs);
    }
    if (at.index >= DealStage.handover.index && !societyDone) {
      if (societySteps.isEmpty) {
        if (isBroker) add('playbook', 'Set the society steps', DealStage.society);
      } else {
        final next = societySteps.firstWhere((s) => !s.done);
        if (next.who == r) add('soc:${next.index}', next.title, DealStage.society);
      }
    }
    return out;
  }

  /// Who the deal is waiting for (people with something to do), for
  /// "Waiting for …" lines and the broker's nudge buttons.
  List<DealRole> holders(DateTime now) => [
    for (final r in DealRole.values)
      if (tasks(r, now).any((x) => x.key != 'raise')) r,
  ];

  // ------------------------------------------------------------ demo help

  /// Demo build only (no backend): does [r]'s next step with sample answers,
  /// so one phone can walk the whole journey. Returns false when [r] has nothing to do.
  bool demoDo(DealRole r, DateTime now) {
    final todo = tasks(r, now).where((x) => x.key != 'raise').firstOrNull;
    if (todo == null) return false;
    final me = part(r), ms = now.millisecondsSinceEpoch;
    final id = todo.key.contains(':') ? todo.key.split(':').last : '';
    switch (todo.key.split(':').first) {
      case 'token':
        t.addAll({'tokenPaid': true, 'tokenAt': ms});
      case 'docs':
        me['docsAt'] = ms;
      case 'review':
        b['docsOk'] = _map(b, 'docsOk')..[id == 't' ? 'tenant' : 'owner'] = true;
      case 'terms':
        sendVersion(defaultTerms(now), items.isEmpty ? const [(name: 'Fans and lights', count: 1), (name: 'Geyser', count: 2)] : items);
      case 'reply':
        me['reply'] = {'v': version, 'ok': true};
      case 'stamp':
        b['stamp'] = 'demo';
      case 'sign':
        me['signed'] = nameOf(r);
      case 'pay':
        t.addAll({'paid': true, 'paidAt': ms});
      case 'fee':
        o['feePaid'] = true;
      case 'handover':
        b['handover'] = {
          'photos': const <String>[],
          'video': '',
          'meters': const {'Electricity': '1024'},
          'keys': 2,
          'keysPhoto': 'demo',
          'at': ms,
        };
      case 'check':
        t.addAll({
          'items': {for (final i in items) i.name: 'ok'},
          'keysOk': true,
        });
      case 'edit':
        me['editOk'] = edit!['v'];
      case 'quote':
        b['quotes'] = _map(b, 'quotes')..[id] = {'min': 500, 'max': 800, 'days': 2};
      case 'approve':
        o['rep'] = _map(o, 'rep')..[id] = {'ok': true};
      case 'fixed':
        b['quotes'] = _map(b, 'quotes')..[id] = {..._map(_map(b, 'quotes'), id), 'done': ms, 'photo': 'demo', 'amount': 650};
      case 'payrepair':
        o['rep'] = _map(o, 'rep')..[id] = {..._map(_map(o, 'rep'), id), 'paid': true};
      case 'playbook':
        b['soc'] = {'name': 'Sample society', 'steps': Tk2SocietyStep.starter};
      case 'soc':
        me['soc'] = _map(me, 'soc')..[id] = true;
    }
    return true;
  }

  // ------------------------------------------------------- broker actions

  /// Terms the form starts with: from the listing's rent and deposit.
  Map<String, dynamic> defaultTerms(DateTime now) => {
    'start': DateTime(now.year, now.month + 1, 1).toIso8601String().substring(0, 10),
    'months': 11,
    'lockIn': 3,
    'notice': 2,
    'dueDay': 5,
    'lateFee': 0,
    'rent': rent,
    'deposit': deposit,
    'refundDays': 7,
    'paint': false,
    'clean': true,
    'pets': false,
    'people': 4,
    'address': '',
    'ownerAddress': '',
    ...terms,
  };

  /// A new agreement version: keeps the old terms to show what changed, and
  /// every earlier reply stops counting (they carry the old version number).
  void sendVersion(Map<String, dynamic> newTerms, List<({String name, int count})> newItems, {String note = ''}) {
    if (version > 0) b['prev'] = terms;
    b['terms'] = newTerms;
    b['items'] = [
      for (final i in newItems) {'n': i.name, 'c': i.count},
    ];
    b['v'] = version + 1;
    b['note'] = note;
  }

  /// Plain "what changed" lines between the last version and this one.
  List<String> get changes {
    final old = _map(b, 'prev');
    if (old.isEmpty) return const [];
    final now = terms;
    return [
      for (final k in termLabels.keys)
        if ('${old[k]}' != '${now[k]}') '${termLabels[k]}: ${termText(k, old[k])} → ${termText(k, now[k])}',
    ];
  }

  static const termLabels = {
    'rent': 'Rent',
    'deposit': 'Security deposit',
    'start': 'Start date',
    'months': 'Term',
    'lockIn': 'Minimum stay',
    'notice': 'Notice',
    'dueDay': 'Rent due by',
    'lateFee': 'Late fee',
    'refundDays': 'Deposit back in',
    'paint': 'Painting at move-out',
    'clean': 'Cleaning at move-out',
    'pets': 'Pets',
    'people': 'People',
  };

  static String termText(String key, Object? v) => switch (key) {
    'rent' || 'deposit' => Tk2Store.money((v as num?)?.toInt() ?? 0),
    'months' || 'lockIn' || 'notice' => '$v months',
    'dueDay' => 'day $v of the month',
    'lateFee' => (v as num? ?? 0) > 0 ? '${Tk2Store.money((v as num).toInt())} a day' : 'None',
    'refundDays' => '$v days',
    'paint' => v == true ? 'Deducted from deposit' : 'Not deducted',
    'clean' => v == true ? 'Tenant cleans or pays' : 'Not asked',
    'pets' => v == true ? 'Allowed' : 'Not allowed',
    'people' => 'Up to $v',
    _ => '$v',
  };

  // ------------------------------------------------------------------ json

  Map<String, dynamic> toJson() => {
    'id': id,
    'listingId': listingId,
    'title': title,
    'tenantName': tenantName,
    'tenantPhone': tenantPhone,
    'ownerName': ownerName,
    'ownerPhone': ownerPhone,
    'brokerName': brokerName,
    'brokerPhone': brokerPhone,
    'brokerUid': brokerUid,
    'tenantUid': tenantUid,
    'ownerUid': ownerUid,
    'token': token,
    'rent': rent,
    'deposit': deposit,
    'brokerage': brokerage,
    'maintenance': maintenance,
    'createdAt': createdAt,
    'b': b,
    't': t,
    'o': o,
  };

  factory Tk2Deal.fromJson(Map<String, dynamic> j) {
    String s(String k) => j[k] as String? ?? '';
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    Map<String, dynamic> m(String k) => Map<String, dynamic>.from(j[k] as Map? ?? const {});
    return Tk2Deal(
      id: s('id'),
      listingId: s('listingId'),
      title: s('title'),
      tenantName: s('tenantName'),
      tenantPhone: s('tenantPhone'),
      ownerName: s('ownerName'),
      ownerPhone: s('ownerPhone'),
      brokerName: s('brokerName'),
      brokerPhone: s('brokerPhone'),
      brokerUid: s('brokerUid'),
      tenantUid: s('tenantUid'),
      ownerUid: j['ownerUid'] as String?,
      token: n('token'),
      rent: n('rent'),
      deposit: n('deposit'),
      brokerage: n('brokerage'),
      maintenance: n('maintenance'),
      createdAt: n('createdAt'),
      b: m('b'),
      t: m('t'),
      o: m('o'),
    );
  }
}

/// One repair request in the 7-day window.
/// Order: tenant raises → broker quotes cost and time → owner approves →
/// broker fixes and adds a photo → owner pays the exact amount.
class Tk2Repair {
  Tk2Repair(this.raised, this.quote, this.answer);
  final Map<String, dynamic> raised, quote, answer;

  String get id => raised['id'] as String;
  String get text => raised['text'] as String? ?? '';
  String get photo => raised['photo'] as String? ?? '';
  int get at => raised['at'] as int? ?? 0;

  bool get withdrawn => raised['off'] == true;
  bool get cancelled => answer['ok'] == false;
  bool get quoted => quote.containsKey('min');

  /// The broker says this is not the owner's to fix: owner and tenant talk it out.
  bool get notOwners => quote['notOwner'] == true;
  bool get approved => answer['ok'] == true;
  bool get fixed => (quote['done'] as int? ?? 0) > 0;
  bool get paid => answer['paid'] == true;
  int get amount => (quote['amount'] as num?)?.toInt() ?? 0;
  String get donePhoto => quote['photo'] as String? ?? '';
  String get range => '${Tk2Store.money((quote['min'] as num?)?.toInt() ?? 0)} – ${Tk2Store.money((quote['max'] as num?)?.toInt() ?? 0)}';
  int get days => (quote['days'] as num?)?.toInt() ?? 0;

  bool get open => !withdrawn && !cancelled && !paid;

  DealRole? get waitingOn => !open
      ? null
      : !quoted
      ? DealRole.broker
      : !approved
      ? DealRole.owner
      : !fixed
      ? DealRole.broker
      : DealRole.owner;

  String get taskKey => !quoted ? 'quote' : (!approved ? 'approve' : (!fixed ? 'fixed' : 'payrepair'));
  String get taskLabel => switch (taskKey) {
    'quote' => 'Add cost and time for a repair',
    'approve' => 'Approve a repair',
    'fixed' => 'Finish a repair and add a photo',
    _ => 'Pay ${Tk2Store.money(amount)} for a repair',
  };

  /// Short status for lists, in the reader's words.
  String status(DealRole reader) {
    if (withdrawn) return 'Taken back by the tenant';
    if (cancelled) return 'Cancelled by the owner';
    if (paid) return 'Fixed';
    if (!quoted) return reader == DealRole.broker ? 'Add cost and time' : 'The broker is checking';
    if (!approved) return reader == DealRole.owner ? 'Needs your yes' : 'Waiting for the owner';
    if (!fixed) return reader == DealRole.broker ? 'Get it fixed' : 'Being fixed · about $days ${days == 1 ? 'day' : 'days'}';
    return reader == DealRole.owner ? 'Fixed · pay ${Tk2Store.money(amount)}' : 'Fixed';
  }
}

/// One step of a society's move-in playbook.
/// Kinds: email · approval · reply · visit · upload · gate · fee.
class Tk2SocietyStep {
  Tk2SocietyStep(this.index, this.data, {required this.done});
  final int index;
  final Map<String, dynamic> data;
  final bool done;

  String get kind => data['k'] as String? ?? 'visit';
  String get title => data['title'] as String? ?? kinds[kind]!.$1;
  String get text => data['text'] as String? ?? '';

  /// Email steps: the society office address.
  String get to => data['to'] as String? ?? '';
  DealRole get who => Tk2Deal._role(data['who']);

  /// kind → (name, what the app does, who does it by default)
  static const kinds = {
    'email': ('Send email', 'An email to the society office, with broker, owner and tenant in CC.', 'broker'),
    'approval': ('Wait for approval', 'Ask a person and wait for their yes.', 'owner'),
    'reply': ('Reply to a request', 'A ready-made reply you can send in one tap.', 'broker'),
    'visit': ('Visit in person', 'Tell the tenant where to go and what to carry.', 'tenant'),
    'upload': ('Upload a document', 'Ask for a file and keep it.', 'tenant'),
    'gate': ('Gate app access', 'Guide the tenant to join the gate app for this flat.', 'tenant'),
    'fee': ('Pay a fee', 'A society charge and who pays it.', 'tenant'),
  };

  /// A common set of steps a broker can start from and edit.
  static const starter = [
    {
      'k': 'email',
      'who': 'broker',
      'title': 'Tell the society office',
      'text': 'We wish to inform you that new tenants are moving in. Their details and the move-in date are below. Kindly do the needful.',
    },
    {'k': 'approval', 'who': 'owner', 'title': 'Owner approves on the email', 'text': 'Reply "Approved" on the email to the society office.'},
    {'k': 'visit', 'who': 'tenant', 'title': 'Fill the form at the society office', 'text': 'Carry your Aadhaar and a copy of the agreement.'},
    {
      'k': 'gate',
      'who': 'tenant',
      'title': 'Join the gate app',
      'text': 'Ask the office to add you on the gate app for this flat. Done when your first guest entry works.',
    },
  ];
}
