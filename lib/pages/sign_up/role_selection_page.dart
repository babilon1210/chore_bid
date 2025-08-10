import 'package:flutter/material.dart';
import 'register_create_family_page.dart';
import 'register_join_family_page.dart';

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Get Started')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RegisterCreateFamilyPage()));
              },
              child: const Text('Create a Family (First Parent)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RegisterJoinFamilyPage(role: 'parent')));
              },
              child: const Text('Join a Family as Second Parent'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RegisterJoinFamilyPage(role: 'child')));
              },
              child: const Text('Join a Family as Child'),
            ),
          ],
        ),
      ),
    );
  }
}
