import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:chore_bid/services/user_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ParentSettingsPage extends StatefulWidget {
  const ParentSettingsPage({super.key});

  @override
  State<ParentSettingsPage> createState() => _ParentSettingsPageState();
}

class _ParentSettingsPageState extends State<ParentSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: Colors.orange[200],
      ),
      body: const ParentSettingsView(), // reuse the embeddable view
    );
  }
}

/// Embeddable settings content (no Scaffold, no AppBar).
class ParentSettingsView extends StatefulWidget {
  const ParentSettingsView({super.key});

  @override
  State<ParentSettingsView> createState() => _ParentSettingsViewState();
}

class _ParentSettingsViewState extends State<ParentSettingsView> {
  bool _showQR = false;

  final Uri _policyUri =
      Uri.parse('https://babilon1210.github.io/chorebid-privacy/');

  Future<void> _openPolicy() async {
    final ok = await launchUrl(_policyUri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Privacy Policy')),
      );
    }
  }

  Future<void> _openAddChildSheet() async {
    final familyId = UserService.currentUser?.familyId;
    if (familyId == null || familyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No family found for this account.')),
      );
      return;
    }

    // Open the bottom sheet and wait for result
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // let us style the container
      builder: (ctx) => _AddChildSheet(familyId: familyId),
    );

    if (!mounted) return;
    if (result != null && result['name'] != null) {
      final name = result['name']!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Child "$name" added.')),
      );
    }
  }

  @override
Widget build(BuildContext context) {
  final user = UserService.currentUser;
  final familyId = user?.familyId ?? '';
  final qrData = {"familyId": familyId};

  return Padding(
    padding: const EdgeInsets.all(20.0),
    child: Column(
      children: [
        // QR toggle button (unchanged)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => setState(() => _showQR = !_showQR),
            child: Text(_showQR ? 'Hide QR Code' : 'Get Family QR Code'),
          ),
        ),

        const SizedBox(height: 12),

        // Add Child button — same look as QR button & placed right under it
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _openAddChildSheet,
            child: const Text('Add Child'),
          ),
        ),

        const SizedBox(height: 20),

        if (_showQR)
          Center(
            child: QrImageView(
              data: qrData.toString(),
              version: QrVersions.auto,
              size: 200.0,
            ),
          ),

        const Spacer(),

        // Privacy Policy
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.privacy_tip_outlined),
            label: const Text('Privacy Policy'),
            onPressed: _openPolicy,
          ),
        ),
      ],
    ),
  );
}
}

/// Bottom-sheet widget for adding a child (Name, optional Email, Password).
class _AddChildSheet extends StatefulWidget {
  final String familyId;
  const _AddChildSheet({required this.familyId});

  @override
  State<_AddChildSheet> createState() => _AddChildSheetState();
}

class _AddChildSheetState extends State<_AddChildSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController(); // optional
  final _passwordCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim(); // optional
    final password = _passwordCtrl.text;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Build payload; omit email if left blank (CF will generate)
      final payload = <String, dynamic>{
        'familyId': widget.familyId,
        'name': name,
        'password': password,
      };
      if (email.isNotEmpty) payload['email'] = email;

      final callable =
          FirebaseFunctions.instance.httpsCallable('adminCreateChildInFamily');
      final res = await callable.call(payload);

      // (Optional) read CF response if needed
      // final data = Map<String, dynamic>.from(res.data as Map);

      if (!mounted) return;
      Navigator.of(context).pop(<String, String>{'name': name});
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom; // keyboard padding
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Color.fromARGB(255, 253, 247, 193),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    'Add Child',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color.fromARGB(255, 11, 16, 47),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: "Child's name",
                            filled: true,
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            labelText: "Child's email (optional)",
                            hintText: "Leave empty to auto-generate",
                            filled: true,
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v != null && v.isNotEmpty && !v.contains('@')) {
                              return 'Enter a valid email or leave empty';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _passwordCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            filled: true,
                          ),
                          obscureText: true,
                          validator: (v) =>
                              (v == null || v.length < 6) ? 'At least 6 characters' : null,
                        ),
                      ],
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _busy ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(255, 244, 190, 71),
                            foregroundColor: const Color.fromARGB(255, 11, 16, 47),
                            textStyle: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Add child'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
