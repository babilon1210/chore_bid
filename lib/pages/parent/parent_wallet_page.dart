import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/chore_model.dart';
import '../../services/user_service.dart';
import '../../services/family_service.dart';
import '../../services/chore_service.dart';

enum ParentWalletTab { pending, paid }
enum RangePreset { week, month, year, custom }

class ParentWalletPage extends StatefulWidget {
  const ParentWalletPage({super.key});

  @override
  State<ParentWalletPage> createState() => _ParentWalletPageState();
}

class _ParentWalletPageState extends State<ParentWalletPage> {
  final _df = DateFormat.yMMMd();
  ParentWalletTab _tab = ParentWalletTab.pending;

  // ----- timeframe filter -----
  RangePreset _range = RangePreset.week;
  DateTimeRange? _customRange;

  // ----- services -----
  final _familySvc = FamilyService();
  final _choreSvc = ChoreService();

  StreamSubscription<List<Chore>>? _choresSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _expiredSub;

  // NEW: live children subscription
  StreamSubscription<List<FamilyChild>>? _childrenSub;

  // currency (from FamilyService)
  StreamSubscription<String?>? _currencySub;
  String _currencySymbol = r'$';

  // ----- data -----
  List<Chore> _activeChores = [];
  List<Chore> _expiredRecent = [];
  Map<String, String> _childNames = {}; // uid -> name
  String? _selectedChildId;

  String get _familyId => UserService.currentUser!.familyId!;
  String get _parentUid => UserService.currentUser!.uid;

  List<Chore> get _allChores {
    final map = <String, Chore>{};
    for (final c in _activeChores) map[c.id] = c;
    for (final c in _expiredRecent) map[c.id] = c;
    return map.values.toList()..sort((a, b) => b.deadline.compareTo(a.deadline));
  }

  List<String> get _childIds => _childNames.keys.toList()..sort();

  // ----- lifecycle -----
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // start listening to family so currency stays live
    _familySvc.listenToFamily(_familyId);
    _currencySymbol = _familySvc.currentCurrency;
    _currencySub = _familySvc.currencyStream.listen((sym) {
      if (!mounted) return;
      if (sym != null && sym.isNotEmpty && sym != _currencySymbol) {
        setState(() => _currencySymbol = sym);
      }
    });

    // NEW: Live children listener — updates immediately when children change
    _childrenSub = _familySvc.childrenStream(_familyId).listen((children) {
      if (!mounted) return;
      // Build latest names map
      final nextNames = <String, String>{
        for (final c in children) c.uid: (c.name.isEmpty ? 'Child' : c.name),
      };

      // Preserve selection when possible; if the selected child was removed, pick first.
      String? nextSelected = _selectedChildId;
      if (nextSelected == null || !nextNames.containsKey(nextSelected)) {
        nextSelected = nextNames.isNotEmpty ? (nextNames.keys.toList()..sort()).first : null;
      }

      setState(() {
        _childNames = nextNames;
        _selectedChildId = nextSelected;
      });
    });

    // 2) Listen to active chores (family scope)
    _choresSub = _choreSvc.listenToChores(_familyId).listen((list) {
      if (!mounted) return;
      setState(() => _activeChores = list);
    });

