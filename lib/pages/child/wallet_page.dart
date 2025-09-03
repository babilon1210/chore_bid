import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/chore_model.dart';
import '../../services/user_service.dart';
import 'package:google_fonts/google_fonts.dart';

// 🔤 Localizations
import 'package:chore_bid/l10n/generated/app_localizations.dart';

enum WalletTab { pending, paid }
enum RangePreset { week, month, year, custom }

class ChildWalletPage extends StatefulWidget {
  const ChildWalletPage({super.key});

  @override
  State<ChildWalletPage> createState() => _ChildWalletPageState();
}

class _ChildWalletPageState extends State<ChildWalletPage> {
  final _df = DateFormat.yMMMd();
  WalletTab _tab = WalletTab.pending;

  String get _uid => UserService.currentUser!.uid;

  // --- time filtering ---
  RangePreset _range = RangePreset.week;
  DateTimeRange? _customRange;

  // --- keep recent expired chores locally (index-free listener) ---
  List<Chore> _expiredRecent = [];

  // Merge active (from global model) + recent expired
  List<Chore> get _allChores {
    final map = <String, Chore>{};
    for (final c in UserService.currentUser!.chores) {
      map[c.id] = c;
    }
    for (final c in _expiredRecent) {
      map[c.id] = c;
    }
    return map.values.toList();
  }

  // ----------------- helpers for new progress shape -----------------

  Map<String, dynamic>? _myProgress(Chore c) {
    final raw = c.progress?[_uid];
    return raw is Map<String, dynamic> ? raw : null;
  }

  String? _myStatus(Chore c) => _myProgress(c)?['status'] as String?;

  DateTime? _myTime(Chore c) {
    final t = _myProgress(c)?['time'];
    if (t is Timestamp) return t.toDate();
    if (t is DateTime) return t;
    return null;
  }

  // ------------- amount parsing -------------

  int _rewardILSFor(Chore c) {
    var s = (c.reward).trim();
    // keep digits and separators, remove everything else
    s = s.replaceAll(RegExp(r'[^0-9\.,]'), '');
    if (s.isEmpty) return 0;
    if (s.contains(',') && !s.contains('.')) {
      s = s.replaceAll(',', '.'); // "30,5" -> "30.5"
    } else if (s.contains(',') && s.contains('.')) {
      s = s.replaceAll(',', ''); // "1,234.50" -> "1234.50"
    }
    final v = double.tryParse(s) ?? 0.0;
    return v.round(); // round to whole ILS
  }

  int _sumRewardsILS(List<Chore> chores) =>
      chores.fold(0, (sum, c) => sum + _rewardILSFor(c));

  String _ils(int amount) => '₪$amount';

