import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'tk2_link.dart';
import 'tk2_store.dart';

/// TrustKeeper 2 backend (Firebase). OFF unless the app is built with the
/// staging settings, e.g. `--dart-define-from-file=tk2_cloud.json`
/// (template: `apps/flutter_app/tk2_cloud.example.json`). Off = the demo build:
/// everything stays on the device. See docs/TRUSTKEEPER2-BACKEND.md.
///
/// Collections (all start with tk2):
/// - tk2Brokers/{uid}: broker profile (name, phone, default token, contacts, account)
/// - tk2Listings/{id}: public listing = [tk2PublicPayload] + brokerUid, ownerUid, active
/// - tk2Private/{id}: full listing for the broker / owner (door no., owner, keys, notes)
/// - tk2Invites/{id}: "Send link to owner" invite
/// - tk2Visits/{id} (+ /secret/code, tenant only): paid visits
/// - tk2Trips/{tenantUid}_{listingId}: the tenant's journey answers
class Tk2Cloud {
  Tk2Cloud._();

  static const _apiKey = String.fromEnvironment('TK2_FIREBASE_API_KEY');
  static const _projectId = String.fromEnvironment('TK2_FIREBASE_PROJECT_ID');
  static const _senderId = String.fromEnvironment('TK2_FIREBASE_SENDER_ID');
  static const _bucket = String.fromEnvironment('TK2_FIREBASE_STORAGE_BUCKET');
  static const _authDomain = String.fromEnvironment('TK2_FIREBASE_AUTH_DOMAIN');
  static const _appIdIos = String.fromEnvironment('TK2_FIREBASE_APP_ID_IOS');
  static const _appIdAndroid = String.fromEnvironment('TK2_FIREBASE_APP_ID_ANDROID');
  static const _appIdWeb = String.fromEnvironment('TK2_FIREBASE_APP_ID_WEB');
  static const _iosBundle = String.fromEnvironment('TK2_IOS_BUNDLE_ID', defaultValue: 'com.trustkeyper.tk2');

  /// Where the owner/tenant web app is hosted (links in WhatsApp messages).
  static const webUrl = String.fromEnvironment('TK2_WEB_URL', defaultValue: tk2WebApp);

  static const _region = 'asia-south1';

  /// Local testing only: Firebase emulators on this host (e.g. 127.0.0.1).
  static const _emulator = String.fromEnvironment('TK2_EMULATOR_HOST');

  /// True when built with backend settings. Turned on in [start].
  static bool on = false;

  static String get _appId => kIsWeb
      ? _appIdWeb
      : switch (defaultTargetPlatform) {
          TargetPlatform.iOS => _appIdIos,
          _ => _appIdAndroid,
        };

  static bool get configured => _apiKey.isNotEmpty && _projectId.isNotEmpty && _appId.isNotEmpty;

