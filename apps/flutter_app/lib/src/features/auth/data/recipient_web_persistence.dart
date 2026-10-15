import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/startup/web_firebase_startup.dart';

Future<void> configureRecipientWebPersistence(
  FirebaseAuth auth, {
  bool? transientStorage,
}) async {
  if (transientStorage ?? hasTransientBrowserStorage()) {
    await auth.setPersistence(Persistence.NONE);
    return;
  }
  try {
    await auth.setPersistence(Persistence.SESSION);
  } on FirebaseAuthException catch (error) {
    if (![
      'web-storage-unsupported',
      'operation-not-supported-in-this-environment',
    ].contains(error.code)) {
      rethrow;
    }
    await auth.setPersistence(Persistence.NONE);
  }
}
