// lib/pages/parent/home_page.dart
import 'package:chore_bid/pages/parent/chore_info_page.dart';
import 'package:chore_bid/pages/parent/parent_settings_page.dart'; // provides ParentSettingsView too
import 'package:chore_bid/pages/parent/parent_wallet_page.dart'; // PERSISTENT Wallets tab
import 'package:chore_bid/services/chore_service.dart';
import 'package:chore_bid/services/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/chore_model.dart';
import '../../widgets/chore_card.dart';
import 'create_chore_bid_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _Section { active, review, paid, expired }

class _HomePageState extends State<HomePage> {
  // 0 = chores, 1 = wallets, 2 = settings
  int _selectedIndex = 0;

  // Which chores sub-section is visible (exclusive).
  _Section _selected = _Section.active;

  // Recent expired chores via second stream
  List<Chore> _expiredRecent = [];

  // ---------- Palette memory (id -> palette index) ----------
  // This keeps the color chosen for a chore so it stays consistent across lists.
  final Map<String, int> _paletteIndexByChoreId = {};
  int _wrapCursor = 0;

  @override
  void initState() {
    super.initState();

    final familyId = UserService.currentUser?.familyId;
    if (familyId != null) {
      // Active/non-expired stream (updates UserService.currentUser!.chores)
      ChoreService().listenToChores(familyId).listen((_) {
        if (mounted) setState(() {});
      });

      // Expired (recent) stream - last 60 days by deadline
      final cutoff = DateTime.now().subtract(const Duration(days: 60));
      FirebaseFirestore.instance
          .collection('families')
          .doc(familyId)
          .collection('chores')
          .where('status', isEqualTo: 'expired')
          .where('deadline', isGreaterThanOrEqualTo: cutoff)
          .orderBy('deadline', descending: true)
          .snapshots()
          .listen((snap) {
            final list =
                snap.docs.map((d) => Chore.fromMap(d.data(), d.id)).toList();
            if (mounted) {
              setState(() => _expiredRecent = list);
            }
          });
    }
  }

  // ---------- Helpers ----------
  // Extract status from either legacy String or new {status, time} map
  String? _statusFrom(dynamic v) {
    if (v is String) return v; // legacy
    if (v is Map<String, dynamic>) return v['status'] as String?;
    if (v is Map) return v['status'] as String?; // extra safety
    return null;
  }

  bool _isDoneStatus(String? s) =>
      s == 'complete' || s == 'verified' || s == 'paid';

  bool _hasAny(Chore c, String status) =>
      (c.progress ?? const <String, dynamic>{}).values.any(
        (v) => _statusFrom(v) == status,
      );

  bool _hasAnyDone(Chore c) => (c.progress ?? const <String, dynamic>{}).values
      .any((v) => _isDoneStatus(_statusFrom(v)));

  bool _hasAnyComplete(Chore c) => _hasAny(c, 'complete');
  bool _hasAnyVerified(Chore c) => _hasAny(c, 'verified');
  bool _hasAnyPaid(Chore c) => _hasAny(c, 'paid');

  // NEW: determine if any child has claimed the chore
  bool _hasAnyClaimed(Chore c) => _hasAny(c, 'claimed');

  bool _isChoreCompletedForActive(Chore c) {
    if (c.status == 'expired') return false;
    return _hasAnyDone(c);
  }

  // Combine up-to-date active chores + recent expired (dedup)
  List<Chore> get _allChores {
    final map = <String, Chore>{};
    for (final c in UserService.currentUser?.chores ?? const <Chore>[]) {
      map[c.id] = c;
    }
    for (final c in _expiredRecent) {
      map[c.id] = c;
    }
    return map.values.toList();
  }

  // ---------- Buckets ----------
  // Active chores: claimed ones should appear first, then by earliest deadline.
  List<Chore> get _activeList =>
      (UserService.currentUser?.chores ?? const <Chore>[])
          .where((c) => c.status != 'expired' && !_isChoreCompletedForActive(c))
          .toList()
        ..sort((a, b) {
          final aClaimed = _hasAnyClaimed(a) ? 0 : 1; // claimed first
          final bClaimed = _hasAnyClaimed(b) ? 0 : 1;
          if (aClaimed != bClaimed) return aClaimed - bClaimed;
          // tie-breaker: earlier deadline first
          final byDeadline = a.deadline.compareTo(b.deadline);
          if (byDeadline != 0) return byDeadline;
          // final tie-breaker: stable-ish by id
          return a.id.compareTo(b.id);
        });

