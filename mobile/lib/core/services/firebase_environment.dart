import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class FirebaseEnvironment {
  static const emulator = bool.fromEnvironment('USE_EMULATORS', defaultValue: true);
  static const host = String.fromEnvironment('EMULATOR_HOST', defaultValue: '127.0.0.1');
  static const options = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'demo-key'),
    appId: String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:123456789:web:demo'),
    messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '123456789'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'demo-crompton-pms'),
    storageBucket: emulator ? null : String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
  );
  static Future<void> initialize() async {
    if (kReleaseMode && emulator) throw StateError('Emulators are forbidden in release builds');
    await Firebase.initializeApp(options: options);
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
    if (emulator) {
      await FirebaseAuth.instance.useAuthEmulator(host,9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host,8086);
    } else if (!kIsWeb) {
      await FirebaseAppCheck.instance.activate(providerAndroid: kReleaseMode ? const AndroidPlayIntegrityProvider() : const AndroidDebugProvider());
    }
    await Hive.initFlutter();
  }
}
