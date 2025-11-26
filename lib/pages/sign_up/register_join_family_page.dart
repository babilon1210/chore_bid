// lib/pages/register_join_family_page.dart
import 'dart:convert';
import 'package:chore_bid/pages/sign_up/email_verification_page.dart';
import 'package:chore_bid/pages/splash_loader_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chore_bid/pages/qr_scanner_page.dart';
import 'package:chore_bid/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart' as gsi;
import 'package:flutter/foundation.dart' show kIsWeb;

class RegisterJoinFamilyPage extends StatefulWidget {
  final String role; // 'child' or 'parent'

  const RegisterJoinFamilyPage({super.key, required this.role});

  @override
  State<RegisterJoinFamilyPage> createState() => _RegisterJoinFamilyPageState();
}

class _RegisterJoinFamilyPageState extends State<RegisterJoinFamilyPage> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? familyId;
  String? _error;
  String? _qrScanError;
  bool _loading = false;

  bool get _isLinked => (familyId != null && familyId!.isNotEmpty);

  // -------------------- CHILD FLOW (unchanged) --------------------
  Future<void> _scanInviteAndSignIn() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerPage()),
    );

    if (result == null) return;

    setState(() {
      _error = null;
      _qrScanError = null;
    });

    try {
      String? code;
      try {
        final decoded = jsonDecode(result);
        if (decoded is Map && decoded['code'] is String) {
          code = decoded['code'] as String;
        }
      } catch (_) {
        if (result is String && result.trim().isNotEmpty) {
          code = result.trim();
        }
      }

      if (code == null || code.isEmpty) {
        throw Exception('Invalid QR. Try again.');
      }

      setState(() => _loading = true);

      final callable = FirebaseFunctions.instance.httpsCallable('redeemCode');
      final res = await callable.call({'code': code});
      final data =
          (res.data is Map)
              ? Map<String, dynamic>.from(res.data)
              : <String, dynamic>{};
      final token = data['customToken'] as String?;

      if (token == null || token.isEmpty) {
        throw Exception('Could not sign in with this code.');
      }

      await FirebaseAuth.instance.signInWithCustomToken(token);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Welcome!')));
      Navigator.pushReplacementNamed(context, '/splash');
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------- SECOND PARENT: QR scan helpers --------------------
  Future<void> _scanFamilyQrToGetFamilyId() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerPage()),
    );

    if (result != null) {
      try {
        String? id;
        final match = RegExp(
          r'familyId[:=]\s*([a-zA-Z0-9_-]+)',
        ).firstMatch(result);
        if (match != null) {
          id = match.group(1);
        } else {
          final decoded = jsonDecode(result);
          if (decoded is Map && decoded['familyId'] is String) {
            id = decoded['familyId'] as String;
          }
        }

        if (id == null || id.isEmpty) {
          throw Exception("familyId not found in QR");
        }

        setState(() {
          familyId = id;
          _qrScanError = null;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Family QR linked'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to scan QR'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearScan() {
    setState(() {
      familyId = null;
      _qrScanError = null;
    });
  }

  // -------------------- SECOND PARENT: Email/Password with EMAIL VERIFICATION --------------------
  Future<void> _registerSecondParent() async {
    if (!_formKey.currentState!.validate()) return;

    if (familyId == null) {
      setState(() => _qrScanError = "Please scan the family QR code first.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Create the Firebase user (signed in after this)
      final user = await _authService.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: 'parent',
      );

      if (user != null) {
        // Send verification email
        await _authService.sendVerificationEmail();

        // Navigate to the email verification page and wait for completion.
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => EmailVerificationPage(
                  email: _emailController.text.trim(),
                  authService: _authService,
                  onVerified: () async {
                    // After verification, attach this parent to the scanned family.
                    final callable = FirebaseFunctions.instance.httpsCallable(
                      'createUserWithFamily',
                    );
                    await callable.call({
                      'role': 'parent',
                      'name': _nameController.text.trim(),
                      'familyId': familyId, // join the scanned family
                    });

                    if (!mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SplashLoaderPage(),
                      ),
                      (route) => false,
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

  // -------------------- SECOND PARENT: Google path (unchanged logic) --------------------
  Future<void> _continueWithGoogleSecondParent() async {
    // Hard requirement: must scan QR first
    if (familyId == null) {
      setState(() => _qrScanError = "Please scan the family QR code first.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please scan the family QR first')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      UserCredential credResult;

      if (kIsWeb) {
        // WEB: Firebase popup (no redirect page, no sessionStorage problem)
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
        // MOBILE (Android / iOS): google_sign_in v7.x native flow
        final gsi.GoogleSignIn signIn = gsi.GoogleSignIn.instance;

        // Required in v7.x
        await signIn.initialize();

        if (!signIn.supportsAuthenticate()) {
          throw Exception(
            'GoogleSignIn.authenticate() is not supported on this platform.',
          );
        }

        // Interactive Google sign-in
        final gsi.GoogleSignInAccount user = await signIn.authenticate();

        // Get tokens (only idToken is available/needed)
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

      // 2) Check if profile already exists
      final uid = firebaseUser.uid;
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (userDoc.exists &&
          (userDoc.data()!['familyId'] as String?)?.isNotEmpty == true) {
        final proceed = await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
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
          await _authService.logout();
          // Also clear Google account on mobile (safe no-op on web)
          await gsi.GoogleSignIn.instance.signOut();
          if (mounted) setState(() => _loading = false);
        }
        return;
      }

      // 3) No profile yet -> join the scanned family via callable
      final callable = FirebaseFunctions.instance.httpsCallable(
        'createUserWithFamily',
      );
      await callable.call({
        'role': 'parent',
        'name':
            (firebaseUser.displayName ??
                (_nameController.text.trim().isNotEmpty
                    ? _nameController.text.trim()
                    : 'Parent')),
        'familyId': familyId, // join the scanned family
      });

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/splash');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------- UI --------------------

  Widget _stepHeader(String title) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  Widget _secondParentQrSection() {
    // Step 1 card
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader('Step 1: Scan Family QR'),
          const SizedBox(height: 8),
          const Text(
            'You must link to the existing family by scanning its QR. '
            'After linking, you can continue with sign up.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (_isLinked)
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF81C784)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Color(0xFF2E7D32),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Family linked: $familyId',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _clearScan, child: const Text('Change')),
              ],
            )
          else
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _scanFamilyQrToGetFamilyId,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Family QR'),
              ),
            ),
          if (_qrScanError != null) ...[
            const SizedBox(height: 8),
            Text(_qrScanError!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isChild = widget.role == 'child';

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isChild ? 'Join as Child' : 'Join as Parent'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child:
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (isChild ? _buildChildBody() : _buildSecondParentBody()),
        ),
      ),
    );
  }

  // --------- CHILD signup (unchanged) ---------
  Widget _buildChildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Text(
          "Ask your parent to open your Sign-up QR and scan it here.",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _scanInviteAndSignIn,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan My Sign-up QR'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }

  // --------- SECOND PARENT layout (Step 1 + Step 2) ---------
  Widget _buildSecondParentBody() {
    final disabledHint =
        !_isLinked
            ? const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text(
                'Scan the Family QR above to enable sign up.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
            : const SizedBox.shrink();

    return Form(
      key: _formKey,
      child: ListView(
        children: [
          // STEP 1 (Required)
          _secondParentQrSection(),
          const SizedBox(height: 16),

          // STEP 2 (Account creation)
          _stepHeader('Step 2: Create your parent account'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            validator:
                (val) => val == null || val.isEmpty ? 'Enter your name' : null,
          ),
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
            validator: (val) {
              if (val == null || val.isEmpty || !val.contains('@')) {
                return 'Valid email required';
              }
              return null;
            },
          ),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            validator:
                (val) => val == null || val.length < 6 ? 'Too short' : null,
          ),
          TextFormField(
            controller: _confirmPasswordController,
            decoration: const InputDecoration(labelText: 'Confirm password'),
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
          const SizedBox(height: 20),

          // Email/Password submit (requires QR link first)
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLinked ? _registerSecondParent : null,
              child: const Text('Sign Up'),
            ),
          ),
          if (!_isLinked) disabledHint,

          // Divider
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

          // Continue with Google (also disabled until QR linked)
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isLinked ? _continueWithGoogleSecondParent : null,
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
          if (!_isLinked) disabledHint,

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }
}
