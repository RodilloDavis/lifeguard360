// lib/firebase_options.dart
// Generated from google-services.json + Firebase web config.
// DO NOT commit this file to public source control.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for Linux. '
          'You can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ── Web ──────────────────────────────────────────────────────────────────
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCk9_Lc6Osz3Xs1WhYKzF3CfUpTImn1704',
    authDomain: 'lifeguard-cefd9.firebaseapp.com',
    databaseURL:
        'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app',
    projectId: 'lifeguard-cefd9',
    storageBucket: 'lifeguard-cefd9.firebasestorage.app',
    messagingSenderId: '579792179500',
    appId: '1:579792179500:web:3bd106cbfd68d985705c89',
    measurementId: 'G-BK036BXCJ0',
  );

  // ── Android ──────────────────────────────────────────────────────────────
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCoBr-q1LF2dJhOAEhfP5GhpZKnhza-TgA',
    authDomain: 'lifeguard-cefd9.firebaseapp.com',
    databaseURL:
        'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app',
    projectId: 'lifeguard-cefd9',
    storageBucket: 'lifeguard-cefd9.firebasestorage.app',
    messagingSenderId: '579792179500',
    appId: '1:579792179500:android:79a13340deae1512705c89',
  );

  // ── iOS ──────────────────────────────────────────────────────────────────
  // You have no iOS app registered in Firebase yet.
  // If you add one, replace these placeholder values with real ones from
  // your GoogleService-Info.plist.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCk9_Lc6Osz3Xs1WhYKzF3CfUpTImn1704',
    authDomain: 'lifeguard-cefd9.firebaseapp.com',
    databaseURL:
        'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app',
    projectId: 'lifeguard-cefd9',
    storageBucket: 'lifeguard-cefd9.firebasestorage.app',
    messagingSenderId: '579792179500',
    appId: '1:579792179500:web:3bd106cbfd68d985705c89',
    iosClientId: '',
    iosBundleId: 'com.example.lifeguard360',
  );

  // ── macOS ────────────────────────────────────────────────────────────────
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCk9_Lc6Osz3Xs1WhYKzF3CfUpTImn1704',
    authDomain: 'lifeguard-cefd9.firebaseapp.com',
    databaseURL:
        'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app',
    projectId: 'lifeguard-cefd9',
    storageBucket: 'lifeguard-cefd9.firebasestorage.app',
    messagingSenderId: '579792179500',
    appId: '1:579792179500:web:3bd106cbfd68d985705c89',
    iosClientId: '',
    iosBundleId: 'com.example.lifeguard360',
  );

  // ── Windows ──────────────────────────────────────────────────────────────
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCk9_Lc6Osz3Xs1WhYKzF3CfUpTImn1704',
    authDomain: 'lifeguard-cefd9.firebaseapp.com',
    databaseURL:
        'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app',
    projectId: 'lifeguard-cefd9',
    storageBucket: 'lifeguard-cefd9.firebasestorage.app',
    messagingSenderId: '579792179500',
    appId: '1:579792179500:web:3bd106cbfd68d985705c89',
    measurementId: 'G-BK036BXCJ0',
  );
}
