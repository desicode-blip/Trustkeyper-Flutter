import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BrokerProperty {
  BrokerProperty({
    required this.id,
    required this.address,
    required this.rooms,
    required this.floor,
    required this.totalFloors,
    required this.furnishing,
    this.sizeSqFt,
    this.facing,
    this.carParking = 0,
    this.bikeParking = 0,
    Map<String, int> inventory = const {},
  }) : inventory = Map.unmodifiable(inventory);

  final String id;
  final String address;
  final String rooms;
  final int floor;
  final int totalFloors;
  final String furnishing;
  final double? sizeSqFt;
  final String? facing;
  final int carParking;
  final int bikeParking;
  final Map<String, int> inventory;

  String get displayName =>
      address.trim().isEmpty ? 'Unnamed property' : address;

  String? get validationError {
    if (sizeSqFt != null && (!sizeSqFt!.isFinite || sizeSqFt! <= 0)) {
      return 'Enter a valid size';
    }
    if (!roomChoices.contains(rooms)) return 'Choose the rooms';
    if (!furnishingChoices.contains(furnishing)) return 'Choose the furnishing';
    if (floor < 0 || totalFloors < floor || totalFloors > 200) {
      return 'Total floors cannot be less than the property floor';
    }
    if (facing != null && !directions.contains(facing)) {
      return 'Choose a valid direction';
    }
    if (carParking < 0 ||
        carParking > 100 ||
        bikeParking < 0 ||
        bikeParking > 100) {
      return 'Enter valid parking counts';
    }
    if (inventory.entries.any(
      (entry) =>
          entry.key.trim().isEmpty || entry.value < 0 || entry.value > 100,
    )) {
      return 'Enter valid inventory counts';
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    'address': address.trim(),
    'rooms': rooms,
    'floor': floor,
    'totalFloors': totalFloors,
    'furnishing': furnishing,
    'sizeSqFt': sizeSqFt,
    'facing': facing,
    'carParking': carParking,
    'bikeParking': bikeParking,
    'inventory': inventory,
  };

  factory BrokerProperty.fromMap(String id, Map<String, dynamic> data) {
    final values = data['inventory'];
    return BrokerProperty(
      id: id,
      address:
          data['address'] is String &&
              (data['address'] as String).trim().isNotEmpty
          ? data['address'] as String
          : data['propertyAddress'] is String &&
                (data['propertyAddress'] as String).trim().isNotEmpty
          ? data['propertyAddress'] as String
          : data['name'] is String
          ? data['name'] as String
          : '',
      rooms: data['rooms'] is String ? data['rooms'] as String : '',
      floor: (data['floor'] as num?)?.toInt() ?? 0,
      totalFloors: (data['totalFloors'] as num?)?.toInt() ?? 0,
      furnishing: data['furnishing'] is String
          ? data['furnishing'] as String
          : '',
      sizeSqFt: (data['sizeSqFt'] as num?)?.toDouble(),
      facing: data['facing'] as String?,
      carParking: (data['carParking'] as num?)?.toInt() ?? 0,
      bikeParking: (data['bikeParking'] as num?)?.toInt() ?? 0,
      inventory: values is Map
          ? {
              for (final entry in values.entries)
                if (entry.key is String && entry.value is num)
                  entry.key as String: (entry.value as num).toInt(),
            }
          : {},
    );
  }

  static const roomChoices = [
    '1 RK',
    '1 BHK',
    '1.5 BHK',
    '2 BHK',
    '2.5 BHK',
    '3 BHK',
    '3.5 BHK',
    '4 BHK',
    '4+ BHK',
  ];
  static const furnishingChoices = ['Empty', 'Semi', 'Full'];
  static const directions = [
    'North-West',
    'North',
    'North-East',
    'West',
    'East',
    'South-West',
    'South',
    'South-East',
  ];
  static const inventoryItems = [
    'Fan',
    'Light',
    'AC',
    'Geyser',
    'Cupboard',
    'Bed',
  ];
}

abstract interface class BrokerPropertyRepository {
  Stream<List<BrokerProperty>> watchProperties();
  Future<BrokerProperty> save(BrokerProperty property);
}

class FirebaseBrokerPropertyRepository implements BrokerPropertyRepository {
  FirebaseBrokerPropertyRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Stream<List<BrokerProperty>> watchProperties() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(const []);
    return _firestore
        .collection('properties')
        .where('participantUids', arrayContains: user.uid)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .where((document) => document.data()['brokerUid'] == user.uid)
                  .map(
                    (document) =>
                        BrokerProperty.fromMap(document.id, document.data()),
                  )
                  .toList()
                ..sort((left, right) => left.address.compareTo(right.address)),
        );
  }

  @override
  Future<BrokerProperty> save(BrokerProperty property) async {
    final error = property.validationError;
    if (error != null) throw StateError(error);
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Your session expired. Please log in again.');
    }
    final document = _firestore
        .collection('properties')
        .doc(property.id.isEmpty ? null : property.id);
    final data = property.toMap();
    if (property.id.isEmpty) {
      await document.set({
        ...data,
        'brokerUid': user.uid,
        'participantUids': [user.uid],
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await document.update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return BrokerProperty.fromMap(document.id, data);
  }
}
