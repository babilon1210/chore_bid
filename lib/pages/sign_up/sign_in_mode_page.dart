import 'package:chore_bid/pages/sign_up/child_qr_signin_page.dart';
import 'package:chore_bid/pages/sign_up/sign_in_page.dart';
import 'package:flutter/material.dart';

class SignInModePage extends StatelessWidget {
  const SignInModePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Who’s signing in?")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('I’m a Parent'),
              subtitle: const Text('Use email & password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SignInPage()),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.child_care),
              title: const Text('I’m a Child'),
              subtitle: const Text('Scan sign-in QR from a parent'),
              trailing: const Icon(Icons.qr_code_scanner),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChildQrSignInPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