  // ------------- date-range helpers -------------

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

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
        return DateTimeRange(
          start: _startOfDay(r.start),
          end: _endOfDay(r.end),
        );
    }
  }

  bool _inSelectedRange(DateTime? t) {
    if (t == null) return false;
    final r = _activeRange;
    return (t.isAfter(r.start) || t.isAtSameMomentAs(r.start)) &&
        (t.isBefore(r.end) || t.isAtSameMomentAs(r.end));
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

  // ------------- filtering -------------

  // PENDING in selected range = verified (waiting for payment) by verified time
  List<Chore> get _pendingInRange =>
      _allChores.where((c) => _myStatus(c) == 'verified' && _inSelectedRange(_myTime(c))).toList()
        ..sort((a, b) {
          final ta = _myTime(a) ?? a.deadline;
          final tb = _myTime(b) ?? b.deadline;
          return tb.compareTo(ta);
        });

  // PAID in selected range = paid status by paid time
  List<Chore> get _paidInRange =>
      _allChores.where((c) => _myStatus(c) == 'paid' && _inSelectedRange(_myTime(c))).toList()
        ..sort((a, b) {
          final ta = _myTime(a) ?? a.deadline;
          final tb = _myTime(b) ?? b.deadline;
          return tb.compareTo(ta);
        });

  @override
  void initState() {
    super.initState();

    // SECOND LISTENER: recent expired chores (index-free; filtered client-side)
    final familyId = UserService.currentUser?.familyId;
    if (familyId != null) {
      final cutoff = DateTime.now().subtract(const Duration(days: 60));
      FirebaseFirestore.instance
          .collection('families')
          .doc(familyId)
          .collection('chores')
          .where('status', isEqualTo: 'expired')
          .limit(200)
          .snapshots()
          .listen((snap) {
        final list = snap.docs.map((d) => Chore.fromMap(d.data(), d.id)).toList();
        final recent = list
            .where((c) => c.deadline.isAfter(cutoff))
            .toList()
          ..sort((a, b) => b.deadline.compareTo(a.deadline));

        if (mounted) {
          setState(() {
            _expiredRecent = recent;
          });
        }
      });
    }
  }

  // ----------------- FILTER UI -----------------

  Future<void> _showRangeSheet() async {
    await showModalBottomSheet(
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
          VoidCallback? onTap,
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
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0B102F),
              ),
            ),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: selected
                ? const Icon(Icons.check_circle, color: Colors.indigo)
                : null,
            onTap: () async {
              if (value == RangePreset.custom) {
                Navigator.pop(ctx); // close sheet before date picker
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

  Widget _headerRow(AppLocalizations l) {
    return Row(
      children: [
        // Title
        Expanded(
          child: Text(
            'My Wallet',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        // Small filter icon button
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _showRangeSheet,
            customBorder: const CircleBorder(),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 6,
                    offset: Offset(0, 2),
                    color: Color(0x22000000),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(10),
              child: const Icon(
                Icons.filter_alt_rounded,
                color: Color(0xFF0B102F),
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _rangeChip() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x330B102F)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFF0B102F)),
          const SizedBox(width: 6),
          Text(
            _rangeLabel(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0B102F),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------- UI -----------------

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final waitingAmount = _sumRewardsILS(_pendingInRange);
    final paidAmount = _sumRewardsILS(_paidInRange);

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 244, 190, 71),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerRow(l),
            _rangeChip(),
            const SizedBox(height: 12),

            // SUMMARY CARDS — act as the tab pickers (filtered by selected range)
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    label: l.waitingPayment,
                    value: _ils(waitingAmount),
                    icon: Icons.hourglass_bottom_rounded,
                    bg: const Color.fromARGB(255, 255, 159, 132),
                    selected: _tab == WalletTab.pending,
                    onTap: () => setState(() => _tab = WalletTab.pending),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    label: 'Paid',
                    value: _ils(paidAmount),
                    icon: Icons.payments_rounded,
                    bg: const Color(0xFFB6F6A8),
                    selected: _tab == WalletTab.paid,
                    onTap: () => setState(() => _tab = WalletTab.paid),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Lists
            Expanded(
              child: _tab == WalletTab.pending
                  ? _buildList(
                      items: _pendingInRange,
                      emptyLabel:
                          'No chores waiting for payment in ${_rangeLabel().toLowerCase()}',
                      tileBuilder: (c) {
                        final t = _myTime(c) ?? c.deadline;
                        return _walletTile(
                          title: c.title,
                          amount: _ils(_rewardILSFor(c)),
                          statusLabel: 'Awaiting payment',
                          statusColor: const Color(0xFF1E88E5),
                          date: _df.format(t),
                          leadingIcon: Icons.verified_rounded,
                          leadingColor: const Color(0xFF1E88E5),
                        );
                      },
                    )
                  : _buildList(
                      items: _paidInRange,
                      emptyLabel:
                          'No paid chores in ${_rangeLabel().toLowerCase()}',
                      tileBuilder: (c) {
                        final t = _myTime(c) ?? c.deadline; // paid time expected
                        return _walletTile(
                          title: c.title,
                          amount: _ils(_rewardILSFor(c)),
                          statusLabel: l.paid,
                          statusColor: const Color(0xFF2E7D32),
                          date: _df.format(t),
                          leadingIcon: Icons.attach_money_rounded,
                          leadingColor: const Color(0xFF2E7D32),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- UI pieces ----------------

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

  Widget _buildList({
    required List<Chore> items,
    required String emptyLabel,
    required Widget Function(Chore) tileBuilder,
  }) {
    if (items.isEmpty) {
      return _emptyState(emptyLabel);
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => tileBuilder(items[i]),
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

  // NEW: row layout → icon | (title + amount) | (pill + date)
  Widget _walletTile({
    required String title,
    required String amount,
    required String statusLabel,
    required Color statusColor,
    required String date,
    required IconData leadingIcon,
    required Color leadingColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCEF),
        borderRadius: BorderRadius.circular(16),
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
          // Title + Amount (left/middle)
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
          // Pill + Date (right)
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
}
