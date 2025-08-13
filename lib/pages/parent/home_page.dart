import 'package:chore_bid/pages/parent/chore_info_page.dart';
import 'package:chore_bid/pages/parent/parent_settings_page.dart';
import 'package:chore_bid/services/chore_service.dart';
import 'package:chore_bid/services/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <-- second query for expired
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/chore_card.dart';
import '../../models/chore_model.dart';
import 'create_chore_bid_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum CompletedTimeFilter { all, today, week, month, custom }

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  // Recent expired chores fetched via a second stream (Option B)
  List<Chore> _expiredRecent = [];

  // Completed section filters
  CompletedTimeFilter _filter = CompletedTimeFilter.all;
  DateTimeRange? _customRange;

  bool _isDoneStatus(String? s) =>
      s == 'complete' || s == 'verified' || s == 'paid';

  bool _hasAnyDone(Chore c) =>
      (c.progress ?? const {}).values.any(_isDoneStatus);

  /// Exclusive: completed if **any** child is done.
  /// Non-exclusive: completed if **all assigned** children are done.
  bool _isChoreCompleted(Chore c) {
    if (c.status == 'expired') return false; // Non-expired rule only here
    final Map<String, String> prog = c.progress ?? const {};
    if (c.isExclusive) {
      return prog.values.any(_isDoneStatus);
    } else {
      if (c.assignedTo.isEmpty) return false;
      for (final childId in c.assignedTo) {
        final s = prog[childId];
        if (!_isDoneStatus(s)) return false;
      }
      return true;
    }
  }

  // ---------- Derived lists ----------

  List<Chore> get _nonExpiredActive =>
      UserService.currentUser!.chores
          .where((c) => c.status != 'expired' && !_isChoreCompleted(c))
          .toList();

  List<Chore> get _nonExpiredCompleted =>
      UserService.currentUser!.chores.where(_isChoreCompleted).toList();

  // Expired with ANY completion (to show in Completed)
  List<Chore> get _expiredCompleted =>
      _expiredRecent.where(_hasAnyDone).toList();

  // Expired with NO completion (hidden by default; collapsible)
  List<Chore> get _expiredIncomplete =>
      _expiredRecent.where((c) => !_hasAnyDone(c)).toList();

  // Completed list that the UI shows (after time filter)
  List<Chore> get _completedForUi {
    final combined = <Chore>[
      ..._nonExpiredCompleted,
      ..._expiredCompleted,
    ];
    return combined.where(_passesTimeFilter).toList()
      ..sort((a, b) => b.deadline.compareTo(a.deadline));
  }

  // ---------- Time filtering ----------

  bool _passesTimeFilter(Chore c) {
    final d = c.deadline;
    final now = DateTime.now();

    DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
    DateTime _startOfWeek(DateTime dt) {
      // Monday as first day of week
      final mondayDelta = dt.weekday - DateTime.monday; // 0..6
      final start = DateTime(dt.year, dt.month, dt.day).subtract(Duration(days: mondayDelta));
      return start;
    }

    switch (_filter) {
      case CompletedTimeFilter.all:
        return true;
      case CompletedTimeFilter.today:
        return _startOfDay(d) == _startOfDay(now);
      case CompletedTimeFilter.week:
        final start = _startOfWeek(now);
        return d.isAfter(start.subtract(const Duration(seconds: 1))) && d.isBefore(now.add(const Duration(days: 1)));
      case CompletedTimeFilter.month:
        return d.year == now.year && d.month == now.month;
      case CompletedTimeFilter.custom:
        if (_customRange == null) return true;
        final s = _customRange!.start;
        final e = _customRange!.end;
        return (d.isAfter(s.subtract(const Duration(seconds: 1))) &&
            d.isBefore(e.add(const Duration(days: 1))));
    }
  }

  // ---------- Init & streams ----------

  @override
  void initState() {
    super.initState();

    final familyId = UserService.currentUser?.familyId;
    if (familyId != null) {
      // Active/non-expired stream (existing)
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
        final list = snap.docs
            .map((d) => Chore.fromMap(d.data(), d.id))
            .toList();
        if (mounted) {
          setState(() {
            _expiredRecent = list;
          });
        }
      });
    }
  }

  // ---------- UI ----------

  Widget _filterChips() {
    Widget chip(String label, CompletedTimeFilter value) {
      final selected = _filter == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('All', CompletedTimeFilter.all),
        chip('Today', CompletedTimeFilter.today),
        chip('This Week', CompletedTimeFilter.week),
        chip('This Month', CompletedTimeFilter.month),
        ChoiceChip(
          label: const Text('Custom…'),
          selected: _filter == CompletedTimeFilter.custom,
          onSelected: (_) async {
            final now = DateTime.now();
            final initialRange = _customRange ??
                DateTimeRange(
                  start: DateTime(now.year, now.month, 1),
                  end: now,
                );
            final picked = await showDateRangePicker(
              context: context,
              firstDate: now.subtract(const Duration(days: 365)),
              lastDate: now.add(const Duration(days: 365)),
              initialDateRange: initialRange,
            );
            if (!mounted) return;
            if (picked != null) {
              setState(() {
                _customRange = picked;
                _filter = CompletedTimeFilter.custom;
              });
            } else {
              // If user cancels, keep previous filter
              setState(() {});
            }
          },
        ),
      ],
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    // --------- Active ---------
                    Card(
                      color: const Color.fromARGB(255, 243, 231, 172),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Active Chores',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Color.fromARGB(255, 14, 20, 61),
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_nonExpiredActive.isEmpty)
                              const Text('No active chores right now.'),
                            ..._nonExpiredActive.map(
                              (chore) => ChoreCard(
                                title: chore.title,
                                reward: chore.reward,
                                status: chore.status,
                                isExclusive: chore.isExclusive,
                                assignedTo: chore.assignedTo,
                                progress: chore.progress,
                                deadline: chore.deadline,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ChoreInfoPage(chore: chore),
                                    ),
                                  );
                                  if (mounted) setState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // --------- Completed ---------
                    Card(
                      color: const Color.fromARGB(255, 251, 213, 184),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Completed Chores',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: Color.fromARGB(255, 14, 20, 61),
                                    ),
                                  ),
                                ),
                                // Filter chips
                              ],
                            ),
                            const SizedBox(height: 8),
                            _filterChips(),
                            const SizedBox(height: 10),

                            if (_completedForUi.isEmpty)
                              const Text('No completed chores for this filter.'),

                            ..._completedForUi.map(
                              (chore) => ChoreCard(
                                title: chore.title,
                                reward: chore.reward,
                                status: chore.status, // may be 'expired'
                                isExclusive: chore.isExclusive,
                                assignedTo: chore.assignedTo,
                                progress: chore.progress,
                                deadline: chore.deadline,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ChoreInfoPage(chore: chore),
                                    ),
                                  );
                                  if (mounted) setState(() {});
                                },
                              ),
                            ),

                            // Collapsible: Expired with NO completion
                            if (_expiredIncomplete.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Theme(
                                data: Theme.of(context).copyWith(
                                  dividerColor: Colors.transparent,
                                ),
                                child: ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: Text(
                                    'Expired (no completion) · ${_expiredIncomplete.length}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Color.fromARGB(255, 14, 20, 61),
                                    ),
                                  ),
                                  childrenPadding: EdgeInsets.zero,
                                  children: _expiredIncomplete.map((chore) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: ChoreCard(
                                        title: chore.title,
                                        reward: chore.reward,
                                        status: chore.status, // 'expired'
                                        isExclusive: chore.isExclusive,
                                        assignedTo: chore.assignedTo,
                                        progress: chore.progress,
                                        deadline: chore.deadline,
                                        onTap: () async {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ChoreInfoPage(chore: chore),
                                            ),
                                          );
                                          if (mounted) setState(() {});
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 1:
        return const ParentSettingsPage();
      default:
        return const SizedBox();
    }
  }

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
            fontSize: 30,
            color: const Color.fromARGB(255, 11, 16, 47),
          ),
          textAlign: TextAlign.center,
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
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateChoreBidPage(user: UserService.currentUser!),
            ),
          );
          if (mounted) setState(() {});
        },
        tooltip: 'Create New Chore Bid',
        child: const Icon(Icons.add),
      ),
    );
  }
}
