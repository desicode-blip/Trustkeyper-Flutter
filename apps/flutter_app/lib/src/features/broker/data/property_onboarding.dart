import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Status of one paper the owner is asked for.
enum PaperStatus { waiting, checking, approved, notClear, needsYou, notNeeded }

PaperStatus _statusFrom(Object? value) => PaperStatus.values.firstWhere(
  (status) => status.name == value,
  orElse: () => PaperStatus.waiting,
);

/// The papers we ask the owner for, in the order the broker sees them.
abstract final class PaperKeys {
  static const aadhaar = 'aadhaar';
  static const phone = 'phone';
  static const email = 'email';
  static const tenantAgreement = 'tenantAgreement';
  static const rentDeposit = 'rentDeposit';
  static const bank = 'bank';
  static const address = 'address';
  static const keys = 'keys';
  /// Order we ask: address first (it creates the house), keys last.
  static const all = [
    address,
    aadhaar,
    phone,
    email,
    tenantAgreement,
    rentDeposit,
    bank,
    keys,
  ];

  static String title(String key) => switch (key) {
    aadhaar => 'Aadhaar card',
    phone => 'Phone number',
    email => 'Email',
    tenantAgreement => 'Tenant agreement',
    rentDeposit => 'Rent and deposit',
    bank => 'Bank details',
    address => 'House address',
    keys => 'Key holder',
    _ => key,
  };

  static String hint(String key) => switch (key) {
    aadhaar => 'Photo of the Aadhaar card',
    phone => 'Number of the owner',
    email => 'Email of the owner',
    tenantAgreement => 'Only if a tenant lives there',
    rentDeposit => 'What the owner wants',
    bank => 'Cancelled cheque is best',
    address => 'Full address of the house',
    keys => 'Name and number of who holds the keys',
    _ => '',
  };
}

class OnboardingPaper {
  const OnboardingPaper({
    required this.key,
    this.status = PaperStatus.waiting,
    this.reason = '',
    this.value = '',
  });
  final String key;
  final PaperStatus status;

  /// Why a paper was not approved, in simple words.
  final String reason;

  /// What we read from the paper (shown to the broker).
  final String value;

  OnboardingPaper copyWith({
    PaperStatus? status,
    String? reason,
    String? value,
  }) => OnboardingPaper(
    key: key,
    status: status ?? this.status,
    reason: reason ?? this.reason,
    value: value ?? this.value,
  );

  Map<String, Object?> toJson() => {
    'key': key,
    'status': status.name,
    'reason': reason,
    'value': value,
  };

  factory OnboardingPaper.fromJson(Map<String, dynamic> json) =>
      OnboardingPaper(
        key: json['key'] as String? ?? '',
        status: _statusFrom(json['status']),
        reason: json['reason'] as String? ?? '',
        value: json['value'] as String? ?? '',
      );
}

/// One change asked on the agreement, by the owner or by the broker.
class DraftChange {
  const DraftChange({
    required this.id,
    required this.clause,
    required this.before,
    required this.asked,
    required this.askedBy,
    this.status = 'waitingYou',
    this.round = 1,
    this.note = '',
  });
  final String id;
  final String clause;
  final String before;
  final String asked;

  /// 'owner' or 'broker'.
  final String askedBy;

  /// waitingYou · waitingOwner · agreed · notAgreed
  final String status;
  final int round;
  final String note;

  DraftChange copyWith({
    String? asked,
    String? askedBy,
    String? status,
    int? round,
  }) => DraftChange(
    id: id,
    clause: clause,
    before: before,
    asked: asked ?? this.asked,
    askedBy: askedBy ?? this.askedBy,
    status: status ?? this.status,
    round: round ?? this.round,
    note: note,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'clause': clause,
    'before': before,
    'asked': asked,
    'askedBy': askedBy,
    'status': status,
    'round': round,
    'note': note,
  };