  // Awaiting review:
  // - Non-exclusive: show if ANY child is 'complete' (even if others are 'verified'/'paid').
  // - Exclusive: show if 'complete' exists and there is NO 'verified'.
  List<Chore> get _reviewAwaitingReviewList =>
      _allChores
          .where(
            (c) => c.isExclusive
                ? (_hasAnyComplete(c) && !_hasAnyVerified(c))
                : _hasAnyComplete(c),
          )
          .toList()
        ..sort((a, b) => b.deadline.compareTo(a.deadline));

  // Awaiting payment: show if ANY child is 'verified' (even if others are 'paid').
  List<Chore> get _reviewAwaitingPaymentList =>
      _allChores.where((c) => _hasAnyVerified(c)).toList()
        ..sort((a, b) => b.deadline.compareTo(a.deadline));

  // REVIEW (total): union of both sublists (unique chores)
  List<Chore> get _reviewList {
    final ids = <String>{};
    final List<Chore> out = [];
    for (final c in _reviewAwaitingReviewList) {
      if (ids.add(c.id)) out.add(c);
    }
    for (final c in _reviewAwaitingPaymentList) {
      if (ids.add(c.id)) out.add(c);
    }
    return out;
  }

  // PAID: any child at 'paid'
  List<Chore> get _paidList =>
      _allChores.where(_hasAnyPaid).toList()
        ..sort((a, b) => b.deadline.compareTo(a.deadline));

  // EXPIRED (NO COMPLETION): expired chores with no child at complete/verified/paid
  List<Chore> get _expiredNoCompletion =>
      _expiredRecent.where((c) => !_hasAnyDone(c)).toList()
        ..sort((a, b) => b.deadline.compareTo(a.deadline));

  // ---------- Palette assignment ----------
  void _assignPaletteIndicesTo(List<Chore> items) {
    if (items.isEmpty) return;
    final N = ChoreCard.happyColors.length;
    final used = <int>{};

    // Keep already assigned indices for visible items and mark as used.
    for (final c in items) {
      final existing = _paletteIndexByChoreId[c.id];
      if (existing != null) used.add(existing);
    }

    // Assign indices to new chores so no repeats until palette is exhausted.
    for (final c in items) {
      if (_paletteIndexByChoreId.containsKey(c.id)) continue;

      // Find a free index
      int? free;
      for (int k = 0; k < N; k++) {
        if (!used.contains(k)) {
          free = k;
          break;
        }
      }

      if (free == null) {
        // Palette exhausted; wrap (spread repeats with a cursor)
        free = _wrapCursor % N;
        _wrapCursor++;
      }

      _paletteIndexByChoreId[c.id] = free;
      used.add(free);
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    // Make sure palette indices exist for the lists where color matters.
    // Active chores should be colorful and unique.
    _assignPaletteIndicesTo(_activeList);
    // Keep color when an item moves to "awaiting review".
    _assignPaletteIndicesTo(_reviewAwaitingReviewList);
    // Also assign for awaiting payment so items keep color (even if colored green in card).
    _assignPaletteIndicesTo(_reviewAwaitingPaymentList);

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 244, 190, 71),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          'Chorebid',
          style: GoogleFonts.pacifico(
            fontSize: 30,
            color: const Color.fromARGB(255, 11, 16, 47),
          ),
          textAlign: TextAlign.center,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            // --- Tab 0: CHORES ---
            Row(
              children: [
                _buildVerticalTabs(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
                    child: _buildExpandedSection(),
                  ),
                ),
              ],
            ),

            // --- Tab 1: WALLETS (ParentWalletPage) ---
            // Stays inside the same Scaffold so the BottomNavigationBar persists.
            const ParentWalletPage(),