  /// Call once before runApp. Does nothing in the demo build.
  static Future<void> start() async {
    if (!configured) return;
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: _apiKey,
        appId: _appId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        storageBucket: _bucket,
        authDomain: _authDomain.isEmpty ? null : _authDomain,
        iosBundleId: _iosBundle,
      ),
    );
    if (_emulator.isNotEmpty) {
      await auth.useAuthEmulator(_emulator, 9099);
      db.useFirestoreEmulator(_emulator, 8080);
      FirebaseStorage.instance.useStorageEmulator(_emulator, 9199);
      FirebaseFunctions.instanceFor(region: _region).useFunctionsEmulator(_emulator, 5001);
    }
    on = true;
  }

  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get db => FirebaseFirestore.instance;
  static String? get uid => on ? auth.currentUser?.uid : null;

  // ---------------------------------------------------------------- sign in

  static ConfirmationResult? _webCode;
  static String? _verificationId;
  static String? _email;
  static String? _emailChallenge;

  /// Sends a 6-digit code to a phone (+91 …) or email. Returns the red message
  /// to show, or null when sent (or when Android signed in on its own).
  static Future<String?> sendCode(String destination) async {
    _webCode = null;
    _verificationId = null;
    _email = null;
    _emailChallenge = null;
    try {
      if (destination.contains('@')) {
        final r = await FirebaseFunctions.instanceFor(region: _region).httpsCallable('requestEmailOtp').call<Map<String, dynamic>>({'email': destination});
        _email = destination;
        _emailChallenge = r.data['challengeId'] as String?;
        return _emailChallenge == null ? 'The code could not be sent. Try again.' : null;
      }
      final phone = destination.replaceAll(RegExp(r'[^0-9+]'), '');
      if (kIsWeb) {
        _webCode = await auth.signInWithPhoneNumber(phone);
        return null;
      }
      final sent = Completer<String?>();
      await auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (credential) async {
          await auth.signInWithCredential(credential);
          if (!sent.isCompleted) sent.complete(null);
        },
        verificationFailed: (e) {
          if (!sent.isCompleted) sent.complete(_authMessage(e));
        },
        codeSent: (id, _) {
          _verificationId = id;
          if (!sent.isCompleted) sent.complete(null);
        },
        codeAutoRetrievalTimeout: (_) {},
      );
      return await sent.future.timeout(const Duration(seconds: 45), onTimeout: () => 'The code did not come. Try again.');
    } catch (e) {
      return _authMessage(e);
    }
  }

  /// Checks the 6-digit code. Returns the red message, or null when signed in.
  static Future<String?> verifyCode(String code) async {
    try {
      if (auth.currentUser != null && _webCode == null && _verificationId == null && _emailChallenge == null) return null;
      if (_emailChallenge != null) {
        final r = await FirebaseFunctions.instanceFor(
          region: _region,
        ).httpsCallable('verifyEmailOtp').call<Map<String, dynamic>>({'email': _email, 'code': code, 'challengeId': _emailChallenge});
        await auth.signInWithCustomToken(r.data['customToken'] as String);
      } else if (_webCode != null) {
        await _webCode!.confirm(code);
      } else if (_verificationId != null) {
        await auth.signInWithCredential(PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: code));
      } else {
        return 'Request a new code.';
      }
      return null;
    } catch (e) {
      return _authMessage(e);
    }
  }

  static String _authMessage(Object e) {
    final code = switch (e) {
      FirebaseAuthException(:final code) => code,
      FirebaseFunctionsException(:final code) => code,
      _ => '',
    };
    return switch (code) {
      'invalid-verification-code' || 'invalid-argument' => 'That code is not right. Try again.',
      'invalid-phone-number' => 'Enter a valid phone number',
      'too-many-requests' || 'resource-exhausted' => 'Too many tries. Wait a few minutes.',
      'session-expired' || 'code-expired' || 'deadline-exceeded' => 'The code expired. Send a new one.',
      'network-request-failed' || 'unavailable' => 'No internet. Try again.',
      _ => 'Something went wrong. Try again.',
    };
  }

  static Future<void> signOut() => on ? auth.signOut() : Future.value();

  // ------------------------------------------------------------ documents

  /// Public listing document: only what tenants may see.
  static Map<String, Object?> publicDoc(
    Tk2Listing l, {
    required String brokerUid,
    required String brokerName,
    required String brokerPhone,
    required bool active,
    String? ownerUid,
    String? inviteId,
  }) => {
    ...tk2PublicPayload(l, brokerName, brokerPhone),
    'brokerUid': brokerUid,
    'ownerUid': ?ownerUid,
    'inviteId': ?inviteId,
    'active': active,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Uploads photos that are still files on this device and returns the
  /// listing with web addresses in their place.
  static Future<Tk2Listing> uploadPhotos(Tk2Listing l) async {
    if (l.photos.every((p) => p.startsWith('http'))) return l;
    final out = <String>[];
    for (final p in l.photos) {
      if (p.startsWith('http')) {
        out.add(p);
        continue;
      }
      out.add(await _upload('tk2/listings/${l.id}/${_name()}', p));
    }
    return l.copyWith(photos: out);
  }

  /// A photo or video of a deal (stamp paper, handover, repairs, documents);
  /// only the deal's broker, tenant and owner can open it.
  static Future<String> uploadDealFile(String dealId, String path) => _upload('tk2/deals/$dealId/${_name()}', path);

  /// Gate pass picture/PDF for one visit; returns its web address.
  static Future<String> uploadGatePass(String visitId, String path) => _upload('tk2/visits/$visitId/${_name()}', path);

  /// A document already read into memory (ID proof picked on the web).
  static Future<String> uploadDealBytes(String dealId, Uint8List bytes) => _put('tk2/deals/$dealId/${_name()}', bytes, null);

  static Future<String> _upload(String where, String path) async {
    final file = XFile(path);
    return _put(where, await file.readAsBytes(), file.mimeType);
  }

  static Future<String> _put(String where, Uint8List bytes, String? hint) async {
    final type = _type(bytes, hint);
    final ref = FirebaseStorage.instance.ref('$where.${type.split('/').last}');
    await ref.putData(bytes, SettableMetadata(contentType: type));
    return ref.getDownloadURL();
  }

  /// Content type from the first bytes (JPEG, PNG, PDF); JPEG when unsure.
  static String _type(Uint8List b, String? hint) {
    if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) return 'application/pdf';
    if (hint == 'image/webp' || hint == 'image/heic' || (hint ?? '').startsWith('video/')) return hint!;
    if (b.length > 12 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) return 'video/mp4'; // ....ftyp
    return 'image/jpeg';
  }

  static String _name() => '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

  /// The confirm-visit check runs on the server (only the tenant can read the
  /// code). Returns null when done, else 'wrong' or 'window'.
  static Future<String?> confirmVisit(String visitId, String code) async {
    final r = await FirebaseFunctions.instanceFor(
      region: _region,
    ).httpsCallable('tk2ConfirmVisit').call<Map<String, dynamic>>({'visitId': visitId, 'code': code});
    final result = r.data['result'] as String?;
    return result == 'done' ? null : (result ?? 'wrong');
  }

  /// Millis from a Firestore value (Timestamp or number).
  static int millis(Object? v) => switch (v) {
    Timestamp t => t.millisecondsSinceEpoch,
    num n => n.toInt(),
    _ => 0,
  };
}