  factory DraftChange.fromJson(Map<String, dynamic> json) => DraftChange(
    id: json['id'] as String? ?? '',
    clause: json['clause'] as String? ?? '',
    before: json['before'] as String? ?? '',
    asked: json['asked'] as String? ?? '',
    askedBy: json['askedBy'] as String? ?? 'owner',
    status: json['status'] as String? ?? 'waitingYou',
    round: (json['round'] as num?)?.toInt() ?? 1,
    note: json['note'] as String? ?? '',
  );
}

class DraftVersion {
  const DraftVersion({required this.number, required this.summary, required this.at});
  final int number;
  final String summary;
  final int at;

  Map<String, Object?> toJson() => {'number': number, 'summary': summary, 'at': at};
  factory DraftVersion.fromJson(Map<String, dynamic> json) => DraftVersion(
    number: (json['number'] as num?)?.toInt() ?? 1,
    summary: json['summary'] as String? ?? '',
    at: (json['at'] as num?)?.toInt() ?? 0,
  );
}

/// What the broker agreed with the owner by word of mouth.
class AgreementAnswers {
  const AgreementAnswers({
    this.feeType = '',
    this.feeValue = 0,
    this.payWay = '',
    this.startDate = '',
    this.months = 11,
    this.notes = '',
  });

  /// days · percent · fixed · once
  final String feeType;
  final double feeValue;

  /// cut · direct · signing
  final String payWay;
  final String startDate;
  final int months;
  final String notes;

  AgreementAnswers copyWith({
    String? feeType,
    double? feeValue,
    String? payWay,
    String? startDate,
    int? months,
    String? notes,
  }) => AgreementAnswers(
    feeType: feeType ?? this.feeType,
    feeValue: feeValue ?? this.feeValue,
    payWay: payWay ?? this.payWay,
    startDate: startDate ?? this.startDate,
    months: months ?? this.months,
    notes: notes ?? this.notes,
  );

  Map<String, Object?> toJson() => {
    'feeType': feeType,
    'feeValue': feeValue,
    'payWay': payWay,
    'startDate': startDate,
    'months': months,
    'notes': notes,
  };

  factory AgreementAnswers.fromJson(Map<String, dynamic> json) =>
      AgreementAnswers(
        feeType: json['feeType'] as String? ?? '',
        feeValue: (json['feeValue'] as num?)?.toDouble() ?? 0,
        payWay: json['payWay'] as String? ?? '',
        startDate: json['startDate'] as String? ?? '',
        months: (json['months'] as num?)?.toInt() ?? 11,
        notes: json['notes'] as String? ?? '',
      );

  String feeSummary(int rent) {
    String money(num value) => '₹ ${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}';
    return switch (feeType) {
      'days' => '${feeValue.toStringAsFixed(0)} days of rent, once '
          '(${money(rent / 30 * feeValue)})',
      'percent' => '${feeValue.toStringAsFixed(feeValue % 1 == 0 ? 0 : 1)}% of rent every month '
          '(${money(rent * feeValue / 100)})',
      'fixed' => '${money(feeValue)} every month',
      'once' => '${money(feeValue)} one time',
      _ => 'Not set',
    };
  }

  String get payWayText => switch (payWay) {
    'cut' => 'We cut it from the rent',
    'direct' => 'Owner pays you directly',
    'signing' => 'Owner pays once, at signing',
    _ => 'Not set',
  };
}

/// Where this house is in the journey.
abstract final class OnboardingPhase {
  static const papers = 'papers';
  static const questions = 'questions';
  static const preparing = 'preparing';
  static const review = 'review';
  static const printing = 'printing';
  static const signing = 'signing';
  static const ready = 'ready';
}

