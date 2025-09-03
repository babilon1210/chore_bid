import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../splash_loader_page.dart';

class AddChildrenPage extends StatefulWidget {
  final String familyId; // passed in by the parent flow

  const AddChildrenPage({super.key, required this.familyId});

  @override
  State<AddChildrenPage> createState() => _AddChildrenPageState();
}

class _AddChildrenPageState extends State<AddChildrenPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController(); // optional
  final _passwordCtrl = TextEditingController();

  bool _busy = false;
  String? _error;
  final List<String> _addedChildren = []; // simple visual feedback list

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _addChild() async {
    if (!_formKey.currentState!.validate()) return;

    final familyId = widget.familyId;
    if (familyId.isEmpty) {
      setState(() => _error = "Couldn't find your family. Please try again.");
      return;
    }

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim(); // optional
    final password = _passwordCtrl.text;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Build payload; omit "email" if parent left it empty so CF can auto-generate.
      final Map<String, dynamic> payload = {
        'familyId': familyId,
        'name': name,
        'password': password,
      };
      if (email.isNotEmpty) {
        payload['email'] = email;
      }

      final callable =
          FirebaseFunctions.instance.httpsCallable('adminCreateChildInFamily');
      final res = await callable.call(payload);

      final data = (res.data is Map) ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};
      final usedEmail = data['email'] as String?; // CF returns the email it used
      // final childUid = data['childUid'] as String?; // available if you want it

      if (!mounted) return;
      setState(() {
        _addedChildren.add(name + (usedEmail != null ? ' <$usedEmail>' : ''));
        _nameCtrl.clear();
        _emailCtrl.clear();
        _passwordCtrl.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Child "$name" added.')),
      );
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SplashLoaderPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Children"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              'Family: ${widget.familyId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(labelText: "Child's name"),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? "Enter a name" : null,
                        ),
                        TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            labelText: "Child's email (optional)",
                            hintText: "Leave empty to auto-generate",
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v != null && v.isNotEmpty && !v.contains('@')) {
                              return 'Enter a valid email or leave empty';
                            }
                            return null;
                          },
                        ),
                        TextFormField(
                          controller: _passwordCtrl,
                          decoration: const InputDecoration(labelText: "Password"),
                          obscureText: true,
                          validator: (v) =>
                              (v == null || v.length < 6) ? "At least 6 characters" : null,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _addChild,
                            child: const Text('Add child'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  if (_addedChildren.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _addedChildren
                            .map((n) => Chip(
                                  label: Text(n),
                                  backgroundColor: const Color(0xFFE8F5E9),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _finish,
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
