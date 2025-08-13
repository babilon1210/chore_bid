import 'package:cloud_firestore/cloud_firestore.dart'; // <-- add
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/chore_model.dart';
import '../../services/user_service.dart';
import 'package:google_fonts/google_fonts.dart';

enum WalletTab { pending, paid }

class ChildWalletPage extends StatefulWidget {
  const ChildWalletPage({super.key});

  @override
  State<ChildWalletPage> createState() => _ChildWalletPageState();
}

class _ChildWalletPageState extends State<ChildWalletPage> {
  final _df = DateFormat.yMMMd();
  WalletTab _tab = WalletTab.pending;

  String get _uid => UserService.currentUser!.uid;

  // --- NEW: keep recent expired chores locally (index-free listener) ---
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

  // PENDING = verified (waiting for payment)
  List<Chore> get _pending =>
      _allChores.where((c) => c.progress?[_uid] == 'verified').toList();

  // PAID (this month) — still using deadline as proxy until we switch to payments.paidAt
  List<Chore> get _paidThisMonth => _allChores.where((c) {
        if (c.progress?[_uid] != 'paid') return false;
        final d = c.deadline;
        final now = DateTime.now();
        return d.month == now.month && d.year == now.year;
      }).toList();

  // Completed (verified) this month
  List<Chore> get _completedThisMonth => _allChores.where((c) {
        if (c.progress?[_uid] != 'verified') return false;
        final d = c.deadline;
        final now = DateTime.now();
        return d.month == now.month && d.year == now.year;
      }).toList();

  int _sumRewards(List<Chore> chores) =>
      chores.fold(0, (sum, c) => sum + (int.tryParse(c.reward) ?? 0));

  String _ils(int amount) => '₪$amount';

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
          .where('status', isEqualTo: 'expired') // no orderBy/inequality -> no index needed
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

  @override
  Widget build(BuildContext context) {
    final waitingAmount = _sumRewards(_pending);
    final paidAmount = _sumRewards(_paidThisMonth);

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 244, 190, 71),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              'My Wallet',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),

            // Summary cards
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    label: 'Waiting',
                    value: _ils(waitingAmount),
                    icon: Icons.hourglass_bottom_rounded,
                    bg: const Color.fromARGB(255, 255, 159, 132),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    label: 'Paid This Month',
                    value: _ils(paidAmount),
                    icon: Icons.payments_rounded,
                    bg: const Color(0xFFB6F6A8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // This month summary line
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('${_completedThisMonth.length} pending this month'),
                _chip('${_paidThisMonth.length} paid this month'),
              ],
            ),
            const SizedBox(height: 16),

            // Segmented control
            Container(
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  _segButton(
                    text: 'Pending',
                    selected: _tab == WalletTab.pending,
                    onTap: () => setState(() => _tab = WalletTab.pending),
                  ),
                  _segButton(
                    text: 'Paid',
                    selected: _tab == WalletTab.paid,
                    onTap: () => setState(() => _tab = WalletTab.paid),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // List
            Expanded(
              child: _tab == WalletTab.pending
                  ? _buildList(
                      items: _pending,
                      emptyLabel: 'No chores waiting for payment',
                      tileBuilder: (c) => _walletTile(
                        title: c.title,
                        amount: _ils(int.tryParse(c.reward) ?? 0),
                        statusLabel: 'Verified • awaiting payment',
                        statusColor: const Color(0xFF1E88E5),
                        date: _df.format(c.deadline),
                        leadingIcon: Icons.verified_rounded,
                        leadingColor: const Color(0xFF1E88E5),
                      ),
                    )
                  : _buildList(
                      items: _paidThisMonth,
                      emptyLabel: 'No paid chores yet this month',
                      tileBuilder: (c) => _walletTile(
                        title: c.title,
                        amount: _ils(int.tryParse(c.reward) ?? 0),
                        statusLabel: 'Paid',
                        statusColor: const Color(0xFF2E7D32),
                        date: _df.format(c.deadline), // swap to paidAt when using payments
                        leadingIcon: Icons.attach_money_rounded,
                        leadingColor: const Color(0xFF2E7D32),
                      ),
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
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
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
              color: Colors.white.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF0B102F)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0B102F))),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B102F))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x330B102F)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0B102F),
        ),
      ),
    );
  }

  Widget _segButton({
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? const Color(0xFF0B102F) : Colors.white,
            ),
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
              fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0B102F)),
        ),
      ),
    );
  }

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
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: leadingColor.withOpacity(0.12),
          radius: 20,
          child: Icon(leadingIcon, color: leadingColor),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0B102F),
          ),
        ),
        subtitle: Row(
          children: [
            Text(
              amount,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0B102F),
              ),
            ),
            const SizedBox(width: 8),
            _statusPill(statusLabel, statusColor),
          ],
        ),
        trailing: Text(
          date,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
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
}
