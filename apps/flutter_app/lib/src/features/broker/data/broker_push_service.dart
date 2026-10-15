import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'broker_updates_repository.dart';
import 'push_token_readiness.dart';

class BrokerPushService {
  BrokerPushService({required this.onOpenUpdates, required this.onForeground});
  final VoidCallback onOpenUpdates;
  final VoidCallback onForeground;
  final repository = FirebaseBrokerUpdatesRepository();
  StreamSubscription<RemoteMessage>? opened;
  StreamSubscription<RemoteMessage>? foreground;
  StreamSubscription<String>? refreshed;
  StreamSubscription<User?>? users;
  final devices = <String>{};
  bool stopped = false;
  bool removingDevices = false;
  String? uid;
  Future<void> start() async {
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    users = FirebaseAuth.instance.userChanges().listen((user) {
      if (user?.uid != uid) unawaited(stop());
    });
    opened = FirebaseMessaging.onMessageOpenedApp.listen(_open);
    foreground = FirebaseMessaging.onMessage.listen((message) {
      if (_matches(message)) onForeground();
    });
    refreshed = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => unawaited(_register(token)),
    );
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null) _open(message);
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await readyMessagingToken(
          requiresApns: defaultTargetPlatform == TargetPlatform.iOS,
          readApnsToken: FirebaseMessaging.instance.getAPNSToken,
          readMessagingToken: FirebaseMessaging.instance.getToken,
          isActive: () =>
              !stopped && FirebaseAuth.instance.currentUser?.uid == uid,
        );
        if (token != null) await _register(token);
      }
    } catch (_) {}
  }

  void _open(RemoteMessage message) {
    if (_matches(message)) onOpenUpdates();
  }

  bool _matches(RemoteMessage message) =>
      !stopped &&
      FirebaseAuth.instance.currentUser?.uid == uid &&
      message.data['brokerUid'] == uid &&
      message.data['kind'] == 'broker_update';
  Future<void> _register(String token) async {
    if (stopped || FirebaseAuth.instance.currentUser?.uid != uid) return;
    try {
      final id = await repository.registerDevice(
        token,
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      );
      devices.add(id);
      if (removingDevices && FirebaseAuth.instance.currentUser?.uid == uid) {
        await repository.removeDevice(uid!, id);
      }
    } catch (_) {}
  }

  Future<void> stop({bool removeDevices = false}) async {
    if (stopped) return;
    stopped = true;
    removingDevices = removeDevices;
    await opened?.cancel();
    await foreground?.cancel();
    await refreshed?.cancel();
    await users?.cancel();
    if (removeDevices &&
        uid != null &&
        FirebaseAuth.instance.currentUser?.uid == uid) {
      for (final id in devices) {
        try {
          await repository.removeDevice(uid!, id);
        } catch (_) {}
      }
    }
  }
}
