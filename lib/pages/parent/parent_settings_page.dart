import 'dart:convert';

import 'package:chore_bid/services/invite_service.dart';
import 'package:chore_bid/services/signin_service.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:chore_bid/services/user_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';

// IMPORTANT: use the shared FamilyService + models from services/
// Do NOT re-declare FamilyService/FamilyChild/ChildInvite in this file.
import 'package:chore_bid/services/family_service.dart';
import 'package:chore_bid/services/auth_service.dart'; // <-- added

class ParentSettingsPage extends StatefulWidget {
  final bool openAddChildOnOpen;

  const ParentSettingsPage({
    super.key,
    this.openAddChildOnOpen = false,
  });

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
      body: ParentSettingsView(openAddChildOnOpen: widget.openAddChildOnOpen),
    );
  }
}

/// Embeddable settings content (no Scaffold, no AppBar).
class ParentSettingsView extends StatefulWidget {
  final bool openAddChildOnOpen;

  const ParentSettingsView({
    super.key,
    this.openAddChildOnOpen = false,
  });

  @override
  State<ParentSettingsView> createState() => _ParentSettingsViewState();
}

class _ParentSettingsViewState extends State<ParentSettingsView> {
  bool _showFamilyQR = false;
  bool _childrenExpanded = false; // children dropdown
  bool _invitesExpanded = false; // invites dropdown

  final _familySvc = FamilyService();
  final _inviteSvc = InviteService();
  final _signInSvc = SignInService();
  final _authService = AuthService(); // <-- added
  bool _signingOut = false; // <-- added

  final Uri _policyUri = Uri.parse(
    'https://babilon1210.github.io/chorebid-privacy/',
  );

  // ----- Currency edit state -----
  String? _pendingCurrency; // user-picked (not yet saved)
  bool _savingCurrency = false;

  // App palette helpers
  static const _darkInk = Color.fromARGB(255, 11, 16, 47);
  static const _cardYellow = Color.fromARGB(255, 253, 247, 193);
  static const _accentYellow = Color.fromARGB(255, 244, 190, 71);
  static const _dropdownFill = Color.fromARGB(255, 255, 251, 220);

  // A compact curated list of currencies (value is what will be saved & prefixed)
  static const List<_Currency> _currencyOptions = [
    _Currency(r'$', 'US Dollar (\$)'),
    _Currency('€', 'Euro (€)'),
    _Currency('£', 'British Pound (£)'),
    _Currency('₪', 'Israeli New Shekel (₪)'),
    _Currency('CHF', 'Swiss Franc (CHF)'),
    _Currency('C\$', 'Canadian Dollar (C\$)'),
    _Currency('A\$', 'Australian Dollar (A\$)'),
    _Currency('¥', 'Japanese Yen (¥)'),
    _Currency('CN¥', 'Chinese Yuan (CN¥)'),
    _Currency('₹', 'Indian Rupee (₹)'),
    _Currency('₩', 'South Korean Won (₩)'),
    _Currency('R\$', 'Brazilian Real (R\$)'),
    _Currency('₺', 'Turkish Lira (₺)'),
  ];

