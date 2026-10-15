import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'src/app.dart';
import 'src/core/startup/web_firebase_startup.dart';
import 'src/features/auth/data/firebase_session_preferences.dart';

@pragma('vm:entry-point')
Future<void> receiveBackgroundUpdate(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Roboto',
    ], await rootBundle.loadString('assets/fonts/Roboto-OFL.txt'));
  });
  try {
    if (kIsWeb) await prepareWebFirebase();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 20));
    await FirebaseSessionPreferences(
      auth: FirebaseAuth.instance,
    ).restoreAtStartup().timeout(const Duration(seconds: 10));
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(receiveBackgroundUpdate);
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestProvider(),
      );
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
  } catch (error, stackTrace) {
    debugPrint('TrustKeyper startup failed: $error\n$stackTrace');
    runApp(const _BootstrapFailureApp());
    return;
  }
  runApp(const ProviderScope(child: TrustKeyperApp()));
}

class _BootstrapFailureApp extends StatelessWidget {
  const _BootstrapFailureApp();

  @override
  Widget build(BuildContext context) {
    final failurePage = Scaffold(
      backgroundColor: const Color(0xFFF6F9FD),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 42,
                      color: Color(0xFF3160FF),
                    ),
                    SizedBox(height: 18),
                    Text(
                      'TrustKeyper could not start',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF172231),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Check your connection, then refresh this page. If the problem continues, contact the TrustKeyper team.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF5E7087), height: 1.45),
                    ),
                    if (kIsWeb) ...[
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        onPressed: reloadStartupPage,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: failurePage,
      onGenerateInitialRoutes: (initialRoute) => [
        MaterialPageRoute<void>(
          settings: RouteSettings(name: initialRoute),
          builder: (context) => failurePage,
        ),
      ],
    );
  }
}