class PropertyOnboarding {
  PropertyOnboarding({
    required this.id,
    required this.ownerName,
    required this.channel,
    required this.contact,
    required this.createdAt,
    List<String> otherOwners = const [],
    List<OnboardingPaper>? papers,
    this.phase = OnboardingPhase.papers,
    this.agreementSkipped = false,
    this.rent = 32000,
    this.deposit = 192000,
    this.address = '',
    this.answers = const AgreementAnswers(),
    this.draftNo = 0,
    this.draftSent = false,
    this.draftSentAt = 0,
    this.ownerAgreedFinal = false,
    List<DraftChange> changes = const [],
    List<DraftVersion> versions = const [],
    this.printStep = 0,
    this.brokerSigned = false,
    this.ownerSigned = false,
    this.lastAskedAt = 0,
  }) : otherOwners = List.unmodifiable(otherOwners),
       papers = List.unmodifiable(
         ([...(papers ?? [for (final key in PaperKeys.all) OnboardingPaper(key: key)])])
           ..sort((a, b) => PaperKeys.all.indexOf(a.key).compareTo(PaperKeys.all.indexOf(b.key))),
       ),
       changes = List.unmodifiable(changes),
       versions = List.unmodifiable(versions);

  final String id;
  final String ownerName;

  /// 'email' or 'whatsapp'.
  final String channel;
  final String contact;
  final int createdAt;
  final List<String> otherOwners;
  final List<OnboardingPaper> papers;
  final String phase;
  final bool agreementSkipped;
  final int rent;
  final int deposit;
  final String address;
  final AgreementAnswers answers;
  final int draftNo;
  final bool draftSent;
  final int draftSentAt;
  final bool ownerAgreedFinal;
  final List<DraftChange> changes;
  final List<DraftVersion> versions;

  /// 0 stamp paper · 1 printing · 2 ready to sign
  final int printStep;
  final bool brokerSigned;
  final bool ownerSigned;
  final int lastAskedAt;

  String get houseName => address.trim().isEmpty ? 'New house' : address;
  String get contactText => channel == 'email' ? contact : '+91 $contact';

  OnboardingPaper paper(String key) =>
      papers.firstWhere((p) => p.key == key, orElse: () => OnboardingPaper(key: key));

  int get approvedCount =>
      papers.where((p) => p.status == PaperStatus.approved || p.status == PaperStatus.notNeeded).length;
  bool get allPapersDone => approvedCount == papers.length;
  int get needYouCount => papers
      .where((p) => p.status == PaperStatus.notClear || p.status == PaperStatus.needsYou)
      .length;
  int get waitingChanges => changes.where((c) => c.status == 'waitingYou').length;

  /// 0 papers · 1 agreement · 2 signing · 3 ready
  int get stage => switch (phase) {
    OnboardingPhase.papers => 0,
    OnboardingPhase.questions || OnboardingPhase.preparing || OnboardingPhase.review => 1,
    OnboardingPhase.printing || OnboardingPhase.signing => 2,
    _ => 3,
  };

  /// Short line for the Home "Continue" panel.
  String get homeTitle => switch (phase) {
    OnboardingPhase.papers => needYouCount > 0 ? '$houseName needs you' : 'Finish $houseName',
    OnboardingPhase.questions => 'Tell us what you agreed',
    OnboardingPhase.review => waitingChanges > 0 ? '$ownerName asked a change' : 'Finish $houseName',
    OnboardingPhase.signing => brokerSigned ? 'Finish $houseName' : 'Sign the agreement',
    _ => 'Finish $houseName',
  };

  String get homeSubtitle => switch (phase) {
    OnboardingPhase.papers => needYouCount > 0
        ? '${PaperKeys.title(papers.firstWhere((p) => p.status == PaperStatus.notClear || p.status == PaperStatus.needsYou).key)} needs you'
        : 'Waiting for ${ownerName.split(' ').first}\'s papers',
    OnboardingPhase.questions => 'Takes 2 minutes',
    OnboardingPhase.preparing => 'We are making the agreement',
    OnboardingPhase.review => waitingChanges > 0
        ? 'Tap to answer'
        : (draftSent ? 'Waiting for ${ownerName.split(' ').first}' : 'Draft $draftNo is ready'),
    OnboardingPhase.printing => 'Getting stamp paper ready',
    OnboardingPhase.signing => brokerSigned ? 'Waiting for ${ownerName.split(' ').first} to sign' : 'Your turn',
    _ => 'Ready',
  };

