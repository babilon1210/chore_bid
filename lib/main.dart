import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'l10n/generated/app_localizations.dart';
import 'pages/auth_gate_page.dart';
import 'pages/splash_loader_page.dart';

@pragma('vm:entry-point')
Future<void> _bgMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // handle background data if needed
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Register background handler early (fast, non-blocking)
  FirebaseMessaging.onBackgroundMessage(_bgMessageHandler);

  runApp(const ChoreBidApp());

  // Don’t block UI on FCM setup
  // (runs after first frame; permission sheet appears over your UI)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_setupFCM());
  });
}

Future<void> _setupFCM() async {
  try {
    final messaging = FirebaseMessaging.instance;

    if (Platform.isIOS) {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );
    }

    Future<void> saveToken(String? token) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'fcmToken': token}, SetOptions(merge: true));
      }
    }

    await saveToken(await messaging.getToken());
    FirebaseMessaging.instance.onTokenRefresh.listen(saveToken);

    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) saveToken(await messaging.getToken());
    });

    FirebaseMessaging.onMessage.listen((m) {
      // print('Foreground message: ${m.notification?.title}');
    });
  } catch (e, st) {
    // print('setupFCM error: $e\n$st');
  }
}

class ChoreBidApp extends StatelessWidget {
  const ChoreBidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChoreBid',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx)!.appTitle,
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthGatePage(),
        '/splash': (context) => const SplashLoaderPage(),
      },
    );
  }
}
