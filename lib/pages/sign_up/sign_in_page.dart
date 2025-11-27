import 'package:chore_bid/pages/auth_gate_page.dart';
import 'package:chore_bid/pages/splash_loader_page.dart';
import 'package:chore_bid/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart' as gsi;
import 'package:flutter/foundation.dart' show kIsWeb;

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  String? _error;

  // Google Sign-In instance
  // final gsi.GoogleSignIn _googleSignIn = gsi.GoogleSignIn(
  //   scopes: <String>['email'],
  // );

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashLoaderPage()),
        (route) => false,
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      UserCredential credResult;

      if (kIsWeb) {
        // WEB: use popup-based Firebase Auth (no redirect / sessionStorage issues)
        final googleProvider =
            GoogleAuthProvider()
              ..addScope('email')
              ..addScope('profile')
              ..setCustomParameters(<String, String>{
                'prompt': 'select_account',
              });

        credResult = await FirebaseAuth.instance.signInWithPopup(
          googleProvider,
        );
      } else {
        // MOBILE (Android / iOS): use google_sign_in v7.x
        final gsi.GoogleSignIn signIn = gsi.GoogleSignIn.instance;

        // Required for v7.x
        await signIn.initialize();

        if (!signIn.supportsAuthenticate()) {
          throw Exception(
            'GoogleSignIn.authenticate() is not supported on this platform.',
          );
        }

        // Interactive sign-in
        final gsi.GoogleSignInAccount user = await signIn.authenticate();

        // Get tokens (idToken only in v7.x)
        final gsi.GoogleSignInAuthentication googleAuth =
            await user.authentication;

        final String? idToken = googleAuth.idToken;
        if (idToken == null) {
          throw Exception('Google sign-in did not return an ID token.');
        }

        final OAuthCredential credential = GoogleAuthProvider.credential(
          idToken: idToken,
        );

        credResult = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
      }

      final User? firebaseUser = credResult.user;
      if (firebaseUser == null) {
        throw Exception('Firebase sign-in failed');
      }

      // 4) Check if user profile exists in Firestore
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(firebaseUser.uid)
              .get();

      print(firebaseUser.uid);
      if (doc.exists &&
          (doc.data()!['familyId'] as String?)?.isNotEmpty == true) {
        // Known user -> continue into app
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SplashLoaderPage()),
          (route) => false,
        );
        return;
      }

      // 5) No user profile -> prompt to sign up first, then route to AuthGate
      final ok = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('No user found'),
              content: const Text(
                'No user found for this account. Please sign up first.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('OK'),
                ),
              ],
            ),
      );

      // Sign out so they can start a clean sign-up flow
      await _authService.logout();
      await gsi.GoogleSignIn.instance.signOut();

      if (ok == true && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGatePage()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: const Text('Sign In')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child:
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator:
                              (val) =>
                                  val == null || !val.contains('@')
                                      ? 'Invalid email'
                                      : null,
                        ),
                        TextFormField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          obscureText: true,
                          validator:
                              (val) =>
                                  val == null || val.length < 6
                                      ? 'Too short'
                                      : null,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _signIn,
                          child: const Text('Sign In'),
                        ),

                        // OR divider
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

                        // Google sign-in button
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _signInWithGoogle,
                            icon: const Icon(Icons.g_mobiledata, size: 28),
                            label: const Text(
                              'Sign in with Google',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.black12),
                            ),
                          ),
                        ),

                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
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
