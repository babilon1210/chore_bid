import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:chore_bid/services/user_service.dart';
import 'package:chore_bid/services/chore_service.dart';

import '../../models/chore_model.dart';
import '../../widgets/chore_card.dart';
import 'wallet_page.dart';

enum ChildSection { available, myWork, history }

class ChildHomePage extends StatefulWidget {
  const ChildHomePage({super.key});

  @override
  State<ChildHomePage> createState() => _ChildHomePageState();
}

class _ChildHomePageState extends State<ChildHomePage> {
  int _selectedIndex = 0; // bottom nav
  ChildSection _section = ChildSection.available; // segmented control

  final String childId = UserService.currentUser!.uid;

  // Second stream (Option B): recent expired chores (client-side filtered/sorted)
  List<Chore> _expiredRecent = [];

  @override
  void initState() {
    super.initState();

    final familyId = UserService.currentUser?.familyId;
    if (familyId != null) {
      // Existing listener (active/non-expired chores)
      ChoreService().listenToChores(familyId).listen((_) {
        if (mounted) setState(() {});
      });

      // Index-free expired listener (limit + client-side filter/sort)
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

  // ------------- Core helpers -------------

  bool _isExpired(Chore c) => c.status == 'expired';
  String? _my(Chore c) => c.progress?[childId];
  bool _assignedToMe(Chore c) => c.assignedTo.contains(childId);

  bool _someoneElseAdvanced(Chore c) {
    final prog = c.progress;
    if (prog == null) return false;
    for (final e in prog.entries) {
      if (e.key == childId) continue;
      final s = e.value;
      if (s != null && s != 'assigned') return true;
    }
    return false;
  }

  bool _isAvailable(Chore c) {
    if (_isExpired(c)) return false;
    if (!_assignedToMe(c)) return false;

    final s = _my(c);
    final mineOpen = (s == null || s == 'assigned');

    if (!mineOpen) return false;

    // Exclusive: only available if nobody else advanced past 'assigned'
    if (c.isExclusive && _someoneElseAdvanced(c)) return false;

    return true;
  }

  bool _isMyClaimed(Chore c) => !_isExpired(c) && _my(c) == 'claimed';
  bool _isMyCompleted(Chore c) => _my(c) == 'complete'; // expired or not
  bool _isMyVerified(Chore c) => _my(c) == 'verified'; // expired or not
  bool _isMyPaid(Chore c) => _my(c) == 'paid';

  bool _isMyExpiredMissed(Chore c) {
    if (!_isExpired(c)) return false;
    if (!_assignedToMe(c)) return false;
    final s = _my(c);
    return (s == null || s == 'assigned' || s == 'claimed');
  }

  // Combine active + expired (dedup by id to be safe)
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

  // Buckets
  List<Chore> get _available =>
      _allChores.where(_isAvailable).toList()
        ..sort((a, b) => a.deadline.compareTo(b.deadline));

  List<Chore> get _claimed =>
      _allChores.where(_isMyClaimed).toList()
        ..sort((a, b) => a.deadline.compareTo(b.deadline));

  List<Chore> get _completedWaiting =>
      _allChores.where(_isMyCompleted).toList()
        ..sort((a, b) => b.deadline.compareTo(a.deadline));

  List<Chore> get _verifiedWaiting =>
      _allChores.where(_isMyVerified).toList()
        ..sort((a, b) => b.deadline.compareTo(a.deadline));

  List<Chore> get _paid =>
      _allChores.where(_isMyPaid).toList()
        ..sort((a, b) => b.deadline.compareTo(a.deadline));

  List<Chore> get _expiredMissed =>
      _allChores.where(_isMyExpiredMissed).toList()
        ..sort((a, b) => b.deadline.compareTo(a.deadline));

  // ------------- Actions -------------

  void _handleChoreTap(Chore chore) {
    final isMineClaimed = _isMyClaimed(chore);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isMineClaimed ? 'Chore Options' : 'Accept Chore?'),
        content: Text(
          isMineClaimed
              ? 'What would you like to do with this chore?'
              : 'Do you want to accept this chore?',
        ),
        actions: [
          if (isMineClaimed) ...[
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await ChoreService().markChoreAsComplete(
                  familyId: UserService.currentUser!.familyId!,
                  choreId: chore.id,
                  childId: childId,
                );
              },
              child: const Text('Done'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await ChoreService().unclaimChore(
                  familyId: UserService.currentUser!.familyId!,
                  choreId: chore.id,
                  childId: childId,
                );
              },
              child: const Text('Unclaim'),
            ),
          ] else ...[
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await ChoreService().claimChore(
                  familyId: UserService.currentUser!.familyId!,
                  choreId: chore.id,
                  childId: childId,
                );
              },
              child: const Text('Yes'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('No'),
            ),
          ],
        ],
      ),
    );
  }

  // ------------- UI -------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 244, 190, 71),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          'Chorebid',
          style: GoogleFonts.pacifico(
            fontSize: 36,
            color: const Color.fromARGB(255, 11, 16, 47),
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color.fromARGB(255, 255, 233, 164),
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.black45,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Chores'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _segmentControl(),
              const SizedBox(height: 12),
              Expanded(child: _buildSegmentContent()),
            ],
          ),
        );
      case 1:
        return const ChildWalletPage();
      case 2:
        return const Center(child: Text('Profile (Coming soon)'));
      default:
        return const SizedBox();
    }
  }

  // Segmented control
  Widget _segmentControl() {
    Widget btn(String label, ChildSection s) {
      final sel = _section == s;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _section = s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? Colors.white : const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: sel ? const Color(0xFF0B102F) : Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          btn('Available', ChildSection.available),
          btn('My Work', ChildSection.myWork),
          btn('History', ChildSection.history),
        ],
      ),
    );
  }

  Widget _buildSegmentContent() {
    switch (_section) {
      case ChildSection.available:
        return _listCard(
          title: 'Available Chores',
          color: const Color.fromARGB(255, 251, 213, 184),
          items: _available,
          emptyText: 'No chores available right now.',
          tileBuilder: (c) => ChoreCard(
            title: c.title,
            reward: c.reward,
            status: c.status,
            isExclusive: c.isExclusive,
            assignedTo: c.assignedTo,
            progress: c.progress,
            deadline: c.deadline,
            onTap: () => _handleChoreTap(c),
          ),
        );

      case ChildSection.myWork:
        // Only render a section if it has at least one item
        final children = <Widget>[];
        children.addAll(_sectionIfAny('Claimed', _claimed));
        children.addAll(_sectionIfAny('Waiting Review', _completedWaiting));
        children.addAll(_sectionIfAny('Waiting Payment', _verifiedWaiting));

        if (children.isEmpty) {
          return ListView(children: [_emptyState('Nothing to do here yet.')]);
        }
        return ListView(children: children);

      case ChildSection.history:
        final children = <Widget>[];
        children.addAll(_sectionIfAny('Paid', _paid));
        children.addAll(_sectionIfAny('Expired — Missed', _expiredMissed));

        if (children.isEmpty) {
          return ListView(children: [_emptyState('No history yet.')]);
        }
        return ListView(children: children);
    }
  }

  // Build a subsection only if it has items
  List<Widget> _sectionIfAny(String title, List<Chore> items) {
    if (items.isEmpty) return const [];
    return [
      _subHeader('$title • ${items.length}'),
      _spacerV(8),
      ...items.map((c) => _tile(c)),
      _spacerV(16),
    ];
  }

  // Reusable List container card for the Available section
  Widget _listCard({
    required String title,
    required Color color,
    required List<Chore> items,
    required String emptyText,
    required Widget Function(Chore) tileBuilder,
  }) {
    return Card(
      color: color,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: items.isEmpty
            ? _emptyState(emptyText)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 14, 20, 61),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...items.map(tileBuilder),
                ],
              ),
      ),
    );
  }

  // Shared chore tile using your ChoreCard + tap handler where relevant
  Widget _tile(Chore c) => Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: ChoreCard(
          title: c.title,
          reward: c.reward,
          status: c.status,
          isExclusive: c.isExclusive,
          assignedTo: c.assignedTo,
          progress: c.progress,
          deadline: c.deadline,
          onTap: () {
            // Only claimed chores (and available chores, where relevant) expose the action sheet
            if (_isMyClaimed(c) || _isAvailable(c)) {
              _handleChoreTap(c);
            }
          },
        ),
      );

  // Small helpers
  Widget _subHeader(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color.fromARGB(255, 14, 20, 61),
        ),
      );

  Widget _spacerV(double h) => SizedBox(height: h);

  Widget _emptyState(String label) => Center(
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
              fontWeight: FontWeight.w700,
              color: Color(0xFF0B102F),
            ),
          ),
        ),
      );
}
