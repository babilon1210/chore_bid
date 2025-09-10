import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:chore_bid/pages/qr_scanner_page.dart';
import 'package:chore_bid/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  String? familyId;
  String? _error;
  String? _qrScanError;
  bool _loading = false;

  // -------------------- CHILD FLOW (new) --------------------
  Future<void> _scanInviteAndSignIn() async {
    // Opens your existing scanner page to get raw string back
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
      // Expect a JSON payload like: {"v":1,"type":"invite","code":"<...>"}
      String? code;
      try {
        final decoded = jsonDecode(result);
        if (decoded is Map && decoded['code'] is String) {
          code = decoded['code'] as String;
        }
      } catch (_) {
        // Fallback: allow plain code text
        if (result is String && result.trim().isNotEmpty) {
          code = result.trim();
        }
      }

      if (code == null || code.isEmpty) {
        throw Exception('Invalid QR. Try again.');
      }

      setState(() => _loading = true);

      // Redeem the code (Cloud Function creates child if needed, then returns a custom token)
      final callable = FirebaseFunctions.instance.httpsCallable('redeemCode');
      final res = await callable.call({'code': code});
      final data = (res.data is Map) ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};
      final token = data['customToken'] as String?;

      if (token == null || token.isEmpty) {
        throw Exception('Could not sign in with this code.');
      }

      // Sign in with the custom token
      await FirebaseAuth.instance.signInWithCustomToken(token);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome!')),
      );
      Navigator.pushReplacementNamed(context, '/splash');
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------- OLD (second parent) FLOW (unchanged UI) --------------------
  Future<void> _scanFamilyQrToGetFamilyId() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerPage()),
    );

    if (result != null) {
      try {
        // Accept either "familyId: ABC123" OR {"familyId":"ABC123"}
        String? id;
        final match = RegExp(r'familyId[:=]\s*([a-zA-Z0-9_-]+)').firstMatch(result);
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
            content: Text('QR Scan successful'),
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
      final user = await _authService.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: 'parent',
      );

      if (user != null && mounted) {
        final callable = FirebaseFunctions.instance.httpsCallable('createUserWithFamily');
        await callable.call({
          'role': 'parent',
          'name': _nameController.text.trim(),
          'familyId': familyId,
        });

        Navigator.pushReplacementNamed(context, '/splash');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------- UI --------------------
  Widget _secondParentQrSection() {
    if (familyId != null) {
      return Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF81C784)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
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
      );
    }

    return ElevatedButton(
      onPressed: _scanFamilyQrToGetFamilyId,
      child: const Text('Scan Family QR'),
    );
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
    final isChild = widget.role == 'child';

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text(isChild ? 'Join as Child' : 'Join as Parent')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (isChild ? _buildChildBody() : _buildSecondParentBody()),
        ),
      ),
    );
  }

  // --------- New CHILD signup: only scan invite QR ---------
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
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }

  // --------- Existing SECOND PARENT join flow (unchanged) ---------
  Widget _buildSecondParentBody() {
    return Form(
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
            validator: (val) {
              if (val == null || !val.contains('@')) {
                return 'Valid email required';
              }
              return null;
            },
          ),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            validator: (val) => val == null || val.length < 6 ? 'Too short' : null,
          ),
          const SizedBox(height: 10),
          _secondParentQrSection(),
          if (_qrScanError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(_qrScanError!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _registerSecondParent,
            child: const Text('Sign Up'),
          ),
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