  PropertyOnboarding copyWith({
    String? ownerName,
    String? channel,
    String? contact,
    List<String>? otherOwners,
    List<OnboardingPaper>? papers,
    String? phase,
    bool? agreementSkipped,
    int? rent,
    int? deposit,
    String? address,
    AgreementAnswers? answers,
    int? draftNo,
    bool? draftSent,
    int? draftSentAt,
    bool? ownerAgreedFinal,
    List<DraftChange>? changes,
    List<DraftVersion>? versions,
    int? printStep,
    bool? brokerSigned,
    bool? ownerSigned,
    int? lastAskedAt,
  }) => PropertyOnboarding(
    id: id,
    ownerName: ownerName ?? this.ownerName,
    channel: channel ?? this.channel,
    contact: contact ?? this.contact,
    createdAt: createdAt,
    otherOwners: otherOwners ?? this.otherOwners,
    papers: papers ?? this.papers,
    phase: phase ?? this.phase,
    agreementSkipped: agreementSkipped ?? this.agreementSkipped,
    rent: rent ?? this.rent,
    deposit: deposit ?? this.deposit,
    address: address ?? this.address,
    answers: answers ?? this.answers,
    draftNo: draftNo ?? this.draftNo,
    draftSent: draftSent ?? this.draftSent,
    draftSentAt: draftSentAt ?? this.draftSentAt,
    ownerAgreedFinal: ownerAgreedFinal ?? this.ownerAgreedFinal,
    changes: changes ?? this.changes,
    versions: versions ?? this.versions,
    printStep: printStep ?? this.printStep,
    brokerSigned: brokerSigned ?? this.brokerSigned,
    ownerSigned: ownerSigned ?? this.ownerSigned,
    lastAskedAt: lastAskedAt ?? this.lastAskedAt,
  );

  PropertyOnboarding withPaper(String key, PaperStatus status, {String reason = '', String? value}) =>
      copyWith(
        papers: [
          for (final p in papers)
            if (p.key == key) p.copyWith(status: status, reason: reason, value: value) else p,
        ],
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'ownerName': ownerName,
    'channel': channel,
    'contact': contact,
    'createdAt': createdAt,
    'otherOwners': otherOwners,
    'papers': [for (final p in papers) p.toJson()],
    'phase': phase,
    'agreementSkipped': agreementSkipped,
    'rent': rent,
    'deposit': deposit,
    'address': address,
    'answers': answers.toJson(),
    'draftNo': draftNo,
    'draftSent': draftSent,
    'draftSentAt': draftSentAt,
    'ownerAgreedFinal': ownerAgreedFinal,
    'changes': [for (final c in changes) c.toJson()],
    'versions': [for (final v in versions) v.toJson()],
    'printStep': printStep,
    'brokerSigned': brokerSigned,
    'ownerSigned': ownerSigned,
    'lastAskedAt': lastAskedAt,
  };