            // --- Tab 2: SETTINGS ---
            const ParentSettingsView(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color.fromARGB(255, 255, 233, 164),
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.black45,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Chores'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Wallets',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton:
          _selectedIndex == 0
              ? FloatingActionButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreateChoreBidPage(
                          user: UserService.currentUser!,
                        ),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                  tooltip: 'Create New Chore Bid',
                  child: const Icon(Icons.add),
                )
              : null,
    );
  }

  // --- Chores tab pieces (tab 0) ---

  Widget _buildVerticalTabs() {
    // Order they appear in the vertical rail
    final order = <_Section>[
      _Section.active,
      _Section.review,
      _Section.paid,
      _Section.expired,
    ];

    final models = <_Section, _SectionModel>{
      _Section.active: _SectionModel(
        key: _Section.active,
        title: 'Active Chores',
        shortLabel: 'Active',
        count: _activeList.length,
        color: const Color.fromARGB(255, 243, 231, 172),
      ),
      _Section.review: _SectionModel(
        key: _Section.review,
        title: 'Review & Pay',
        shortLabel: 'Review',
        count: _reviewList.length, // union of both tabs
        color: const Color.fromARGB(255, 251, 213, 184),
      ),
      _Section.paid: _SectionModel(
        key: _Section.paid,
        title: 'Paid',
        shortLabel: 'Paid',
        count: _paidList.length,
        color: const Color.fromARGB(255, 214, 240, 204),
      ),
      _Section.expired: _SectionModel(
        key: _Section.expired,
        title: 'Expired (no completion)',
        shortLabel: 'Expired',
        count: _expiredNoCompletion.length,
        color: const Color.fromARGB(255, 255, 130, 130),
      ),
    };

    return _VerticalTabs(
      sections: order.map((s) => models[s]!).toList(),
      selected: _selected,
      onSelect: (s) => setState(() => _selected = s),
    );
  }

  Widget _buildExpandedSection() {
    final models = <_Section, _ExpandedSectionModel>{
      _Section.active: _ExpandedSectionModel(
        title: 'Active Chores',
        color: const Color.fromARGB(255, 243, 231, 172),
        child: _buildList(
          items: _activeList,
          empty: const _EmptyLine('No active chores right now.'),
        ),
        count: _activeList.length,
      ),
      _Section.review: _ExpandedSectionModel(
        title: 'Review & Pay',
        color: const Color.fromARGB(255, 251, 213, 184),
        child: _ReviewTabView(
          awaitingReview: _reviewAwaitingReviewList,
          awaitingPayment: _reviewAwaitingPaymentList,
          // pass through the palette mapper so items keep their color
          paletteIndexOf: (id) => _paletteIndexByChoreId[id],
        ),
        count: _reviewList.length, // union count
      ),
      _Section.paid: _ExpandedSectionModel(
        title: 'Paid',
        color: const Color.fromARGB(255, 214, 240, 204),
        child: _buildList(
          items: _paidList,
          empty: const _EmptyLine('No paid chores yet.'),
        ),
        count: _paidList.length,
      ),
      _Section.expired: _ExpandedSectionModel(
        title: 'Expired (no completion)',
        color: const Color.fromARGB(255, 255, 130, 130),
        child: _buildList(
          items: _expiredNoCompletion,
          empty: const _EmptyLine('No expired chores without completion.'),
        ),
        count: _expiredNoCompletion.length,
      ),
    };

    final m = models[_selected]!;
    return _ExpandedSectionCard(
      title: m.title,
      count: m.count,
      color: m.color,
      child: m.child,
    );
  }

  Widget _buildList({required List<Chore> items, required Widget empty}) {
    if (items.isEmpty) return empty;

    // Ensure palette indices exist for the items shown in this list.
    _assignPaletteIndicesTo(items);

    return Scrollbar(
      thumbVisibility: true,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 10, bottom: 10, right: 6, left: 6),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final chore = items[i];
          return ChoreCard(
            title: chore.title,
            description: chore.description,
            reward: chore.reward,
            status: chore.status,
            isExclusive: chore.isExclusive,
            assignedTo: chore.assignedTo,
            progress: chore.progress,
            deadline: chore.deadline,
            paletteIndex: _paletteIndexByChoreId[chore.id], // <— keep color
            showRightDeadline: true, // <— ALWAYS show deadline on the right (parent request)
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChoreInfoPage(chore: chore)),
              );
              if (mounted) setState(() {});
            },
          );
        },
      ),
    );
  }
}

/// Narrow left rail of vertical tabs.
class _VerticalTabs extends StatelessWidget {
  final List<_SectionModel> sections;
  final _Section selected;
  final ValueChanged<_Section> onSelect;

  const _VerticalTabs({
    required this.sections,
    required this.selected,
    required this.onSelect,
  });

