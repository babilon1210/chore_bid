import 'package:chore_bid/pages/child/child_home_page.dart';
import 'package:chore_bid/pages/sign_up/role_selection_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import 'parent/home_page.dart';

class SplashLoaderPage extends StatefulWidget {
  const SplashLoaderPage({super.key});

  @override
  State<SplashLoaderPage> createState() => _SplashLoaderPageState();
}

class _SplashLoaderPageState extends State<SplashLoaderPage> {
  final _userService = UserService();

  @override
  void initState() {
    super.initState();
    _loadUserAndRedirect();
  }

  Future<void> _loadUserAndRedirect() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _goToRegister();
      return;
    }

    final userModel = await _userService.getCurrentUserProfile();

    if (userModel == null) {
      _goToRegister();
      return;
    }

    // Save the userModel for global access (if you're using singleton or provider)
    UserService.currentUser = userModel;

    // Start listening to chores (optional: only for parent)

    _goToHome();
  }

  void _goToRegister() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => RoleSelectionPage()),
    );
  }

  void _goToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => UserService.currentUser!.role == 'parent' ? const HomePage() : const ChildHomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