  factory PropertyOnboarding.fromJson(Map<String, dynamic> json) => PropertyOnboarding(
    id: json['id'] as String? ?? '',
    ownerName: json['ownerName'] as String? ?? '',
    channel: json['channel'] as String? ?? 'email',
    contact: json['contact'] as String? ?? '',
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    otherOwners: [
      for (final item in (json['otherOwners'] as List? ?? const [])) item.toString(),
    ],
    papers: [
      for (final item in (json['papers'] as List? ?? const []))
        if (item is Map) OnboardingPaper.fromJson(Map<String, dynamic>.from(item)),
    ],
    phase: json['phase'] as String? ?? OnboardingPhase.papers,
    agreementSkipped: json['agreementSkipped'] as bool? ?? false,
    rent: (json['rent'] as num?)?.toInt() ?? 32000,
    deposit: (json['deposit'] as num?)?.toInt() ?? 192000,
    address: json['address'] as String? ?? '',
    answers: json['answers'] is Map
        ? AgreementAnswers.fromJson(Map<String, dynamic>.from(json['answers'] as Map))
        : const AgreementAnswers(),
    draftNo: (json['draftNo'] as num?)?.toInt() ?? 0,
    draftSent: json['draftSent'] as bool? ?? false,
    draftSentAt: (json['draftSentAt'] as num?)?.toInt() ?? 0,
    ownerAgreedFinal: json['ownerAgreedFinal'] as bool? ?? false,
    changes: [
      for (final item in (json['changes'] as List? ?? const []))
        if (item is Map) DraftChange.fromJson(Map<String, dynamic>.from(item)),
    ],
    versions: [
      for (final item in (json['versions'] as List? ?? const []))
        if (item is Map) DraftVersion.fromJson(Map<String, dynamic>.from(item)),
    ],
    printStep: (json['printStep'] as num?)?.toInt() ?? 0,
    brokerSigned: json['brokerSigned'] as bool? ?? false,
    ownerSigned: json['ownerSigned'] as bool? ?? false,
    lastAskedAt: (json['lastAskedAt'] as num?)?.toInt() ?? 0,
  );
}

/// Keeps onboarding requests on this phone. Sending the real email or
/// WhatsApp message, reading the papers and e-signing need the backend; the
/// "test" helpers below let the broker walk through every step meanwhile.
class PropertyOnboardingStore extends ChangeNotifier {
  PropertyOnboardingStore({SharedPreferences? preferences}) : _preferences = preferences;

  static final PropertyOnboardingStore instance = PropertyOnboardingStore();
  static const _storageKey = 'property_onboardings_v1';

  SharedPreferences? _preferences;
  List<PropertyOnboarding> _items = const [];
  bool _loaded = false;

  bool get loaded => _loaded;
  List<PropertyOnboarding> get items => _items;

  /// Houses still being set up (not ready yet).
  List<PropertyOnboarding> get open =>
      _items.where((item) => item.phase != OnboardingPhase.ready).toList();

