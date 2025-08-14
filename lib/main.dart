import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// ✅ use the generated import path
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'pages/auth_gate_page.dart';
import 'pages/splash_loader_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await setupFCM();
  runApp(const ChoreBidApp());
}

Future<void> setupFCM() async {
  final messaging = FirebaseMessaging.instance;

  // Request permission (iOS only)
  await messaging.requestPermission();

  // Get token
  final token = await messaging.getToken();
  // ignore: avoid_print
  print('FCM Token: $token');

  if (token != null) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // Save token to Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': token,
      });
    }
  }

  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    // ignore: avoid_print
    print('Foreground message: ${message.notification?.title}');
  });
}

class ChoreBidApp extends StatelessWidget {
  const ChoreBidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChoreBid',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo),

      // ✅ Localization wiring
      // These two pull from the generated AppLocalizations class.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,

      // Optional: dynamic app title from ARB
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,

      initialRoute: '/',
      routes: {
        '/': (context) => const AuthGatePage(),
        '/splash': (context) => const SplashLoaderPage(),
      },
    );
  }
}
