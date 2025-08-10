import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'pages/auth_gate_page.dart';
import 'pages/splash_loader_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await setupFCM();
  runApp(const ChoreBidApp());
}

Future<void> setupFCM() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request permission (iOS only)
  await messaging.requestPermission();

  // Get token
  String? token = await messaging.getToken();
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
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthGatePage(),
        '/splash': (context) => const SplashLoaderPage(),
      },
    );
  }
}