  @override
  void initState() {
    super.initState();

    // Begin listening to family for live currency updates
    final familyId = UserService.currentUser?.familyId;
    if (familyId != null && familyId.isNotEmpty) {
      _familySvc.listenToFamily(familyId);
    }

    // Auto-open the Add Child sheet if requested
    if (widget.openAddChildOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAddChildSheet());
    }
  }

  @override
  void dispose() {
    _familySvc.dispose();
    super.dispose();
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite QR created for "$name".')),
      );
    }
  }

  void _cancelCurrencyEdit() {
    setState(() {
      _pendingCurrency = null; // discard changes (revert to stream value)
    });
  }

  Future<void> _saveCurrencyEdit(String currentStreamCurrency) async {
    final newValue = _pendingCurrency;
    if (newValue == null || newValue == currentStreamCurrency) return;

    final familyId = UserService.currentUser?.familyId;
    if (familyId == null || familyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No family found for this account.')),
      );
      return;
    }

    setState(() => _savingCurrency = true);
    try {
      await _familySvc.setFamilyCurrency(familyId, newValue);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Currency updated')),
      );
      setState(() {
        _pendingCurrency = null; // now matches stream; hide action buttons
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update currency: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingCurrency = false);
    }
  }

  Future<void> _showSignUpQr(String inviteCode, String childName) async {
    final payload = jsonEncode({'v': 1, 'type': 'invite', 'code': inviteCode});

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WatchingQrDialog(
        title: 'Sign-up QR for $childName',
        payloadJson: payload,
        subtitle: 'Single-use • No expiry (valid until used)',
        statusBuilder: () => _inviteSvc.watchInvite(inviteCode),
        renderStatus: (status) {
          if (status is InviteStatus) {
            switch (status.state) {
              case 'waiting':
                return const _StatusRow(
                  icon: Icons.hourglass_bottom,
                  text: 'Waiting for scan…',
                );
              case 'used':
                return _StatusRow(
                  icon: Icons.check_circle,
                  text: 'Sign-up complete!',
                  color: Colors.green,
                );
              case 'missing':
                return const _StatusRow(
                  icon: Icons.error_outline,
                  text: 'Invite not found',
                  color: Colors.red,
                );
            }
          }
          return const SizedBox.shrink();
        },
        autoCloseWhen: (status) =>
            status is InviteStatus && status.state == 'used',
      ),
    );
  }

  Future<void> _createAndShowSignInQr({
    required String childUid,
    required String childName,
  }) async {
    try {
      final created = await _signInSvc.createChildSignInCode(childUid);
      final code = created.code;
      final payload = jsonEncode({'v': 1, 'type': 'signin', 'code': code});
      String? subtitle;
      if (created.expiresAt != null) {
        subtitle = 'Single-use • Expires at ${created.expiresAt!.toLocal()}';
      } else {
        subtitle = 'Single-use • Short-lived';
      }

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WatchingQrDialog(
          title: 'Sign-in QR for $childName',
          payloadJson: payload,
          subtitle: subtitle,
          statusBuilder: () => _signInSvc.watchCode(code),
          renderStatus: (status) {
            if (status is SignInStatus) {
              switch (status.state) {
                case 'waiting':
                  final when = status.when;
                  final extra =
                      (when != null) ? ' (expires ${when.toLocal()})' : '';
                  return _StatusRow(
                    icon: Icons.hourglass_bottom,
                    text: 'Waiting for scan$extra…',
                  );
                case 'used':
                  return _StatusRow(
                    icon: Icons.check_circle,
                    text: 'Signed in!',
                    color: Colors.green,
                  );
                case 'revoked':
                  return const _StatusRow(
                    icon: Icons.block,
                    text: 'Code revoked',
                    color: Colors.red,
                  );
                case 'expired':
                  return const _StatusRow(
                    icon: Icons.timer_off,
                    text: 'Code expired',
                    color: Colors.red,
                  );
                case 'missing':
                  return const _StatusRow(
                    icon: Icons.error_outline,
                    text: 'Code not found',
                    color: Colors.red,
                  );
              }
            }
            return const SizedBox.shrink();
          },
          autoCloseWhen: (status) =>
              status is SignInStatus && status.state == 'used',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // ----- Logout (via AuthService) -----
  Future<void> _logout() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await _authService.logout();
      if (!mounted) return;
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
          // Family QR toggle
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _showFamilyQR = !_showFamilyQR),
              child:
                  Text(_showFamilyQR ? 'Hide Family QR' : 'Get Family QR Code'),
            ),
          ),
          const SizedBox(height: 12),
          if (_showFamilyQR)
            Center(
              child: QrImageView(
                data: qrData.toString(), // existing scanner compat
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),
          const SizedBox(height: 12),

          // ----- Reward Currency Card (smaller + info icon) -----
          StreamBuilder<String?>(
            stream: _familySvc.currencyStream,
            builder: (context, snap) {
              final current = snap.data ?? _familySvc.currentCurrency;
              final displayValue = _pendingCurrency ?? current;
              final changed =
                  _pendingCurrency != null && _pendingCurrency != current;

              // Build items; ensure the selected value exists even if custom
              final items = <DropdownMenuItem<String>>[
                if (!_currencyOptions.any((c) => c.value == displayValue))
                  DropdownMenuItem(
                    value: displayValue,
                    child: Text('Current: $displayValue',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ..._currencyOptions.map(
                  (c) => DropdownMenuItem(
                    value: c.value,
                    child: Text(c.label),
                  ),
                ),
              ];

              return Card(
                color: _cardYellow,
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with info icon (top-right)
                      Row(
                        children: [
                          const Icon(Icons.monetization_on_outlined,
                              color: _darkInk),
                          const SizedBox(width: 8),
                          const Text(
                            'Reward Currency',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: _darkInk,
                            ),
                          ),
                          const Spacer(),
                          if (_savingCurrency)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          IconButton(
                            tooltip: 'About reward currency',
                            icon: const Icon(Icons.info_outline, color: _darkInk),
                            onPressed: () {
                              showDialog<void>(
                                context: context,
                                builder: (_) => const AlertDialog(
                                  title: Text('About reward currency'),
                                  content: Text(
                                    'This changes how rewards are displayed throughout the app.',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      //const SizedBox(height: 10),

                      // Compact dropdown container
                      Container(
                        decoration: BoxDecoration(
                          color: _dropdownFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _accentYellow, width: 1),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x11000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 2),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: displayValue,
                            isExpanded: true,
                            icon: const Icon(Icons.expand_more, color: _darkInk),
                            style: const TextStyle(
                              color: _darkInk,
                              fontWeight: FontWeight.w700,
                            ),
                            items: items,
                            onChanged: _savingCurrency
                                ? null
                                : (v) => setState(() => _pendingCurrency = v),
                          ),
                        ),
                      ),

                      // Save / Cancel row appears only when there’s a change
                      if (changed) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed:
                                    _savingCurrency ? null : _cancelCurrencyEdit,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: _accentYellow),
                                  foregroundColor: _darkInk,
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _savingCurrency
                                    ? null
                                    : () => _saveCurrencyEdit(current),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accentYellow,
                                  foregroundColor: _darkInk,
                                  textStyle: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                                child: const Text('Save'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // MAIN AREA (fills until the bottom button)
          Expanded(
            child: StreamBuilder<List<ChildInvite>>(
              stream: invitesStream,
              builder: (context, invSnap) {
                final invites = invSnap.data ?? <ChildInvite>[];

                return StreamBuilder<List<FamilyChild>>(
                  stream: childrenStream,
                  builder: (context, chSnap) {
                    if (chSnap.hasError) {
                      return const Center(
                        child: Text('Error loading children'),
                      );
                    }
                    if (!chSnap.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    final children = chSnap.data ?? <FamilyChild>[];

                    // Build the children dropdown card (with count chip)
                    final childrenCard = _ChildrenCardExpandable(
                      title: 'Children',
                      children: children,
                      expanded: _childrenExpanded,
                      onToggle: () =>
                          setState(() => _childrenExpanded = !_childrenExpanded),
                      onAddChild: _openAddChildSheet,
                      onSignInQr: (child) => _createAndShowSignInQr(
                        childUid: child.uid,
                        childName: child.name,
                      ),
                    );

                    // Build the invites dropdown card
                    final invitesCard = _InvitesCardExpandable(
                      title: 'Pending sign ups',
                      invites: invites,
                      expanded: _invitesExpanded,
                      onToggle: () =>
                          setState(() => _invitesExpanded = !_invitesExpanded),
                      onShowQr: (inv) => _showSignUpQr(inv.code, inv.name),
                    );

                    // Only show invites if there are any AND children list is collapsed.
                    final showInvites = invites.isNotEmpty && !_childrenExpanded;

                    // Order: Children first, then Pending sign ups (only if visible)
                    return Column(
                      children: [
                        // Children dropdown
                        if (_childrenExpanded)
                          Expanded(child: childrenCard)
                        else
                          childrenCard,

                        if (showInvites) ...[
                          const SizedBox(height: 12),
                          if (_invitesExpanded)
                            Expanded(child: invitesCard)
                          else
                            invitesCard,
                        ],
                      ],
                    );
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Bottom actions: Privacy policy + Log out
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Privacy Policy'),
              onPressed: _openPolicy,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _signingOut ? null : _logout,
              icon: _signingOut
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout),
              label: Text(_signingOut ? 'Logging out…' : 'Log out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentYellow,
                foregroundColor: _darkInk,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A reusable section card (kept for consistency; not used by invites now).
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
      color: _ParentSettingsViewState._cardYellow,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _ParentSettingsViewState._darkInk,
              ),
            ),
            const SizedBox(height: 6),
            if (children.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  'No items',
                  style: TextStyle(
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

/// Expandable "Children" card with inline + button next to the title.
/// - Parent passes [expanded] and wraps in Expanded when true.
/// - When expanded, the internal list scrolls to fill available height.
class _ChildrenCardExpandable extends StatelessWidget {
  final String title;
  final List<FamilyChild> children;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAddChild;
  final void Function(FamilyChild child) onSignInQr;

  const _ChildrenCardExpandable({
    required this.title,
    required this.children,
    required this.expanded,
    required this.onToggle,
    required this.onAddChild,
    required this.onSignInQr,
  });

  @override
  Widget build(BuildContext context) {
    final count = children.length;

    return Card(
      color: _ParentSettingsViewState._cardYellow,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: title + small count chip, small "+" icon, and chevron
            Row(
              children: [
                // Tap area for expand/collapse (icon + title + count chip)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.people_alt_outlined,
                            color: _ParentSettingsViewState._darkInk,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: _ParentSettingsViewState._darkInk,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Count chip next to "Children" title
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _ParentSettingsViewState._accentYellow,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                color: _ParentSettingsViewState._darkInk,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Small + icon next to the title
                IconButton(
                  onPressed: onAddChild,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Add Child',
                  splashRadius: 20,
                ),
                // Chevron (also toggles on tap)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onToggle,
                  child: AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: expanded ? 0.5 : 0.0, // chevron flip
                    child: const Icon(
                      Icons.expand_more,
                      color: _ParentSettingsViewState._darkInk,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Content area
            if (!expanded)
              const Text(
                'Tap to show your children',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              )
            else
              // Expanded: parent already wrapped this whole card with Expanded,
              // so we can safely use Expanded here to fill the card.
              Expanded(
                child: children.isEmpty
                    ? const Center(
                        child: Text(
                          'No children yet',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: children.length,
                        separatorBuilder: (_, __) => const Divider(height: 8),
                        itemBuilder: (context, i) {
                          final child = children[i];
                          return Theme(
                            data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent,
                              visualDensity: VisualDensity.compact,
                            ),
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 4.0,
                              ),
                              title: Text(
                                child.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              leading: CircleAvatar(
                                backgroundColor:
                                    _ParentSettingsViewState._accentYellow,
                                child: Text(
                                  (child.name.isNotEmpty
                                          ? child.name[0]
                                          : '?')
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: _ParentSettingsViewState._darkInk,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      8, 0, 8, 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => onSignInQr(child),
                                          icon: const Icon(Icons.qr_code),
                                          label: const Text('Sign-in QR'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                _ParentSettingsViewState
                                                    ._accentYellow,
                                            foregroundColor:
                                                _ParentSettingsViewState
                                                    ._darkInk,
                                            textStyle: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Expandable "Pending sign ups" card (dropdown).
class _InvitesCardExpandable extends StatelessWidget {
  final String title;
  final List<ChildInvite> invites;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(ChildInvite invite) onShowQr;

  const _InvitesCardExpandable({
    required this.title,
    required this.invites,
    required this.expanded,
    required this.onToggle,
    required this.onShowQr,
  });

  @override
  Widget build(BuildContext context) {
    final count = invites.length;

    return Card(
      color: _ParentSettingsViewState._cardYellow,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with count chip and chevron
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.mail_outline,
                      color: _ParentSettingsViewState._darkInk,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title, // "Pending sign ups"
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: _ParentSettingsViewState._darkInk,
                        ),
                      ),
                    ),
                    // Small count chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _ParentSettingsViewState._accentYellow,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: _ParentSettingsViewState._darkInk,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 180),
                      turns: expanded ? 0.5 : 0.0,
                      child: const Icon(
                        Icons.expand_more,
                        color: _ParentSettingsViewState._darkInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Content area
            if (!expanded)
              const Text(
                'Tap to show pending sign ups',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              )
            else
              Expanded(
                child: invites.isEmpty
                    ? const Center(
                        child: Text(
                          'No pending sign ups',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: invites.length,
                        separatorBuilder: (_, __) => const Divider(height: 8),
                        itemBuilder: (context, i) {
                          final inv = invites[i];
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4.0),
                            title: Text(
                              inv.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'Sign-up QR (waiting to be used)',
                            ),
                            trailing: ElevatedButton.icon(
                              onPressed: () => onShowQr(inv),
                              icon: const Icon(Icons.qr_code_2),
                              label: const Text('Show QR'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _ParentSettingsViewState._accentYellow,
                                foregroundColor:
                                    _ParentSettingsViewState._darkInk,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
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

      final data = (res.data is Map)
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
            color: _ParentSettingsViewState._cardYellow,
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
                      color: _ParentSettingsViewState._darkInk,
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
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter a name'
                            : null,
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
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _busy ? null : _createInvite,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _ParentSettingsViewState._accentYellow,
                              foregroundColor:
                                  _ParentSettingsViewState._darkInk,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            child: _busy
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
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
                        color: _ParentSettingsViewState._darkInk,
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
                    // Live watch of invite usage (service-based)
                    StreamBuilder<InviteStatus>(
                      stream: InviteService().watchInvite(_inviteCode!),
                      builder: (_, snap) {
                        if (!snap.hasData) return const SizedBox.shrink();
                        final s = snap.data!;
                        if (s.state == 'waiting') {
                          return const _StatusRow(
                            icon: Icons.hourglass_bottom,
                            text: 'Waiting for scan…',
                          );
                        }
                        if (s.state == 'used') {
                          return const _StatusRow(
                            icon: Icons.check_circle,
                            text: 'Sign-up complete!',
                            color: Colors.green,
                          );
                        }
                        if (s.state == 'missing') {
                          return const _StatusRow(
                            icon: Icons.error_outline,
                            text: 'Invite not found',
                            color: Colors.red,
                          );
                        }
                        return const SizedBox.shrink();
                      },
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
                        onPressed: () => Navigator.of(context)
                            .pop({'name': _nameCtrl.text.trim()}),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _ParentSettingsViewState._accentYellow,
                          foregroundColor:
                              _ParentSettingsViewState._darkInk,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
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

class _WatchingQrDialog<T> extends StatefulWidget {
  final String title;
  final String payloadJson;
  final String? subtitle;
  final Stream<T> Function() statusBuilder;
  final Widget Function(T status) renderStatus;
  final bool Function(T status)? autoCloseWhen; // close after success

  const _WatchingQrDialog({
    required this.title,
    required this.payloadJson,
    this.subtitle,
    required this.statusBuilder,
    required this.renderStatus,
    this.autoCloseWhen,
  });

  @override
  State<_WatchingQrDialog<T>> createState() => _WatchingQrDialogState<T>();
}

class _WatchingQrDialogState<T> extends State<_WatchingQrDialog<T>> {
  Stream<T>? _stream;
  @override
  void initState() {
    super.initState();
    _stream = widget.statusBuilder();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.subtitle != null) ...[
              Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
            ],
            Center(
              child: SizedBox.square(
                dimension: 240,
                child: QrImageView(
                  data: widget.payloadJson,
                  version: QrVersions.auto,
                ),
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<T>(
              stream: _stream,
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const _StatusRow(
                    icon: Icons.hourglass_bottom,
                    text: 'Waiting for scan…',
                  );
                }
                final status = snap.data as T;
                final w = widget.renderStatus(status);

                // Auto-close on success
                final shouldClose =
                    widget.autoCloseWhen?.call(status) ?? false;
                if (shouldClose) {
                  Future.delayed(const Duration(milliseconds: 900), () {
                    if (mounted) Navigator.of(context).maybePop();
                  });
                }
                return w;
              },
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
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _StatusRow({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color ?? Colors.black87),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: color ?? Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

class _Currency {
  final String value; // what we store in Firestore & prefix before amounts
  final String label; // what we show in the dropdown
  const _Currency(this.value, this.label);
}
