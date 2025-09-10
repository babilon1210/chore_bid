import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:chore_bid/services/user_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';

// IMPORTANT: use the shared FamilyService + models from services/
// Do NOT re-declare FamilyService/FamilyChild/ChildInvite in this file.
import 'package:chore_bid/services/family_service.dart';

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
      body: const ParentSettingsView(),
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
  bool _showFamilyQR = false;
  final _familySvc = FamilyService();

  final Uri _policyUri = Uri.parse(
    'https://babilon1210.github.io/chorebid-privacy/',
  );

  Future<void> _openPolicy() async {
    final ok = await launchUrl(
      _policyUri,
      mode: LaunchMode.externalApplication,
    );
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

    // Bottom sheet to create a sign-up QR (name only)
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddChildSheet(familyId: familyId),
    );

    if (!mounted) return;
    if (result != null && result['name'] != null) {
      final name = result['name']!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite QR created for "$name".')));
    }
  }

  Future<void> _showQrDialog({
    required String title,
    required String payloadJson,
    String? subtitle,
  }) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        // Key fix: give the dialog a tight width and the QR a tight size
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 360,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (subtitle != null) ...[
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
              ],
              Center(
                child: SizedBox.square(
                  dimension: 240,
                  child: QrImageView(
                    data: payloadJson,
                    version: QrVersions.auto,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSignUpQr(String inviteCode, String childName) async {
    final payload = jsonEncode({'v': 1, 'type': 'invite', 'code': inviteCode});
    await _showQrDialog(
      title: 'Sign-up QR for $childName',
      payloadJson: payload,
      subtitle: 'Single-use • No expiry (valid until used)',
    );
  }

  Future<void> _createAndShowSignInQr({
    required String childUid,
    required String childName,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'createChildSignInCode',
      );
      final res = await callable.call({'childUid': childUid});
      final data =
          (res.data is Map)
              ? Map<String, dynamic>.from(res.data)
              : <String, dynamic>{};
      final code = data['code'] as String?;
      final expiresAtIso = data['expiresAt'] as String?;
      String? subtitle;
      if (expiresAtIso != null) {
        final dt = DateTime.tryParse(expiresAtIso);
        subtitle =
            dt != null
                ? 'Single-use • Expires at ${dt.toLocal()}'
                : 'Single-use • Short-lived';
      } else {
        subtitle = 'Single-use • Short-lived';
      }
      if (code == null || code.isEmpty) {
        throw Exception('No sign-in code returned');
      }

      final payload = jsonEncode({'v': 1, 'type': 'signin', 'code': code});
      await _showQrDialog(
        title: 'Sign-in QR for $childName',
        payloadJson: payload,
        subtitle: subtitle,
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = UserService.currentUser;
    final familyId = user?.familyId ?? '';
    final qrData = {"familyId": familyId};

    // Streams come from FamilyService (no direct Firestore queries here)
    final invitesStream = _familySvc.pendingChildInvitesStream(familyId);
    final childrenStream = _familySvc.childrenStream(familyId);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          // Family QR (for second parent)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _showFamilyQR = !_showFamilyQR),
              child: Text(
                _showFamilyQR ? 'Hide Family QR' : 'Get Family QR Code',
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Add Child (new flow)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _openAddChildSheet,
              child: const Text('Add Child'),
            ),
          ),

          const SizedBox(height: 12),

          if (_showFamilyQR)
            Center(
              child: QrImageView(
                data: qrData.toString(), // keeps compat with your existing scanner fallback
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),

          const SizedBox(height: 12),

          // Children & Invites list (scrollable)
          Expanded(
            child: ListView(
              children: [
                // Pending invites (from FamilyService)
                StreamBuilder<List<ChildInvite>>(
                  stream: invitesStream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _SectionCard(
                        title: 'Pending Invites',
                        emptyText: 'Error loading invites',
                        children: const [],
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final invites = snap.data!;
                    return _SectionCard(
                      title: 'Pending Invites',
                      emptyText: 'No pending invites',
                      children: invites.map((inv) {
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          title: Text(
                            inv.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: const Text('Sign-up QR (waiting to be used)'),
                          trailing: ElevatedButton.icon(
                            onPressed: () => _showSignUpQr(inv.code, inv.name),
                            icon: const Icon(Icons.qr_code_2),
                            label: const Text('Show QR'),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Active children (from FamilyService)
                StreamBuilder<List<FamilyChild>>(
                  stream: childrenStream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _SectionCard(
                        title: 'Children',
                        emptyText: 'Error loading children',
                        children: const [],
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final children = snap.data!;
                    return _SectionCard(
                      title: 'Children',
                      emptyText: 'No children yet',
                      children: children.map((child) {
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          title: Text(
                            child.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: const Text('Signed up'),
                          trailing: ElevatedButton.icon(
                            onPressed: () => _createAndShowSignInQr(
                              childUid: child.uid,
                              childName: child.name,
                            ),
                            icon: const Icon(Icons.qr_code),
                            label: const Text('Sign-in QR'),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

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

/// A reusable section card with a title and a list of children widgets.
class _SectionCard extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.emptyText,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color.fromARGB(255, 253, 247, 193),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color.fromARGB(255, 11, 16, 47),
              ),
            ),
            const SizedBox(height: 6),
            if (children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  emptyText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet widget for adding a child (Name only → create non-expiring invite QR)
class _AddChildSheet extends StatefulWidget {
  final String familyId;
  const _AddChildSheet({required this.familyId});

  @override
  State<_AddChildSheet> createState() => _AddChildSheetState();
}

class _AddChildSheetState extends State<_AddChildSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  String? _inviteCode; // returned from CF
  String get _qrPayload =>
      jsonEncode({'v': 1, 'type': 'invite', 'code': _inviteCode});

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _createInvite() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
      _inviteCode = null;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'createChildInvite',
      );
      final res = await callable.call({
        'familyId': widget.familyId,
        'name': _nameCtrl.text.trim(),
      });

      final data =
          (res.data is Map)
              ? Map<String, dynamic>.from(res.data)
              : <String, dynamic>{};
      final code = data['code'] as String?;
      if (code == null || code.isEmpty) {
        throw Exception('No code returned.');
      }

      setState(() => _inviteCode = code);
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

                  if (_inviteCode == null) ...[
                    Form(
                      key: _formKey,
                      child: TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: "Child's name",
                          filled: true,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
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
                            onPressed: _busy ? null : _createInvite,
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
                                : const Text('Create Sign-up QR'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Child Sign-up QR (scan with the child’s app)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color.fromARGB(255, 11, 16, 47),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: SizedBox.square(
                        dimension: 240,
                        child: QrImageView(
                          data: _qrPayload,
                          version: QrVersions.auto,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Single-use • No expiry (valid until used)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).pop({'name': _nameCtrl.text.trim()}),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 244, 190, 71),
                          foregroundColor: const Color.fromARGB(255, 11, 16, 47),
                          textStyle: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
