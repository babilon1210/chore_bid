// lib/pages/sign_up/role_selection_page.dart
import 'package:flutter/material.dart';
import 'register_create_family_page.dart';
import 'register_join_family_page.dart';

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  // Match AuthGatePage visuals
  static const String _bgAsset = 'assets/highfive.png';
  static const String _logoAsset = 'assets/sticker.png';
  static const double _liftUpY = -45;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 242, 197, 100),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text('Choose Your Role'),
      ),
      body: Stack(
        children: [
          // Main content
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
                        // Hero image (same as AuthGatePage)
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
                          'Choose the right option for you',
                          style: TextStyle(fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        // Buttons (full-width within the 500px container)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegisterCreateFamilyPage(),
                                ),
                              );
                            },
                            child: const Text('Create a Family (First Parent)'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const RegisterJoinFamilyPage(role: 'parent'),
                                ),
                              );
                            },
                            child: const Text('Join a Family as Second Parent'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const RegisterJoinFamilyPage(role: 'child'),
                                ),
                              );
                            },
                            child: const Text('Join a Family as Child'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // App icon pinned to bottom-right (same as AuthGatePage)
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
