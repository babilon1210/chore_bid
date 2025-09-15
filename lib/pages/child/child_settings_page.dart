// lib/pages/child/child_settings_page.dart
import 'package:flutter/material.dart';
import 'package:chore_bid/services/auth_service.dart';

class ChildSettingsPage extends StatefulWidget {
  const ChildSettingsPage({super.key});

  @override
  State<ChildSettingsPage> createState() => _ChildSettingsPageState();
}

class _ChildSettingsPageState extends State<ChildSettingsPage> {
  final _authService = AuthService();
  bool _signingOut = false;

  Future<void> _logout() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);

    try {
      await _authService.logout(); // <- all auth + FCM cleanup is inside the service
      if (!mounted) return;
      // Go back to the AuthGatePage (your "/" route)
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to log out: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 244, 190, 71),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: Center(
        child: _signingOut
            ? const CircularProgressIndicator()
            : ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Log out'),
                onPressed: _logout,
              ),
      ),
    );
  }
}