  PropertyOnboarding? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      _preferences ??= await SharedPreferences.getInstance();
      final raw = _preferences!.getString(_storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _items = [
            for (final item in decoded)
              if (item is Map) PropertyOnboarding.fromJson(Map<String, dynamic>.from(item)),
          ];
        }
      }
    } catch (_) {
      _items = const [];
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences!.setString(
        _storageKey,
        jsonEncode([for (final item in _items) item.toJson()]),
      );
    } catch (_) {
      // Keeping it in memory is fine if the phone cannot save right now.
    }
  }

  Future<PropertyOnboarding> create({
    required String ownerName,
    required String channel,
    required String contact,
    List<String> otherOwners = const [],
    PropertyOnboarding? carryFrom,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = PropertyOnboarding(
      id: 'onb$now',
      ownerName: ownerName.trim(),
      channel: channel,
      contact: contact.trim(),
      createdAt: now,
      otherOwners: otherOwners,
      lastAskedAt: now,
    );
    // We already have the contact we used to ask, so that paper is ticked.
    var first = item;
    // Same owner, new house: personal ID proofs come from the earlier request.
    // House papers (address, tenant, rent, bank, keys) are asked again.
    if (carryFrom != null) {
      for (final key in const [PaperKeys.aadhaar, PaperKeys.phone, PaperKeys.email]) {
        final old = carryFrom.paper(key);
        if (old.status == PaperStatus.approved) {
          first = first.withPaper(key, PaperStatus.approved, value: old.value);
        }
      }
    }
    // The contact we used to ask is always ticked.
    first = channel == 'email'
        ? first.withPaper(PaperKeys.email, PaperStatus.approved, value: contact.trim())
        : first.withPaper(PaperKeys.phone, PaperStatus.approved, value: '+91 ${contact.trim()}');
    _items = [first, ..._items];
    notifyListeners();
    await _save();
    return first;
  }

  Future<void> update(String id, PropertyOnboarding Function(PropertyOnboarding) change) async {
    _items = [
      for (final item in _items)
        if (item.id == id) change(item) else item,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _items = [for (final item in _items) if (item.id != id) item];
    notifyListeners();
    await _save();
  }

  // ---- Test helpers: pretend the owner or our team did something. ----

  Future<void> testOwnerSendsPapers(String id) => update(id, (item) {
    var next = item
        .withPaper(
          PaperKeys.aadhaar,
          PaperStatus.needsYou,
          reason: 'Name on Aadhaar: ${item.ownerName.split(' ').first} K. You typed: ${item.ownerName}.',
          value: '${item.ownerName.split(' ').first} K · XXXX 4821',
        )
        .withPaper(PaperKeys.phone, PaperStatus.approved, value: item.channel == 'whatsapp' ? '+91 ${item.contact}' : '+91 98765 43210')
        .withPaper(PaperKeys.email, PaperStatus.approved, value: item.channel == 'email' ? item.contact : 'owner@gmail.com')
        .withPaper(PaperKeys.tenantAgreement, PaperStatus.checking)
        .withPaper(PaperKeys.rentDeposit, PaperStatus.approved, value: '₹ 32,000 · ₹ 1,92,000')
        .withPaper(PaperKeys.bank, PaperStatus.notClear, reason: 'The photo is blurry. We cannot read the account number.');
    next = next.copyWith(
      rent: 32000,
      deposit: 192000,
      lastAskedAt: DateTime.now().millisecondsSinceEpoch - const Duration(hours: 3).inMilliseconds,
    );
    return next;
  });

  Future<void> testFixAllPapers(String id) => update(id, (item) {
    var next = item;
    for (final paper in item.papers) {
      if (paper.status == PaperStatus.approved || paper.status == PaperStatus.notNeeded) continue;
      final value = switch (paper.key) {
        PaperKeys.tenantAgreement => 'Anil Sharma · ₹ 28,000 · ends 31 Mar 2027',
        PaperKeys.bank => 'HDFC Bank · 5010 0234 5612 34',
        PaperKeys.address => 'Flat 402, Sri Sai Residency, Madhapur, Hyderabad 500081',
        PaperKeys.keys => 'Suresh (watchman) · +91 90000 11122',
        _ => 'Received',
      };
      next = next.withPaper(paper.key, PaperStatus.approved, value: value);
    }
    return next.copyWith(address: 'Flat 402, Madhapur');
  });

  Future<void> testDraftReady(String id) => update(id, (item) => item.copyWith(
    phase: OnboardingPhase.review,
    draftNo: 1,
    draftSent: false,
    versions: [
      DraftVersion(number: 1, summary: 'First draft', at: DateTime.now().millisecondsSinceEpoch),
    ],
  ));

  Future<void> testOwnerAsksChange(String id) => update(id, (item) {
    final before = item.answers.feeSummary(item.rent);
    return item.copyWith(
      changes: [
        ...item.changes,
        DraftChange(
          id: 'c${item.changes.length + 1}',
          clause: 'Your fee',
          before: before,
          asked: '4% of rent every month',
          askedBy: 'owner',
          note: 'Please make it 4%. The rent is already high.',
        ),
      ],
    );
  });

  Future<void> testOwnerAgrees(String id) => update(id, (item) => item.copyWith(
    ownerAgreedFinal: true,
    changes: [
      for (final c in item.changes)
        if (c.status == 'waitingOwner') c.copyWith(status: 'agreed') else c,
    ],
  ));

  Future<void> testNextPrintStep(String id) => update(id, (item) {
    final step = item.printStep + 1;
    return item.copyWith(
      printStep: step.clamp(0, 2),
      phase: step >= 2 ? OnboardingPhase.signing : OnboardingPhase.printing,
    );
  });

  Future<void> testOwnerSigns(String id) => update(id, (item) {
    final done = item.brokerSigned;
    return item.copyWith(ownerSigned: true, phase: done ? OnboardingPhase.ready : item.phase);
  });
}
