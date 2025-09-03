import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:chore_bid/pages/qr_scanner_page.dart';
import 'package:chore_bid/services/auth_service.dart';

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

  Future<void> _scanQrCode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerPage()),
    );

    if (result != null) {
      try {
        // Try a few formats: raw text or JSON
        String? id;
        // pattern like: "familyId: ABC123"
        final match = RegExp(r'familyId[:=]\s*([a-zA-Z0-9_-]+)').firstMatch(result);
        if (match != null) {
          id = match.group(1);
        } else {
          // maybe JSON
          final decoded = jsonDecode(result);
          if (decoded is Map && decoded['familyId'] is String) {
            id = decoded['familyId'] as String;
          }
        }

        if (id == null || id.isEmpty) {
          throw Exception("familyId not found in result");
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

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    if (familyId == null) {
      setState(() => _qrScanError = "Please scan a parent's QR code first.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String email = _emailController.text.trim();
      if (widget.role == 'child' && email.isEmpty) {
        email = 'child_${DateTime.now().millisecondsSinceEpoch}@chorbit.email';
      }

      final user = await _authService.register(
        name: _nameController.text.trim(),
        email: email,
        password: _passwordController.text,
        role: widget.role,
      );

      if (user != null && mounted) {
        final callable = FirebaseFunctions.instance.httpsCallable('createUserWithFamily');
        await callable.call({
          'role': widget.role,
          'name': _nameController.text.trim(),
          'familyId': familyId,
        });

        Navigator.pushReplacementNamed(context, '/splash');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Widget _qrSection() {
    // If we already have a familyId, hide the scan button and show a success chip
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
          TextButton(
            onPressed: _clearScan, // optional “Change” to rescan
            child: const Text('Change'),
          ),
        ],
      );
    }

    // No family yet → show scan button
    return ElevatedButton(
      onPressed: _scanQrCode,
      child: const Text('Scan Parent QR'),
    );
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
                        validator: (val) {
                          if (!isChild && (val == null || !val.contains('@'))) {
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
      
                      // QR section (button OR success box)
                      _qrSection(),
      
                      if (_qrScanError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(_qrScanError!, style: const TextStyle(color: Colors.red)),
                        ),
                      const SizedBox(height: 20),
      
                      ElevatedButton(
                        onPressed: _register,
                        child: const Text('Sign Up'),
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
