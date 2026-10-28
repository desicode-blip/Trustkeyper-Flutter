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
  /// Papers each owner gives about themselves. The rest are about the house.
  static const personal = [aadhaar, phone, email];
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

/// One part of the agreement the broker changed after the first draft. It
/// remembers how that part was before, so the change can be undone.
class AgreementEdit {
  const AgreementEdit({required this.group, required this.before});

  /// fee · dates · notes
  final String group;
  final AgreementAnswers before;

  Map<String, Object?> toJson() => {'group': group, 'before': before.toJson()};
  factory AgreementEdit.fromJson(Map<String, dynamic> json) => AgreementEdit(
    group: json['group'] as String? ?? 'fee',
    before: json['before'] is Map
        ? AgreementAnswers.fromJson(Map<String, dynamic>.from(json['before'] as Map))
        : const AgreementAnswers(),
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

  /// days (one time) · daysMonthly · percent · fixed · once · none (no fee) · later (decided on every deal)
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

  /// The parts of the agreement the broker can change.
  static const groups = ['fee', 'dates', 'notes'];

  static String groupLabel(String group) => switch (group) {
    'fee' => 'Your fee',
    'dates' => 'Start date and length',
    _ => 'Other notes',
  };

  /// This part of the answers, in simple words.
  String groupText(String group, int rent) => switch (group) {
    'fee' => feeHasNoAmount ? feeSummary(rent) : '${feeSummary(rent)}. $payWayText',
    'dates' => '${startDate.isEmpty ? 'No start date' : startDate} · $months months',
    _ => notes.trim().isEmpty ? 'None' : notes.trim(),
  };

  /// Takes one part from [other] and keeps the rest.
  AgreementAnswers withGroup(String group, AgreementAnswers other) => switch (group) {
    'fee' => copyWith(feeType: other.feeType, feeValue: other.feeValue, payWay: other.payWay),
    'dates' => copyWith(startDate: other.startDate, months: other.months),
    _ => copyWith(notes: other.notes),
  };

  bool sameGroup(String group, AgreementAnswers other) => switch (group) {
    'fee' => feeType == other.feeType && feeValue == other.feeValue && payWay == other.payWay,
    'dates' => startDate == other.startDate && months == other.months,
    _ => notes.trim() == other.notes.trim(),
  };

  /// No amount to type: no fee at all, or decided on every deal.
  bool get feeHasNoAmount => feeType == 'none' || feeType == 'later';

  String feeSummary(int rent) {
    String money(num value) => '₹ ${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}';
    return switch (feeType) {
      'daysMonthly' => '${feeValue.toStringAsFixed(feeValue % 1 == 0 ? 0 : 1)} days of rent every month '
          '(${money(rent / 30 * feeValue)} each month)',
      'none' => 'No fee. We do not charge the owner',
      'later' => 'Decided on every deal. We will agree it each time',
      'days' => '${feeValue.toStringAsFixed(0)} days of rent, once '
          '(${money(rent / 30 * feeValue)})',
      'percent' => '${feeValue.toStringAsFixed(feeValue % 1 == 0 ? 0 : 1)}% of rent every month '
          '(${money(rent * feeValue / 100)})',
      'fixed' => '${money(feeValue)} every month',
      'once' => '${money(feeValue)} one time',
      _ => 'Not set',
    };
  }

  String get payWayText => feeType == 'none'
      ? 'No fee to pay'
      : feeType == 'later'
          ? 'Decided on every deal'
          : _payWayOnly;

  /// A fee paid once (days of rent, or a fixed amount, one time).
  bool get feeIsOneTime => feeType == 'days' || feeType == 'once';

  String get _payWayOnly => switch (payWay) {
    'cut' => feeIsOneTime ? 'We deduct it from the first month\'s rent' : 'We deduct it from every month\'s rent',
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

/// An owner after the first one. Each owner has their own Aadhaar, phone and
/// email papers, their own reminders and their own signature.
class CoOwner {
  CoOwner({
    required this.name,
    required this.channel,
    required this.contact,
    List<OnboardingPaper>? papers,
    this.signed = false,
    this.lastAskedAt = 0,
  }) : papers = List.unmodifiable(
         papers ??
             [
               for (final key in PaperKeys.personal)
                 // The contact we used to ask is already known.
                 if ((channel == 'email' && key == PaperKeys.email) || (channel != 'email' && key == PaperKeys.phone))
                   OnboardingPaper(
                     key: key,
                     status: PaperStatus.approved,
                     value: channel == 'email' ? contact : '+91 $contact',
                   )
                 else
                   OnboardingPaper(key: key),
             ],
       );

  final String name;

  /// 'email' or 'whatsapp'.
  final String channel;
  final String contact;
  final List<OnboardingPaper> papers;
  final bool signed;
  final int lastAskedAt;

  String get contactText => channel == 'email' ? contact : '+91 $contact';
  String get firstName => name.trim().split(' ').first;

  OnboardingPaper paper(String key) =>
      papers.firstWhere((p) => p.key == key, orElse: () => OnboardingPaper(key: key));

  CoOwner copyWith({
    String? name,
    String? channel,
    String? contact,
    List<OnboardingPaper>? papers,
    bool? signed,
    int? lastAskedAt,
  }) => CoOwner(
    name: name ?? this.name,
    channel: channel ?? this.channel,
    contact: contact ?? this.contact,
    papers: papers ?? this.papers,
    signed: signed ?? this.signed,
    lastAskedAt: lastAskedAt ?? this.lastAskedAt,
  );

  CoOwner withPaper(String key, PaperStatus status, {String reason = '', String? value}) => copyWith(
    papers: [
      for (final p in papers)
        if (p.key == key) p.copyWith(status: status, reason: reason, value: value) else p,
    ],
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'channel': channel,
    'contact': contact,
    'papers': [for (final p in papers) p.toJson()],
    'signed': signed,
    'lastAskedAt': lastAskedAt,
  };

  factory CoOwner.fromJson(Map<String, dynamic> json) => CoOwner(
    name: json['name'] as String? ?? '',
    channel: json['channel'] as String? ?? 'email',
    contact: json['contact'] as String? ?? '',
    papers: json['papers'] is List
        ? [
            for (final item in json['papers'] as List)
              if (item is Map) OnboardingPaper.fromJson(Map<String, dynamic>.from(item)),
          ]
        : null,
    signed: json['signed'] as bool? ?? false,
    lastAskedAt: (json['lastAskedAt'] as num?)?.toInt() ?? 0,
  );

  /// Older saves kept other owners as "Name · contact" text.
  factory CoOwner.fromText(String text) {
    final parts = text.split(' · ');
    final contact = parts.length > 1 ? parts.sublist(1).join(' · ') : '';
    final isEmail = contact.contains('@');
    return CoOwner(
      name: parts.first,
      channel: isEmail ? 'email' : 'whatsapp',
      contact: isEmail ? contact : contact.replaceFirst('+91 ', ''),
    );
  }
}

class PropertyOnboarding {
  PropertyOnboarding({
    required this.id,
    required this.ownerName,
    required this.channel,
    required this.contact,
    required this.createdAt,
    List<CoOwner> coOwners = const [],
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
    this.readyAck = true,
    List<DraftChange> changes = const [],
    List<DraftVersion> versions = const [],
    List<AgreementEdit> edits = const [],
    this.printStep = 0,
    this.brokerSigned = false,
    this.ownerSigned = false,
    this.lastAskedAt = 0,
  }) : coOwners = List.unmodifiable(coOwners),
       papers = List.unmodifiable(
         ([...(papers ?? [for (final key in PaperKeys.all) OnboardingPaper(key: key)])])
           ..sort((a, b) => PaperKeys.all.indexOf(a.key).compareTo(PaperKeys.all.indexOf(b.key))),
       ),
       changes = List.unmodifiable(changes),
       versions = List.unmodifiable(versions),
       edits = List.unmodifiable(edits);

  final String id;
  final String ownerName;

  /// 'email' or 'whatsapp'.
  final String channel;
  final String contact;
  final int createdAt;
  final List<CoOwner> coOwners;
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

  /// False from the moment the first draft is ready until the broker taps Next on the "ready" page.
  final bool readyAck;
  final List<DraftChange> changes;
  final List<DraftVersion> versions;

  /// Parts the broker changed after the first draft (shown green, can be undone).
  final List<AgreementEdit> edits;

  /// 0 stamp paper · 1 printing · 2 ready to sign
  final int printStep;
  final bool brokerSigned;
  final bool ownerSigned;
  final int lastAskedAt;

  String get houseName => address.trim().isEmpty ? 'New house' : address;
  String get contactText => channel == 'email' ? contact : '+91 $contact';

  OnboardingPaper paper(String key) =>
      papers.firstWhere((p) => p.key == key, orElse: () => OnboardingPaper(key: key));

  // ---- owners: owner 0 is the main owner, 1.. are the other owners ----

  int get ownerCount => 1 + coOwners.length;
  bool get hasManyOwners => coOwners.isNotEmpty;
  String ownerNameAt(int owner) => owner == 0 ? ownerName : coOwners[owner - 1].name;
  String ownerFirstAt(int owner) => ownerNameAt(owner).trim().split(' ').first;
  String ownerChannelAt(int owner) => owner == 0 ? channel : coOwners[owner - 1].channel;
  String ownerContactAt(int owner) => owner == 0 ? contact : coOwners[owner - 1].contact;
  String ownerContactTextAt(int owner) => owner == 0 ? contactText : coOwners[owner - 1].contactText;
  int ownerAskedAt(int owner) => owner == 0 ? lastAskedAt : coOwners[owner - 1].lastAskedAt;
  bool ownerSignedAt(int owner) => owner == 0 ? ownerSigned : coOwners[owner - 1].signed;

  /// "Avg", "Avg and Ravi", "Avg, Ravi and Sam".
  String get ownersFirst {
    final names = [for (var i = 0; i < ownerCount; i++) ownerFirstAt(i)];
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  String get ownersFull => [for (var i = 0; i < ownerCount; i++) ownerNameAt(i)].join(', ');

  /// Aadhaar, phone and email of one owner.
  List<OnboardingPaper> personalPapersAt(int owner) => owner == 0
      ? [for (final p in papers) if (PaperKeys.personal.contains(p.key)) p]
      : coOwners[owner - 1].papers;

  /// Papers about the house: asked once, from the main owner.
  List<OnboardingPaper> get sharedPapers => [for (final p in papers) if (!PaperKeys.personal.contains(p.key)) p];

  OnboardingPaper paperAt(int owner, String key) => owner == 0 ? paper(key) : coOwners[owner - 1].paper(key);

  PropertyOnboarding withOwnerPaper(int owner, String key, PaperStatus status, {String reason = '', String? value}) {
    if (owner == 0) return withPaper(key, status, reason: reason, value: value);
    return copyWith(
      coOwners: [
        for (var i = 0; i < coOwners.length; i++)
          if (i == owner - 1) coOwners[i].withPaper(key, status, reason: reason, value: value) else coOwners[i],
      ],
    );
  }

  PropertyOnboarding withOwnerAsked(int owner, int at) => owner == 0
      ? copyWith(lastAskedAt: at)
      : copyWith(
          coOwners: [
            for (var i = 0; i < coOwners.length; i++)
              if (i == owner - 1) coOwners[i].copyWith(lastAskedAt: at) else coOwners[i],
          ],
        );

  static bool _isOk(OnboardingPaper p) => p.status == PaperStatus.approved || p.status == PaperStatus.notNeeded;
  static bool _isNeed(OnboardingPaper p) => p.status == PaperStatus.notClear || p.status == PaperStatus.needsYou;

  Iterable<OnboardingPaper> get _everyPaper => [...papers, for (final c in coOwners) ...c.papers];

  /// Papers of this owner only. For the main owner this is Aadhaar, phone and email.
  bool ownerPapersDone(int owner) => personalPapersAt(owner).every(_isOk);
  int ownerNeedYouAt(int owner) => personalPapersAt(owner).where(_isNeed).length;
  bool get sharedPapersDone => sharedPapers.every(_isOk);
  int get sharedNeedYou => sharedPapers.where(_isNeed).length;

  /// First owner (0..) who has a paper that needs the broker, or -1.
  int get firstOwnerNeedingYou {
    for (var i = 0; i < ownerCount; i++) {
      if (ownerNeedYouAt(i) > 0) return i;
    }
    return -1;
  }

  int get approvedCount => _everyPaper.where(_isOk).length;
  bool get allPapersDone => approvedCount == _everyPaper.length;
  int get needYouCount => _everyPaper.where(_isNeed).length;

  /// Everyone has signed (main owner and the others).
  bool get allOwnersSigned => ownerSigned && coOwners.every((c) => c.signed);
  int get signedOwners => (ownerSigned ? 1 : 0) + coOwners.where((c) => c.signed).length;

  /// The first draft is ready and the broker has not seen the "ready" page yet.
  bool get agreementJustReady => phase == OnboardingPhase.review && !readyAck && !draftSent;

  /// The draft is with the owner(s) and they have not said yes yet.
  bool get underOwnerReview => phase == OnboardingPhase.review && draftSent && !ownerAgreedFinal && waitingChanges == 0;

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
    OnboardingPhase.review => waitingChanges > 0
        ? '$ownerName asked a change'
        : agreementJustReady
            ? 'Agreement is ready'
            : underOwnerReview
                ? 'Agreement under review'
                : 'Finish $houseName',
    OnboardingPhase.signing => brokerSigned ? 'Finish $houseName' : 'Sign the agreement',
    _ => 'Finish $houseName',
  };

  String get homeSubtitle => switch (phase) {
    OnboardingPhase.papers => needYouCount > 0
        ? (hasManyOwners
              ? '${ownerFirstAt(firstOwnerNeedingYou < 0 ? 0 : firstOwnerNeedingYou)} · ${PaperKeys.title(_everyPaper.firstWhere(_isNeed).key)} needs you'
              : '${PaperKeys.title(_everyPaper.firstWhere(_isNeed).key)} needs you')
        : 'Waiting for $ownersFirst\'s documents',
    OnboardingPhase.questions => 'Takes 2 minutes',
    OnboardingPhase.preparing => 'We are making the agreement',
    OnboardingPhase.review => waitingChanges > 0
        ? 'Tap to answer'
        : (draftSent ? '$ownersFirst is reviewing it' : 'Review it, then send for signing'),
    OnboardingPhase.printing => 'Getting stamp paper ready',
    OnboardingPhase.signing => brokerSigned ? 'Waiting for $ownersFirst to sign' : 'Your turn',
    _ => 'Ready',
  };

  PropertyOnboarding copyWith({
    String? ownerName,
    String? channel,
    String? contact,
    List<CoOwner>? coOwners,
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
    bool? readyAck,
    List<DraftChange>? changes,
    List<DraftVersion>? versions,
    List<AgreementEdit>? edits,
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
    coOwners: coOwners ?? this.coOwners,
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
    readyAck: readyAck ?? this.readyAck,
    changes: changes ?? this.changes,
    versions: versions ?? this.versions,
    edits: edits ?? this.edits,
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
    'coOwners': [for (final c in coOwners) c.toJson()],
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
    'readyAck': readyAck,
    'changes': [for (final c in changes) c.toJson()],
    'versions': [for (final v in versions) v.toJson()],
    'edits': [for (final e in edits) e.toJson()],
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
    coOwners: json['coOwners'] is List
        ? [
            for (final item in json['coOwners'] as List)
              if (item is Map) CoOwner.fromJson(Map<String, dynamic>.from(item)),
          ]
        : [
            for (final item in (json['otherOwners'] as List? ?? const [])) CoOwner.fromText(item.toString()),
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
    readyAck: json['readyAck'] as bool? ?? true,
    changes: [
      for (final item in (json['changes'] as List? ?? const []))
        if (item is Map) DraftChange.fromJson(Map<String, dynamic>.from(item)),
    ],
    versions: [
      for (final item in (json['versions'] as List? ?? const []))
        if (item is Map) DraftVersion.fromJson(Map<String, dynamic>.from(item)),
    ],
    edits: [
      for (final item in (json['edits'] as List? ?? const []))
        if (item is Map) AgreementEdit.fromJson(Map<String, dynamic>.from(item)),
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
    List<CoOwner> coOwners = const [],
    PropertyOnboarding? carryFrom,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = PropertyOnboarding(
      id: 'onb$now',
      ownerName: ownerName.trim(),
      channel: channel,
      contact: contact.trim(),
      createdAt: now,
      coOwners: [for (final c in coOwners) _withKnownProofs(c, now)],
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

  /// An extra owner we already know (same phone or email as someone from an
  /// earlier house) keeps the ID proofs that were approved before.
  CoOwner _withKnownProofs(CoOwner owner, int now) {
    var next = owner.copyWith(lastAskedAt: now);
    for (final old in _items) {
      final known = <(String, String, List<OnboardingPaper>)>[
        (old.channel, old.contact, old.personalPapersAt(0)),
        for (final c in old.coOwners) (c.channel, c.contact, c.papers),
      ];
      for (final (channel, contact, papers) in known) {
        if (channel != owner.channel || contact.toLowerCase() != owner.contact.toLowerCase()) continue;
        for (final paper in papers) {
          if (paper.status == PaperStatus.approved) {
            next = next.withPaper(paper.key, PaperStatus.approved, value: paper.value);
          }
        }
        return next;
      }
    }
    return next;
  }

  /// The broker forgot an owner: add them to a house that is still being set up.
  Future<void> addOwner(String id, CoOwner owner) => update(id, (item) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return item.copyWith(coOwners: [...item.coOwners, _withKnownProofs(owner, now)]);
  });

  /// Take an extra owner off the house. The main owner (first) cannot be removed.
  Future<void> removeOwner(String id, int owner) => update(id, (item) {
    if (owner < 1 || owner > item.coOwners.length) return item;
    return item.copyWith(coOwners: [
      for (var i = 0; i < item.coOwners.length; i++)
        if (i != owner - 1) item.coOwners[i],
    ]);
  });

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

  Future<void> testOwnerSendsPapers(String id, {int owner = 0}) => update(id, (item) {
    if (owner > 0 && owner <= item.coOwners.length) {
      // An extra owner only gives Aadhaar, phone and email.
      final first = item.ownerFirstAt(owner);
      return item
          .withOwnerPaper(owner, PaperKeys.aadhaar, PaperStatus.approved, value: '$first S · XXXX 7305')
          .withOwnerPaper(
            owner,
            PaperKeys.phone,
            PaperStatus.approved,
            value: item.ownerChannelAt(owner) == 'whatsapp' ? '+91 ${item.ownerContactAt(owner)}' : '+91 98765 11223',
          )
          .withOwnerPaper(
            owner,
            PaperKeys.email,
            PaperStatus.approved,
            value: item.ownerChannelAt(owner) == 'email' ? item.ownerContactAt(owner) : 'coowner@gmail.com',
          )
          .withOwnerAsked(owner, DateTime.now().millisecondsSinceEpoch - const Duration(hours: 3).inMilliseconds);
    }
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
    for (var o = 1; o < item.ownerCount; o++) {
      for (final paper in item.personalPapersAt(o)) {
        if (paper.status == PaperStatus.approved || paper.status == PaperStatus.notNeeded) continue;
        next = next.withOwnerPaper(o, paper.key, PaperStatus.approved, value: 'Received');
      }
    }
    return next.copyWith(address: 'Flat 402, Madhapur');
  });

  /// The broker changes one part of the agreement. After the first draft the
  /// change is remembered (so it shows green and can be undone). If the owner
  /// already has the draft, it becomes a new draft and they must say yes again.
  Future<void> changeAgreementPart(String id, String group, AgreementAnswers next) => update(id, (item) {
    final old = item.answers;
    if (old.sameGroup(group, next)) return item;
    final merged = old.withGroup(group, next);
    var result = item.copyWith(answers: merged);
    if (item.phase != OnboardingPhase.review) return result;
    final edits = [...item.edits];
    final at = edits.indexWhere((e) => e.group == group);
    final before = at >= 0 ? edits[at].before : old;
    if (before.sameGroup(group, merged)) {
      if (at >= 0) edits.removeAt(at);
    } else if (at >= 0) {
      edits[at] = AgreementEdit(group: group, before: before);
    } else {
      edits.add(AgreementEdit(group: group, before: before));
    }
    result = result.copyWith(edits: edits);
    return _newDraftIfSent(result, 'You changed: ${AgreementAnswers.groupLabel(group)}');
  });

  /// Puts one changed part back the way it was in the first draft.
  Future<void> undoAgreementPart(String id, String group) => update(id, (item) {
    final at = item.edits.indexWhere((e) => e.group == group);
    if (at < 0) return item;
    final result = item.copyWith(
      answers: item.answers.withGroup(group, item.edits[at].before),
      edits: [...item.edits]..removeAt(at),
    );
    return _newDraftIfSent(result, 'You undid: ${AgreementAnswers.groupLabel(group)}');
  });

  PropertyOnboarding _newDraftIfSent(PropertyOnboarding item, String summary) {
    if (!item.draftSent) return item;
    final now = DateTime.now().millisecondsSinceEpoch;
    // A new draft the broker must send again for signing.
    return item.copyWith(
      ownerAgreedFinal: false,
      draftSent: false,
      draftNo: item.draftNo + 1,
      versions: [...item.versions, DraftVersion(number: item.draftNo + 1, summary: summary, at: now)],
    );
  }

  Future<void> testDraftReady(String id) => update(id, (item) => item.copyWith(
    phase: OnboardingPhase.review,
    draftNo: 1,
    draftSent: false,
    readyAck: false,
    edits: const [],
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

  /// Pretend one owner signs. Without a number, the next owner who has not signed.
  Future<void> testOwnerSigns(String id, {int? owner}) => update(id, (item) {
    var next = item;
    final who = owner ?? [for (var i = 0; i < item.ownerCount; i++) i].firstWhere((i) => !item.ownerSignedAt(i), orElse: () => -1);
    if (who == 0) {
      next = next.copyWith(ownerSigned: true);
    } else if (who > 0) {
      next = next.copyWith(coOwners: [
        for (var i = 0; i < next.coOwners.length; i++)
          if (i == who - 1) next.coOwners[i].copyWith(signed: true) else next.coOwners[i],
      ]);
    }
    return next.copyWith(phase: next.brokerSigned && next.allOwnersSigned ? OnboardingPhase.ready : next.phase);
  });
}