    // 3) Also keep recent expired to show recently-paid items (last 60d)
    final cutoff = DateTime.now().subtract(const Duration(days: 60));
    _expiredSub = FirebaseFirestore.instance
        .collection('families')
        .doc(_familyId)
        .collection('chores')
        .where('status', isEqualTo: 'expired')
        .limit(200)
        .snapshots()
        .listen((snap) {
      final list = snap.docs
          .map((d) => Chore.fromMap(d.data(), d.id))
          .where((c) => c.deadline.isAfter(cutoff))
          .toList()
        ..sort((a, b) => b.deadline.compareTo(a.deadline));
      if (mounted) setState(() => _expiredRecent = list);
    });
  }

  @override
  void dispose() {
    _choresSub?.cancel();
    _expiredSub?.cancel();
    _childrenSub?.cancel(); // NEW
    _currencySub?.cancel();
    _familySvc.dispose();
    super.dispose();
  }

  // ----- helpers for progress schema (keeps legacy fallback) -----
  String? _statusFor(Chore c, String childId) {
    final v = c.progress?[childId];
    if (v is String) return v; // legacy fallback
    if (v is Map<String, dynamic>) return v['status'] as String?;
    return null;
  }

  DateTime? _timeFor(Chore c, String childId) {
    final v = c.progress?[childId];
    if (v is Map<String, dynamic>) {
      final t = v['time'];
      if (t is Timestamp) return t.toDate();
      if (t is DateTime) return t;
    }
    return null;
  }

  // ----- amount helpers -----
  int _sumRewards(List<Chore> chores) =>
      chores.fold(0, (sum, c) => sum + (int.tryParse(c.reward) ?? 0));

  String _money(int amount) => '$_currencySymbol$amount';

  int _toCents(int major) => major * 100;

  // ----- timeframe helpers -----
  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  DateTimeRange get _activeRange {
    final now = DateTime.now();
    switch (_range) {
      case RangePreset.week:
        return DateTimeRange(
          start: _startOfDay(now.subtract(const Duration(days: 6))),
          end: _endOfDay(now),
        );
      case RangePreset.month:
        return DateTimeRange(
          start: _startOfDay(now.subtract(const Duration(days: 29))),
          end: _endOfDay(now),
        );
      case RangePreset.year:
        return DateTimeRange(
          start: _startOfDay(now.subtract(const Duration(days: 364))),
          end: _endOfDay(now),
        );
      case RangePreset.custom:
        final r = _customRange ??
            DateTimeRange(
              start: _startOfDay(now.subtract(const Duration(days: 6))),
              end: _endOfDay(now),
            );
        return DateTimeRange(start: _startOfDay(r.start), end: _endOfDay(r.end));
    }
  }

  bool _inSelectedRange(DateTime? t) {
    if (t == null) return false;
    final r = _activeRange;
    return (t.isAfter(r.start) || t.isAtSameMomentAs(r.start)) &&
        (t.isBefore(r.end) || t.isAtSameMomentAs(r.end));
  }

  String _rangeLabel() {
    switch (_range) {
      case RangePreset.week:
        return 'Past 7 days';
      case RangePreset.month:
        return 'Past 30 days';
      case RangePreset.year:
        return 'Past 365 days';
      case RangePreset.custom:
        final r = _activeRange;
        return '${_df.format(r.start)} — ${_df.format(r.end)}';
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = _customRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 6)),
          end: now,
        );

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      helpText: 'Select custom range',
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _range = RangePreset.custom;
      });
    }
  }

  void _openRangeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        Widget tile({
          required String title,
          String? subtitle,
          required IconData icon,
          required RangePreset value,
        }) {
          final selected = _range == value;
          return ListTile(
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF0B102F).withOpacity(0.08),
              child: Icon(icon, color: const Color(0xFF0B102F)),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF0B102F),
              ),
            ),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: selected ? const Icon(Icons.check_circle, color: Colors.indigo) : null,
            onTap: () async {
              if (value == RangePreset.custom) {
                Navigator.pop(ctx); // close sheet then pick range
                await _pickCustomRange();
              } else {
                setState(() => _range = value);
                Navigator.pop(ctx);
              }
            },
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                Text(
                  'Filter by timeframe',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: const Color(0xFF0B102F),
                  ),
                ),
                const SizedBox(height: 6),
                const Divider(height: 1),
                tile(
                  title: 'Past 7 days',
                  icon: Icons.calendar_view_week_rounded,
                  value: RangePreset.week,
                ),
                tile(
                  title: 'Past 30 days',
                  icon: Icons.calendar_month_rounded,
                  value: RangePreset.month,
                ),
                tile(
                  title: 'Past 365 days',
                  icon: Icons.event_rounded,
                  value: RangePreset.year,
                ),
                tile(
                  title: 'Custom range',
                  subtitle: _range == RangePreset.custom ? _rangeLabel() : null,
                  icon: Icons.tune_rounded,
                  value: RangePreset.custom,
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  // ----- filters that respect timeframe (by status time) -----
  List<Chore> _pendingInRangeFor(String childId) => _allChores
      .where((c) => _statusFor(c, childId) == 'verified' && _inSelectedRange(_timeFor(c, childId)))
      .toList()
    ..sort((a, b) {
      final ta = _timeFor(a, childId) ?? a.deadline;
      final tb = _timeFor(b, childId) ?? b.deadline;
      return tb.compareTo(ta);
    });

  List<Chore> _paidInRangeFor(String childId) => _allChores
      .where((c) => _statusFor(c, childId) == 'paid' && _inSelectedRange(_timeFor(c, childId)))
      .toList()
    ..sort((a, b) {
      final ta = _timeFor(a, childId) ?? a.deadline;
      final tb = _timeFor(b, childId) ?? b.deadline;
      return tb.compareTo(ta);
    });

  // ----- payments -----
  Future<void> _paySingle({
    required Chore chore,
    required String childId,
    required String method,
    String? txRef,
  }) async {
    final rewardMajor = int.tryParse(chore.reward) ?? 0;
    await _choreSvc.markChoreAsPaid(
      familyId: _familyId,
      choreId: chore.id,
      childId: childId,
      amountCents: _toCents(rewardMajor),
      currency: 'ILS', // business logic code remains as-is; display uses symbol from FamilyService
      method: method,
      txRef: txRef,
      paidByUid: _parentUid,
      paidAt: DateTime.now(),
    );
  }

  Future<void> _payAllForChild(
    String childId,
    List<Chore> chores,
    String method,
    String? txRef,
  ) async {
    for (final c in chores) {
      if (_statusFor(c, childId) == 'verified') {
        await _paySingle(chore: c, childId: childId, method: method, txRef: txRef);
      }
    }
  }

  void _openPaySheet({
    required String childId,
    required List<Chore> chores,
    Chore? single,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String method = 'cash';
        String? txRef;
        bool paying = false;
        final total =
            single != null ? (int.tryParse(single.reward) ?? 0) : _sumRewards(chores);

        return StatefulBuilder(builder: (ctx, setM) {
          Future<void> submit() async {
            if (paying) return;
            setM(() => paying = true);
            try {
              if (single != null) {
                await _paySingle(
                  chore: single,
                  childId: childId,
                  method: method,
                  txRef: txRef,
                );
              } else {
                await _payAllForChild(childId, chores, method, txRef);
              }
              if (mounted) Navigator.pop(ctx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Paid')),
              );
            } catch (e) {
              setM(() => paying = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Payment failed: $e')),
              );
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      single != null ? 'Pay chore' : 'Pay all verified',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Text(
                      _money(total),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Method', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in const ['cash', 'transfer', 'card'])
                      ChoiceChip(
                        label: Text(m),
                        selected: method == m,
                        onSelected: (_) => setM(() => method = m),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Transaction ref (optional)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => txRef = v.trim().isEmpty ? null : v.trim(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: paying ? null : submit,
                    icon: paying
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('Confirm'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ----- build -----
  @override
  Widget build(BuildContext context) {
    final childIds = _childIds;

    // Ensure selection if children just arrived
    if (_selectedChildId == null && childIds.isNotEmpty) {
      _selectedChildId = childIds.first;
    }
    final selectedId = _selectedChildId;

    // Per-selected-child totals for the tab cards (respecting timeframe)
    final waitingAmount =
        selectedId == null ? 0 : _sumRewards(_pendingInRangeFor(selectedId));
    final paidAmount = selectedId == null ? 0 : _sumRewards(_paidInRangeFor(selectedId));

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 244, 190, 71),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + filter button
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Family Wallet',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Filter timeframe',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _openRangeSheet,
                        customBorder: const CircleBorder(),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.16),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0x22FFFFFF)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.filter_alt_rounded, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _rangeLabel(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),

              // SUMMARY CARDS — act as the tab pickers (per selected child & range)
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      label: 'Awaiting payment (${_rangeLabel()})',
                      value: _money(waitingAmount),
                      icon: Icons.hourglass_bottom_rounded,
                      bg: const Color.fromARGB(255, 255, 159, 132),
                      selected: _tab == ParentWalletTab.pending,
                      onTap: () => setState(() => _tab = ParentWalletTab.pending),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _statCard(
                      label: 'Paid',
                      value: _money(paidAmount),
                      icon: Icons.payments_rounded,
                      bg: const Color(0xFFB6F6A8),
                      selected: _tab == ParentWalletTab.paid,
                      onTap: () => setState(() => _tab = ParentWalletTab.paid),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Horizontal child tab chooser (LIVE)
              if (childIds.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: childIds.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final id = childIds[i];
                      final name = _childNames[id] ?? 'Child';
                      final selected = id == selectedId;
                      return _ChildTabChip(
                        name: name,
                        selected: selected,
                        onTap: () => setState(() => _selectedChildId = id),
                      );
                    },
                  ),
                )
              else
                _emptyState('No children in family'),

              const SizedBox(height: 12),

              // CONTENT for selected child
              if (selectedId != null)
                Expanded(
                  child: _SelectedChildPane(
                    childId: selectedId,
                    childName: _childNames[selectedId] ?? 'Child',
                    tab: _tab,
                    pending: _pendingInRangeFor(selectedId),
                    paidInRange: _paidInRangeFor(selectedId),
                    df: _df,
                    money: _money, // <-- pass symbolized formatter
                    timeFor: (chore) => _timeFor(chore, selectedId),
                    onPayAll: (chores) => _openPaySheet(childId: selectedId, chores: chores),
                    onPaySingle: (chore) => _openPaySheet(
                      childId: selectedId,
                      chores: const [],
                      single: chore,
                    ),
                  ),
                )
              else
                // Edge: if there are children but none selected
                (childIds.isNotEmpty)
                    ? Expanded(child: _emptyState('Select a child'))
                    : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }

  // ----- UI pieces -----
  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color bg,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg.withOpacity(selected ? 1.0 : 0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? Colors.white.withOpacity(0.95) : Colors.transparent,
              width: selected ? 2 : 0,
            ),
            boxShadow: const [
              BoxShadow(
                blurRadius: 6,
                offset: Offset(0, 3),
                color: Color(0x22000000),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: const Color(0xFF0B102F)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0B102F),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B102F),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(String label) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x22000000)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B102F),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// HORIZONTAL CHILD TABS (styled like the "selected child chip")
// ----------------------------------------------------------------------------

class _ChildTabChip extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _ChildTabChip({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.08);
    final border = selected ? const Color(0x33FFFFFF) : const Color(0x11FFFFFF);
    final textColor = Colors.white.withOpacity(selected ? 1.0 : 0.85);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: Colors.white.withOpacity(0.9),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B102F),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                name,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// RIGHT PANE: selected child content
// ----------------------------------------------------------------------------

class _SelectedChildPane extends StatelessWidget {
  final String childId;
  final String childName;
  final ParentWalletTab tab;
  final List<Chore> pending;
  final List<Chore> paidInRange;
  final DateFormat df;
  final String Function(int) money; // currency symbol formatter
  final DateTime? Function(Chore chore) timeFor; // status time for this child
  final void Function(List<Chore> chores) onPayAll;
  final void Function(Chore chore) onPaySingle;

  const _SelectedChildPane({
    required this.childId,
    required this.childName,
    required this.tab,
    required this.pending,
    required this.paidInRange,
    required this.df,
    required this.money,
    required this.timeFor,
    required this.onPayAll,
    required this.onPaySingle,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = tab == ParentWalletTab.pending;
    final items = isPending ? pending : paidInRange;

    if (items.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: _empty(isPending ? 'No chores waiting for payment' : 'No paid chores in range'),
      );
    }

    return Column(
      children: [
        // Actions row (Pay all on pending)
        if (isPending)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => onPayAll(items),
              icon: const Icon(Icons.payments_rounded, size: 18),
              label: const Text('Pay all'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        if (isPending) const SizedBox(height: 8),

        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final c = items[i];
              final t = timeFor(c); // status time for current status (verified/paid)
              return _walletTile(
                title: c.title,
                amount: money(int.tryParse(c.reward) ?? 0),
                statusLabel: isPending ? 'Awaiting payment' : 'Paid',
                statusColor: isPending ? const Color(0xFF1E88E5) : const Color(0xFF2E7D32),
                date: df.format(t ?? c.deadline),
                leadingIcon: isPending ? Icons.verified_rounded : Icons.attach_money_rounded,
                leadingColor: isPending ? const Color(0xFF1E88E5) : const Color(0xFF2E7D32),
                onTap: isPending ? () => onPaySingle(c) : null, // tap whole card to pay
              );
            },
          ),
        ),
      ],
    );
  }

  // Row layout → icon | (title + amount) | (pill + date)
  Widget _walletTile({
    required String title,
    required String amount,
    required String statusLabel,
    required Color statusColor,
    required String date,
    required IconData leadingIcon,
    required Color leadingColor,
    VoidCallback? onTap,
  }) {
    final radius = BorderRadius.circular(16);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCEF),
            borderRadius: radius,
            boxShadow: const [
              BoxShadow(
                blurRadius: 4,
                offset: Offset(0, 2),
                color: Color(0x22000000),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundColor: leadingColor.withOpacity(0.12),
                radius: 20,
                child: Icon(leadingIcon, color: leadingColor),
              ),
              const SizedBox(width: 12),
              // Title + Amount
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B102F),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      amount,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B102F),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Pill + Date
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _statusPill(statusLabel, statusColor),
                  const SizedBox(height: 6),
                  Text(
                    date,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _empty(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x22000000)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0B102F),
        ),
      ),
    );
  }
}
