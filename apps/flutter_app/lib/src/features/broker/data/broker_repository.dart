import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BrokerProfile {
  const BrokerProfile({
    required this.displayName,
    required this.email,
    required this.phone,
    required this.approvalStatus,
    this.paused = false,
    this.bankName,
    this.bankAccountLast4,
  });

  final String displayName;
  final String email;
  final String phone;
  final String approvalStatus;
  final bool paused;
  final String? bankName;
  final String? bankAccountLast4;

  String get greetingName {
    final normalized = displayName.trim();
    if (normalized.isEmpty) return 'there';
    return normalized.split(RegExp(r'\s+')).first;
  }

  String get initial {
    final normalized = displayName.trim();
    return normalized.isEmpty ? 'B' : normalized.substring(0, 1).toUpperCase();
  }

  bool get hasBankAccount => bankAccountLast4?.trim().isNotEmpty == true;

  bool get canCreateAgreements => approvalStatus == 'approved' && !paused;

  factory BrokerProfile.fromMap(Map<String, dynamic> data, {User? authUser}) {
    return BrokerProfile(
      displayName: _string(data['displayName']) ?? authUser?.displayName ?? '',
      email: _string(data['email']) ?? authUser?.email ?? '',
      phone: authUser?.phoneNumber ?? _string(data['phone']) ?? '',
      approvalStatus: _string(data['approvalStatus']) ?? 'pending',
      paused: data['paused'] == true,
      bankName: _string(data['bankName']),
      bankAccountLast4:
          _string(data['bankAccountLast4']) ??
          _string(data['payoutBankAccountLast4']),
    );
  }

  factory BrokerProfile.fromAuthUser(User? user) => BrokerProfile(
    displayName: user?.displayName ?? '',
    email: user?.email ?? '',
    phone: user?.phoneNumber ?? '',
    approvalStatus: 'pending',
  );
}

class BrokerAgreementSummary {
  const BrokerAgreementSummary({
    required this.id,
    required this.property,
    required this.people,
    required this.status,
    required this.monthlyRentPaise,
    required this.updatedAt,
    this.revision = 0,
    this.copyMode,
    this.propertyId,
    this.details = const {},
  });

  final String id;
  final String property;
  final String people;
  final String status;
  final int? monthlyRentPaise;
  final DateTime? updatedAt;
  final int revision;
  final String? copyMode;
  final String? propertyId;
  final Map<String, dynamic> details;

  factory BrokerAgreementSummary.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final partyNames = (data['partyNames'] as List?)
        ?.whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .join(', ');
    return BrokerAgreementSummary(
      id: document.id,
      details: Map.unmodifiable(data),
      propertyId: _string(data['propertyId']),
      property:
          _string(data['propertyAddress']) ??
          _string(data['propertyName']) ??
          'Property details pending',
      people: partyNames ?? _string(data['people']) ?? 'People not added yet',
      status: _string(data['status']) ?? 'draft',
      monthlyRentPaise:
          _integer(data['monthlyRentPaise']) ??
          _rupeesToPaise(data['monthlyRent']),
      updatedAt: _dateTime(data['updatedAt']),
      revision: _integer(data['revision']) ?? 0,
      copyMode:
          data['agreementCopy'] is Map &&
              (data['agreementCopy'] as Map)['revision'] == data['revision']
          ? (data['agreementCopy'] as Map)['mode'] as String?
          : null,
    );
  }
}

class BrokerPaymentSummary {
  const BrokerPaymentSummary({
    required this.id,
    required this.label,
    required this.amountPaise,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String label;
  final int amountPaise;
  final String status;
  final DateTime? createdAt;

  static bool belongsToBroker(Map<String, dynamic> data, String uid) =>
      data['recipientUid'] == uid && data['kind'] == 'brokerage';

  factory BrokerPaymentSummary.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return BrokerPaymentSummary(
      id: document.id,
      label:
          _string(data['propertyAddress']) ??
          _string(data['description']) ??
          'Brokerage payment',
      amountPaise:
          _integer(data['amountPaise']) ?? _rupeesToPaise(data['amount']) ?? 0,
      status: _string(data['status']) ?? 'pending',
      createdAt:
          _dateTime(data['createdAt']) ??
          _dateTime(data['paidAt']) ??
          (data['createdAtMs'] is int
              ? DateTime.fromMillisecondsSinceEpoch(data['createdAtMs'] as int)
              : null),
    );
  }
}

abstract interface class BrokerRepository {
  Stream<BrokerProfile> watchProfile();

  Stream<List<BrokerAgreementSummary>> watchAgreements();

  Stream<List<BrokerPaymentSummary>> watchPayments();
}

class FirebaseBrokerRepository implements BrokerRepository {
  FirebaseBrokerRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Stream<BrokerProfile> watchProfile() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(BrokerProfile.fromAuthUser(null));
    return _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .map(
          (snapshot) => BrokerProfile.fromMap(
            snapshot.data() ?? const <String, dynamic>{},
            authUser: user,
          ),
        );
  }

  @override
  Stream<List<BrokerAgreementSummary>> watchAgreements() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(const []);
    return _firestore
        .collection('agreements')
        .where('participantUids', arrayContains: user.uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((document) => document.data()['brokerUid'] == user.uid)
              .map(BrokerAgreementSummary.fromDocument)
              .toList(growable: false),
        );
  }

  @override
  Stream<List<BrokerPaymentSummary>> watchPayments() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(const []);
    return _firestore
        .collection('payouts')
        .where('participantUids', arrayContains: user.uid)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .where(
                    (document) => BrokerPaymentSummary.belongsToBroker(
                      document.data(),
                      user.uid,
                    ),
                  )
                  .map(BrokerPaymentSummary.fromDocument)
                  .toList(growable: false)
                ..sort(
                  (left, right) => (right.createdAt ?? DateTime(1970))
                      .compareTo(left.createdAt ?? DateTime(1970)),
                ),
        );
  }
}

String? _string(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

int? _rupeesToPaise(Object? value) {
  if (value is num) return (value * 100).round();
  final parsed = double.tryParse(value?.toString() ?? '');
  return parsed == null ? null : (parsed * 100).round();
}

DateTime? _dateTime(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
