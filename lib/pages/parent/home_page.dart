import 'package:chore_bid/pages/parent/chore_info_page.dart';
import 'package:chore_bid/pages/parent/parent_settings_page.dart';
import 'package:chore_bid/services/chore_service.dart';
import 'package:chore_bid/services/user_service.dart';
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

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  List<Chore> get activeChores =>
      UserService.currentUser!.chores.where((c) => c.status != 'expired' && (((c.progress == null || (c.progress!.isEmpty || c.progress!.containsValue('claimed')))))).toList();

  List<Chore> get completedChores =>
      UserService.currentUser!.chores.where((c) => c.progress != null && c.progress!.containsValue('complete')).toList();

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
                            ...activeChores.map(
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
                                      builder:
                                          (_) => ChoreInfoPage(chore: chore),
                                    ),
                                  );
                                  setState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
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
                              'Completed Chores',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Color.fromARGB(255, 14, 20, 61),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...completedChores.map(
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
                                      builder:
                                          (_) => ChoreInfoPage(chore: chore),
                                    ),
                                  );
                                  setState(() {});
                                },
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
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => CreateChoreBidPage(user: UserService.currentUser!),
            ),
          );
          setState(() {});
        },
        tooltip: 'Create New Chore Bid',
        child: const Icon(Icons.add),
      ),
    );
  }
}
