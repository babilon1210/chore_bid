import 'package:chore_bid/pages/sign_up/role_selection_page.dart';
import 'package:chore_bid/pages/sign_up/sign_in_mode_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sign_up/sign_in_page.dart';
import 'splash_loader_page.dart';

class AuthGatePage extends StatefulWidget {
  const AuthGatePage({super.key});

  @override
  State<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends State<AuthGatePage> {
  bool _navigated = false;

  static const String _bgAsset = 'assets/family.png';
  static const String _logoAsset = 'assets/sticker.png';

  // Move everything under the title up a bit (negative = up).
  static const double _liftUpY = -45;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !_navigated) {
      _navigated = true;
      Future.microtask(() {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SplashLoaderPage()),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 242, 197, 100),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text('Welcome to ChoreBid'),
      ),
      body: Stack(
        children: [
          // Page content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Transform.translate(
                    offset: const Offset(0, _liftUpY),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        FractionallySizedBox(
                          widthFactor: 1,
                          child: Image.asset(
                            _bgAsset,
                            fit: BoxFit.contain,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                        const SizedBox(height: 24),

                        const Text(
                          'Manage chores, earn rewards, and grow together as a family.',
                          style: TextStyle(fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
                            );
                          },
                          child: const Text('Sign up'),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SignInModePage()),
                            );
                          },
                          child: const Text('Already have an account? Sign In'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // App icon pinned to bottom-right
          Positioned(
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              left: false,
              child: Opacity(
                opacity: 0.95,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    _logoAsset,
                    width: 64,
                    height: 64,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