  String _verticalize(String s) => s.split('').join('\n');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      padding: const EdgeInsets.fromLTRB(8, 8, 6, 12),
      child: Column(
        children:
            sections.map((m) {
              final isSelected = m.key == selected;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: isSelected ? m.color : m.color.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    elevation: isSelected ? 4 : 1,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onSelect(m.key),
                      child: Stack(
                        children: [
                          Center(
                            child: Text(
                              _verticalize(m.shortLabel),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                height: 1.0,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Color.fromARGB(255, 14, 20, 61),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '(${m.count})',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color.fromARGB(255, 14, 20, 61),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

class _ExpandedSectionCard extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final Widget child;

  const _ExpandedSectionCard({
    required this.title,
    required this.count,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$title • $count',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color.fromARGB(255, 14, 20, 61),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Divider(height: 1, color: Color(0x33000000)),
            const SizedBox(height: 6),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;
  const _EmptyLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0B102F),
        ),
      ),
    );
  }
}

class _SectionModel {
  final _Section key;
  final String title;
  final String shortLabel;
  final int count;
  final Color color;
  _SectionModel({
    required this.key,
    required this.title,
    required this.shortLabel,
    required this.count,
    required this.color,
  });
}

class _ExpandedSectionModel {
  final String title;
  final int count;
  final Color color;
  final Widget child;
  _ExpandedSectionModel({
    required this.title,
    required this.count,
    required this.color,
    required this.child,
  });
}

/// Internal two-tab view used inside the Review section.
/// Styled like a pill/segmented control:  [ Awaiting review | Awaiting payment ]
class _ReviewTabView extends StatefulWidget {
  final List<Chore> awaitingReview;
  final List<Chore> awaitingPayment;

  /// Ask parent for a palette index so cards keep their color across lists.
  final int? Function(String choreId) paletteIndexOf;

  const _ReviewTabView({
    required this.awaitingReview,
    required this.awaitingPayment,
    required this.paletteIndexOf,
  });

  @override
  State<_ReviewTabView> createState() => _ReviewTabViewState();
}

class _ReviewTabViewState extends State<_ReviewTabView> {
  int _index = 0; // 0 = Awaiting review, 1 = Awaiting payment

  @override
  Widget build(BuildContext context) {
    // Base colors inspired by “Active | History”
    final Color railBg = Colors.white.withOpacity(0.55);
    final Color pillSel = Colors.white;
    final Color textSel = const Color(0xFF0B102F);
    final Color textUnsel = const Color(0xCCFFFFFF);

    return Column(
      children: [
        // Segmented header
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: railBg,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              _SegmentedPill(
                label: 'Awaiting review (${widget.awaitingReview.length})',
                selected: _index == 0,
                onTap: () => setState(() => _index = 0),
                selectedColor: pillSel,
                selectedTextColor: textSel,
                unselectedTextColor: textUnsel,
              ),
              const SizedBox(width: 6),
              _SegmentedPill(
                label: 'Awaiting payment (${widget.awaitingPayment.length})',
                selected: _index == 1,
                onTap: () => setState(() => _index = 1),
                selectedColor: pillSel,
                selectedTextColor: textSel,
                unselectedTextColor: textUnsel,
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Content
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child:
                _index == 0
                    ? _BulkReviewList(
                        key: const ValueKey('awaiting_review'),
                        items: widget.awaitingReview,
                        mode: _BulkMode.awaitingReview,
                        paletteIndexOf: widget.paletteIndexOf,
                      )
                    : _BulkReviewList(
                        key: const ValueKey('awaiting_payment'),
                        items: widget.awaitingPayment,
                        mode: _BulkMode.awaitingPayment,
                        paletteIndexOf: widget.paletteIndexOf,
                      ),
          ),
        ),
      ],
    );
  }
}

/// One side of the segmented control
class _SegmentedPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;
  final Color selectedTextColor;
  final Color unselectedTextColor;

  const _SegmentedPill({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.selectedColor,
    required this.selectedTextColor,
    required this.unselectedTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? selectedColor : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow:
                selected
                    ? const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected ? selectedTextColor : unselectedTextColor,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

enum _BulkMode { awaitingReview, awaitingPayment }

/// Review list that supports long-press multi-select and bulk actions.
class _BulkReviewList extends StatefulWidget {
  final List<Chore> items;
  final _BulkMode mode;

  final int? Function(String choreId) paletteIndexOf;

  const _BulkReviewList({
    super.key,
    required this.items,
    required this.mode,
    required this.paletteIndexOf,
  });

  @override
  State<_BulkReviewList> createState() => _BulkReviewListState();
}

class _BulkReviewListState extends State<_BulkReviewList> {
  final Set<String> _selectedIds = {};
  bool _busy = false;

  bool get _selectionMode => _selectedIds.isNotEmpty;
  bool get _allSelected =>
      widget.items.isNotEmpty && _selectedIds.length == widget.items.length;

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelect(String id) {
    if (_selectionMode && _selectedIds.contains(id)) return;
    setState(() {
      _selectedIds.add(id);
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(widget.items.map((c) => c.id));
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  int _parseAmountCents(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[^0-9\.,]'), '');
    if (s.contains(',') && !s.contains('.')) {
      s = s.replaceAll(',', '.');
    } else if (s.contains(',') && s.contains('.')) {
      s = s.replaceAll(',', '');
    }
    final value = double.tryParse(s) ?? 0.0;
    return (value * 100).round();
  }

  Future<void> _bulkVerify() async {
    if (_busy) return;
    setState(() => _busy = true);

    final familyId = UserService.currentUser!.familyId!;
    int ops = 0;

    try {
      for (final id in _selectedIds.toList()) {
        final idx = widget.items.indexWhere((c) => c.id == id);
        if (idx == -1) continue;
        final chore = widget.items[idx];

        final Map<String, dynamic> prog = chore.progress ?? const {};
        for (final entry in prog.entries) {
          final val = entry.value;
          if (val is Map<String, dynamic>) {
            final status = val['status'] as String?;
            if (status == 'complete') {
              await ChoreService().markChoreAsVerified(
                familyId: familyId,
                choreId: chore.id,
                childId: entry.key,
                time: DateTime.now(),
              );
              ops++;
            }
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Verified $ops completion(s).')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _selectedIds.clear();
          _busy = false;
        });
      }
    }
  }

  Future<void> _bulkPay() async {
    if (_busy) return;
    setState(() => _busy = true);

    final familyId = UserService.currentUser!.familyId!;
    final payer = UserService.currentUser!.uid;
    int ops = 0;

    try {
      for (final id in _selectedIds.toList()) {
        final idx = widget.items.indexWhere((c) => c.id == id);
        if (idx == -1) continue;
        final chore = widget.items[idx];

        final Map<String, dynamic> prog = chore.progress ?? const {};
        final amountCents = _parseAmountCents(chore.reward);

        for (final entry in prog.entries) {
          final val = entry.value;
          if (val is Map<String, dynamic>) {
            final status = val['status'] as String?;
            if (status == 'verified') {
              await ChoreService().markChoreAsPaid(
                familyId: familyId,
                choreId: chore.id,
                childId: entry.key,
                amountCents: amountCents,
                currency: 'ILS',
                method: 'cash',
                paidByUid: payer,
                paidAt: DateTime.now(),
              );
              ops++;
            }
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Paid $ops verification(s).')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _selectedIds.clear();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Center(
        child: Text(
          widget.mode == _BulkMode.awaitingReview
              ? 'Nothing awaiting review.'
              : 'No chores awaiting payment.',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B102F),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Selection toolbar appears only when multi-select is active
        if (_selectionMode)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x15000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Text(
                  '${_selectedIds.length} selected',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0B102F),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _toggleSelectAll,
                  icon: const Icon(Icons.select_all),
                  label: Text(
                    _allSelected
                        ? 'Unselect all'
                        : 'Select all (${widget.items.length})',
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: _clearSelection,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),

        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              itemCount: widget.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final chore = widget.items[i];
                final selected = _selectedIds.contains(chore.id);

                return GestureDetector(
                  onLongPress: () => _enterSelect(chore.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border:
                          selected
                              ? Border.all(color: Colors.indigo, width: 2)
                              : null,
                    ),
                    child: Stack(
                      children: [
                        // Use the same card; onTap navigates unless in select mode.
                        ChoreCard(
                          title: chore.title,
                          description: chore.description,
                          reward: chore.reward,
                          status: chore.status,
                          isExclusive: chore.isExclusive,
                          assignedTo: chore.assignedTo,
                          progress: chore.progress,
                          deadline: chore.deadline,
                          paletteIndex: widget.paletteIndexOf(chore.id),
                          showRightDeadline:
                              true, // <— ALWAYS show deadline on the right (parent request)
                          onTap: () async {
                            if (_selectionMode) {
                              _toggle(chore.id);
                            } else {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChoreInfoPage(chore: chore),
                                ),
                              );
                            }
                          },
                        ),
                        if (selected)
                          const Positioned(
                            right: 10,
                            top: 10,
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.indigo,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        if (_selectionMode) const SizedBox(height: 10),
        if (_selectionMode)
          SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    _busy
                        ? null
                        : (widget.mode == _BulkMode.awaitingReview
                            ? _bulkVerify
                            : _bulkPay),
                icon: Icon(
                  widget.mode == _BulkMode.awaitingReview
                      ? Icons.verified
                      : Icons.attach_money,
                ),
                label: Text(
                  widget.mode == _BulkMode.awaitingReview
                      ? 'Verify selected'
                      : 'Pay selected',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      widget.mode == _BulkMode.awaitingReview
                          ? Colors.indigo
                          : Colors.green[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
