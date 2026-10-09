// Firebase client configuration, read from Envied (`.env`) at build time.
//
// These are PUBLIC Firebase client identifiers/config (A-class in the Phase 0
// audit) — not secrets. Keeping the literals out of tracked source puts the
// value in lib/config/env.dart / .env instead. If you re-run `flutterfire
// configure`, re-apply the AppEnv references below before committing.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'env.dart';

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static final FirebaseOptions android = FirebaseOptions(
    apiKey: AppEnv.firebaseAndroidApiKey,
    appId: AppEnv.firebaseAndroidAppId,
    messagingSenderId: AppEnv.firebaseMessagingSenderId,
    projectId: AppEnv.firebaseProjectId,
    storageBucket: AppEnv.firebaseStorageBucket,
  );

  static final FirebaseOptions ios = FirebaseOptions(
    apiKey: AppEnv.firebaseIosApiKey,
    appId: AppEnv.firebaseIosAppId,
    messagingSenderId: AppEnv.firebaseMessagingSenderId,
    projectId: AppEnv.firebaseProjectId,
    storageBucket: AppEnv.firebaseStorageBucket,
    iosBundleId: 'com.example.flashChatApp',
  );
}