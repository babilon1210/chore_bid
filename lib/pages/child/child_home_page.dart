import 'package:flutter/material.dart';
import 'package:chore_bid/services/user_service.dart';
import 'package:chore_bid/services/chore_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/chore_model.dart';
import '../../widgets/chore_card.dart';
import 'wallet_page.dart';

class ChildHomePage extends StatefulWidget {
  const ChildHomePage({super.key});

  @override
  State<ChildHomePage> createState() => _ChildHomePageState();
}

class _ChildHomePageState extends State<ChildHomePage> {
  int _selectedIndex = 0;
  final String childId = UserService.currentUser!.uid;

  List<Chore> get availableChores =>
      UserService.currentUser!.chores.where((chore) {
        final isAssignedToMe = chore.assignedTo.contains(childId);

        if (chore.isExclusive) {
          return isAssignedToMe &&
              (chore.progress == null || chore.progress!.isEmpty);
        } else {
          return isAssignedToMe &&
              (chore.progress == null || chore.progress![childId] == null);
        }
      }).toList();

  List<Chore> get myChores =>
      UserService.currentUser!.chores
          .where(
            (chore) =>
                ((chore.progress != null &&
                    chore.progress![childId] != null &&  chore.progress![childId] != 'approved')),
          )
          .toList();

  void _handleChoreTap(Chore chore) {
    final isMine =
        ((chore.progress != null &&
            chore.progress![childId] != null && chore.progress![childId] != 'claimed'));

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(isMine ? 'Chore Options' : 'Accept Chore?'),
            content: Text(
              isMine
                  ? 'What would you like to do with this chore?'
                  : 'Do you want to accept this chore?',
            ),
            actions: [
              if (isMine) ...[
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await ChoreService().markChoreAsComplete(
                      familyId: UserService.currentUser!.familyId!,
                      choreId: chore.id,
                      childId: UserService.currentUser!.uid,
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
                      childId: UserService.currentUser!.uid,
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
                      childId: UserService.currentUser!.uid,
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

  @override
  void initState() {
    super.initState();
    final familyId = UserService.currentUser?.familyId;
    if (familyId != null) {
      ChoreService().listenToChores(familyId).listen((_) {
        setState(() {});
      });
    }
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
                    // --- Your Chores Card ---
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
                              'Your Chores',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Color.fromARGB(255, 14, 20, 61),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...myChores.map(
                              (chore) => ChoreCard(
                                title: chore.title,
                                reward: chore.reward,
                                status: chore.status,
                                isExclusive: chore.isExclusive,
                                assignedTo: chore.assignedTo,
                                progress: chore.progress,
                                deadline: chore.deadline,
                                onTap: () => _handleChoreTap(chore),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // --- Available Chores Card ---
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
                            const Text(
                              'Available Chores',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Color.fromARGB(255, 14, 20, 61),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...availableChores.map(
                              (chore) => ChoreCard(
                                title: chore.title,
                                reward: chore.reward,
                                status: chore.status,
                                isExclusive: chore.isExclusive,
                                assignedTo: chore.assignedTo,
                                progress: chore.progress,
                                deadline: chore.deadline,
                                onTap: () => _handleChoreTap(chore),
                              ),
                            ),
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
        return const ChildWalletPage();
      case 2:
        return const Center(child: Text('Profile (Coming soon)'));
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
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Wallet',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
