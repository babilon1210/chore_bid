import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:chore_bid/services/user_service.dart';
import 'package:chore_bid/services/chore_service.dart';

import '../../models/chore_model.dart';
import '../../widgets/chore_card.dart';
import 'wallet_page.dart';

// Confetti
import 'package:confetti/confetti.dart';

// TTS
import 'package:flutter_tts/flutter_tts.dart';

// 🔤 Localizations (your generated file)
import 'package:chore_bid/l10n/generated/app_localizations.dart';

enum ChildTab { active, history }

class ChildHomePage extends StatefulWidget {
  const ChildHomePage({super.key});

  @override
  State<ChildHomePage> createState() => _ChildHomePageState();
}

class _ChildHomePageState extends State<ChildHomePage> {
  int _selectedIndex = 0; // bottom nav
  ChildTab _tab = ChildTab.active; // Active | History

  final String childId = UserService.currentUser!.uid;

  // recent expired chores (client-side filtered/sorted)
  List<Chore> _expiredRecent = [];

  // ---------- Confetti ----------
  late final ConfettiController _confettiCtrl;
  bool _confettiOn = false;

  // ---------- TTS ----------
  late final FlutterTts _tts;
  bool _ttsReady = false;

  @override
  void initState() {
    super.initState();

    // Confetti controller
    _confettiCtrl = ConfettiController(duration: const Duration(milliseconds: 900));

    // TTS init
    _initTts();

    final familyId = UserService.currentUser?.familyId;
    if (familyId != null) {
      // active/non-expired chores
      ChoreService().listenToChores(familyId).listen((_) {
        if (mounted) setState(() {});
      });

      // expired listener
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

  Future<void> _initTts() async {
    _tts = FlutterTts();
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(0.4);
    await _tts.setVolume(100.0);

    try {
      final voices = await _tts.getVoices;
      if (voices is List) {
        final en = voices.where((v) {
          final loc = (v['locale'] ?? v['language'] ?? '').toString().toLowerCase();
          return loc.startsWith('en') && (loc.contains('us') || loc.contains('gb') || loc.contains('en'));
        }).toList();
        if (en.isNotEmpty) {
          final chosen = en.first;
          await _tts.setVoice({
            'name': chosen['name'],
            'locale': (chosen['locale'] ?? chosen['language'] ?? 'en-US').toString(),
          });
        }
      }
    } catch (_) {}
    _ttsReady = true;
  }

  Future<void> _sayAwesome() async {
    if (!_ttsReady) await _initTts();
    await _tts.speak('Awesome!');
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    _tts.stop();
    super.dispose();
  }

  // Fire a quick, centered confetti burst
  void _burstConfetti() {
    if (!mounted) return;
    setState(() => _confettiOn = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confettiCtrl.play();
    });

    Future.delayed(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() => _confettiOn = false);
    });
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
    final l = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isMineClaimed ? l.choreOptions : l.acceptChoreQ),
        content: Text(
          isMineClaimed
              ? 'What would you like to do with this chore?' // (no key yet) keep literal
              : l.acceptChoreQ,
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
              child: Text(l.done),
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
              child: Text(l.unclaim),
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
                // 🎉 Visual + Audio celebration on successful claim
                if (mounted) {
                  _burstConfetti();
                  _sayAwesome();
                }
              },
              child: Text(l.yes),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.no),
            ),
          ],
        ],
      ),
    );
  }

  // ------------- UI -------------

  @override
  Widget build(BuildContext context) {
    // NOTE: Keep "Chorebid" in English by request
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
      // Confetti overlay above content
      body: Stack(
        children: [
          _buildBody(),
          if (_confettiOn)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.center,
                  child: ConfettiWidget(
                    confettiController: _confettiCtrl,
                    blastDirectionality: BlastDirectionality.explosive,
                    emissionFrequency: 0,
                    numberOfParticles: 60,
                    maxBlastForce: 25,
                    minBlastForce: 10,
                    gravity: 0.9,
                    colors: const [
                      Color(0xFFFFC107),
                      Color(0xFF8BC34A),
                      Color(0xFF03A9F4),
                      Color(0xFFE91E63),
                      Color(0xFF9C27B0),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
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
              _topTabs(),
              const SizedBox(height: 12),
              Expanded(
                child: _tab == ChildTab.active
                    ? _buildActiveContent()
                    : _buildHistoryContent(),
              ),
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

  // Top two-tab control
  Widget _topTabs() {
    final l = AppLocalizations.of(context);

    Widget btn(String label, ChildTab t) {
      final sel = _tab == t;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = t),
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
          btn(l.tabActive, ChildTab.active),
          btn(l.tabHistory, ChildTab.history),
        ],
      ),
    );
  }

  // ACTIVE tab: show ONLY what's available; if none at all, show single notice.
  Widget _buildActiveContent() {
    final l = AppLocalizations.of(context);

    final hasAvailable = _available.isNotEmpty;
    final hasMyWork = _claimed.isNotEmpty ||
        _completedWaiting.isNotEmpty ||
        _verifiedWaiting.isNotEmpty;

    // Nothing to show at all
    if (!hasAvailable && !hasMyWork) {
      return ListView(children: [_emptyState(l.noChoresNow)]);
    }

    final widgets = <Widget>[];

    if (hasAvailable) {
      widgets.add(
        _listCard(
          title: l.availableChores,
          color: const Color.fromARGB(255, 251, 213, 184),
          items: _available,
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
        ),
      );
    }

    if (hasAvailable && hasMyWork) widgets.add(const SizedBox(height: 16));

    if (hasMyWork) {
      final sections = <Widget>[];
      sections.addAll(_sectionIfAny(AppLocalizations.of(context).claimed, _claimed));
      sections.addAll(_sectionIfAny(AppLocalizations.of(context).waitingReview, _completedWaiting));
      sections.addAll(_sectionIfAny(AppLocalizations.of(context).waitingPayment, _verifiedWaiting));

      widgets.add(
        Card(
          color: const Color.fromARGB(255, 243, 231, 172),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sections,
            ),
          ),
        ),
      );
    }

    return ListView(children: widgets);
  }

  // HISTORY tab: (Paid, Expired — Missed) and hides empty sections
  Widget _buildHistoryContent() {
    final l = AppLocalizations.of(context);

    final children = <Widget>[];
    children.addAll(_sectionIfAny(l.paid, _paid));
    children.addAll(_sectionIfAny(l.expiredMissed, _expiredMissed));

    if (children.isEmpty) {
      return ListView(children: [_emptyState(l.noHistory)]);
    }
    return ListView(children: children);
  }

  // Build a subsection only if it has items
  List<Widget> _sectionIfAny(String title, List<Chore> items) {
    final l = AppLocalizations.of(context);
    if (items.isEmpty) return const [];
    return [
      _subHeader('$title • ${l.countLabel(items.length)}'),
      const SizedBox(height: 8),
      ...items.map((c) => _tile(c)),
      const SizedBox(height: 16),
    ];
  }

  // Reusable List container card; call this ONLY with non-empty items.
  Widget _listCard({
    required String title,
    required Color color,
    required List<Chore> items,
    required Widget Function(Chore) tileBuilder,
  }) {
    return Card(
      color: color,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
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
