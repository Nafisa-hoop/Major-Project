import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:splitnow/screens/notification_service.dart';
import 'package:splitnow/screens/theme_provider.dart';

import 'screens/login_page.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/signup_page.dart';
import 'screens/forgot_password_page.dart';
import 'screens/reset_password_page.dart';

Future<void> saveFcmToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
  }
}

Future<void> setupPushNotifications() async {
  final messaging = FirebaseMessaging.instance;

  // Request permission (important on iOS)
  await messaging.requestPermission();

  // Get initial token
  final token = await messaging.getToken();
  final uid = FirebaseAuth.instance.currentUser?.uid;

  if (uid != null && token != null) {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      "fcmToken": token,
    }, SetOptions(merge: true));
  }

  // Listen for token refresh
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        "fcmToken": newToken,
      }, SetOptions(merge: true));
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.init();

  // 👇 Setup FCM token after Firebase is initialized
  if (FirebaseAuth.instance.currentUser != null) {
    await setupPushNotifications();
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.amber,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.amber,
      ),
      themeMode: themeProvider.themeMode,
      initialRoute:
      FirebaseAuth.instance.currentUser != null ? '/home' : '/login',
      onGenerateRoute: (settings) {
        if (settings.name == '/home') {
          final args = settings.arguments as Map<String, dynamic>?;
          final username = args?['username'] ?? 'User';
          return MaterialPageRoute(
            builder: (_) => HomeWidget(username: username),
          );
        }
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const OnboardingScreen());
          case '/login':
            return MaterialPageRoute(builder: (_) => const LoginPage());
          case '/signup':
            return MaterialPageRoute(builder: (_) => const SignupPage());
          case '/forgot-password':
            return MaterialPageRoute(
                builder: (_) => const ForgotPasswordPage());
          case '/reset-password':
            return MaterialPageRoute(
                builder: (_) => const ResetPasswordPage());
          default:
            return MaterialPageRoute(builder: (_) => const LoginPage());
        }
      },
    );
  }
}
