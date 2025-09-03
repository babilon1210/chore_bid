import 'package:chore_bid/pages/sign_up/add_children_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:chore_bid/services/auth_service.dart';

class RegisterCreateFamilyPage extends StatefulWidget {
  const RegisterCreateFamilyPage({super.key});

  @override
  State<RegisterCreateFamilyPage> createState() => _RegisterCreateFamilyPageState();
}

class _RegisterCreateFamilyPageState extends State<RegisterCreateFamilyPage> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  String? _error;

  Future<void> _register() async {
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

    if (user != null && mounted) {
      final callable = FirebaseFunctions.instance.httpsCallable('createUserWithFamily');
      final result = await callable.call({
        'role': 'parent',
        'name': _nameController.text.trim(),
      });

      // Extract familyId from the callable response
      final data = result.data;
      final String? familyId =
          (data is Map ? data['familyId'] as String? : null);

      if (familyId == null || familyId.isEmpty) {
        throw Exception('createUserWithFamily did not return a familyId');
      }

      // OPTIONAL: If you keep a local user model, you can update it here:
      // UserService.currentUser?.familyId = familyId;

      // Hard replace the stack so there is no back button
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => AddChildrenPage(familyId: familyId),
        ),
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
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
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
                        validator: (val) => val == null || val.isEmpty ? 'Enter your name' : null,
                      ),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        validator: (val) => val == null || !val.contains('@') ? 'Invalid email' : null,
                      ),
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(labelText: 'Password'),
                        obscureText: true,
                        validator: (val) => val == null || val.length < 6 ? 'Too short' : null,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _register,
                        child: const Text('Create Family'),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Text(_error!, style: const TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
