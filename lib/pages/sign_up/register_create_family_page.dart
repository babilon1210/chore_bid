import 'dart:async';
import 'package:chore_bid/pages/sign_up/email_verification_page.dart';
import 'package:chore_bid/pages/splash_loader_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chore_bid/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart' as gsi;
import 'dart:ui' as ui;

class RegisterCreateFamilyPage extends StatefulWidget {
  const RegisterCreateFamilyPage({super.key});

  @override
  State<RegisterCreateFamilyPage> createState() =>
      _RegisterCreateFamilyPageState();
}

class _RegisterCreateFamilyPageState extends State<RegisterCreateFamilyPage> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController(); // <-- added

  bool _loading = false;
  String? _error;

  /// Resolve a currency symbol based on the current device locale.
  /// Requirement: IL -> ₪ ; defaults sensibly otherwise.
  String _resolveCurrencySymbol(BuildContext context) {
    Locale locale =
        Localizations.maybeLocaleOf(context) ??
        ui.PlatformDispatcher.instance.locale;

    if ((locale.countryCode ?? '').isEmpty) {
      final withRegion = ui.PlatformDispatcher.instance.locales.firstWhere(
        (l) => (l.countryCode ?? '').isNotEmpty,
        orElse: () => locale,
      );
      locale = withRegion;
    }

    final cc = (locale.countryCode ?? '').toUpperCase();
    switch (cc) {
      case 'IL':
        return '₪';
      case 'US':
        return r'$';
      case 'GB':
        return '£';
      case 'DE':
      case 'FR':
      case 'ES':
      case 'IT':
      case 'IE':
      case 'NL':
      case 'PT':
      case 'BE':
      case 'FI':
      case 'AT':
      case 'GR':
      case 'EE':
      case 'LV':
      case 'LT':
      case 'LU':
      case 'MT':
      case 'SI':
      case 'SK':
      case 'CY':
        return '€';
      case 'JP':
      case 'CN':
        return '¥';
      case 'IN':
        return '₹';
      default:
        return r'$';
    }
  }

  Future<void> _postAuthCreateFamily({
    required String displayNameFallback,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }

    final currency = _resolveCurrencySymbol(context);

    final callable = FirebaseFunctions.instance.httpsCallable(
      'createUserWithFamily',
    );
    final result = await callable.call({
      'role': 'parent',
      'name':
          (user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : displayNameFallback.trim()),
      'currency': currency,
      // no familyId -> function creates (idempotently) a new family if needed
    });

    final data = result.data;
    final String? familyId = (data is Map ? data['familyId'] as String? : null);
    if (familyId == null || familyId.isEmpty) {
      throw Exception('createUserWithFamily did not return a familyId');
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashLoaderPage()),
      (route) => false,
    );
  }

  Future<void> _registerEmailPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = await _authService.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: 'parent',
      );

      if (user != null) {
        // Send verification email
        await _authService.sendVerificationEmail();

        // Go to a waiting screen that auto-detects verification
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EmailVerificationPage(
              email: _emailController.text.trim(),
              authService: _authService,
              onVerified: () async {
                await _postAuthCreateFamily(
                  displayNameFallback: _nameController.text.trim(),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1) Native Google sign-in (Android/iOS)
      final googleUser = await gsi.GoogleSignIn.instance.authenticate();
      if (googleUser == null) {
        // user cancelled
        if (mounted) setState(() => _loading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;

      // 2) Exchange tokens for Firebase credential
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.idToken,
      );

      final credResult = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final firebaseUser = credResult.user;
      if (firebaseUser == null) {
        throw Exception('Firebase sign-in failed');
      }

      // 3) BEFORE creating a family: check if profile already exists
      final uid = firebaseUser.uid;
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (userDoc.exists) {
        // Show "already exists" dialog
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Account exists'),
            content: const Text('This user already exists. Sign in?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('No'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        );

        if (proceed == true) {
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const SplashLoaderPage()),
            (route) => false,
          );
        } else {
          // User chose "No" -> sign out both Firebase & Google
          await _authService.logout();
          await gsi.GoogleSignIn.instance.signOut();
          if (mounted) setState(() => _loading = false);
        }
        return; // Important: do NOT create a family here
      }

      // 4) No profile yet -> create family + profile
      await _postAuthCreateFamily(
        displayNameFallback:
            _nameController.text.trim().isNotEmpty
                ? _nameController.text.trim()
                : (googleUser.displayName ?? 'Parent'),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose(); // <-- added
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: const Text('Parent info')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator: (val) =>
                            val == null || val.isEmpty ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        validator: (val) =>
                            val == null || val.isEmpty || !val.contains('@')
                                ? 'Invalid email'
                                : null,
                      ),
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        obscureText: true,
                        validator: (val) =>
                            val == null || val.length < 6 ? 'Too short' : null,
                      ),
                      TextFormField(
                        controller: _confirmPasswordController,
                        decoration: const InputDecoration(
                          labelText: 'Confirm Password',
                        ),
                        obscureText: true,
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return 'Confirm your password';
                          }
                          if (val != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _registerEmailPassword,
                        child: const Text('Create Family'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: const [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text('or'),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _continueWithGoogle,
                          icon: const Icon(Icons.g_mobiledata, size: 28),
                          label: const Text(
                            'Continue with Google',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.black12),
                          ),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
