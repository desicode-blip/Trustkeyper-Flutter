import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirebaseSessionPreferences {
  FirebaseSessionPreferences({
    required FirebaseAuth auth,
    bool isWeb = kIsWeb,
    Future<bool?> Function()? readRemembered,
    Future<void> Function(bool)? writeRemembered,
  }) : _auth = auth,
       _isWeb = isWeb,
       _readRemembered = readRemembered ?? _readPreference,
       _writeRemembered = writeRemembered ?? _writePreference;

  static const _key = 'trustkeyper.keep_logged_in';

  final FirebaseAuth _auth;
  final bool _isWeb;
  final Future<bool?> Function() _readRemembered;
  final Future<void> Function(bool) _writeRemembered;

  static Future<bool?> _readPreference() async =>
      (await SharedPreferences.getInstance()).getBool(_key);

  static Future<void> _writePreference(bool remembered) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setBool(_key, remembered)) {
      throw StateError('Login preference could not be saved.');
    }
  }

  Future<void> configure({required bool keepLoggedIn}) async {
    if (_isWeb) {
      await _auth.setPersistence(
        keepLoggedIn ? Persistence.LOCAL : Persistence.SESSION,
      );
    } else {
      await _writeRemembered(keepLoggedIn);
    }
  }

  Future<void> restoreAtStartup() async {
    if (!_isWeb && await _readRemembered() == false) {
      await _auth.signOut();
    }
  }
}
