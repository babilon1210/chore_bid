import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/chore_model.dart';
import '../../services/user_service.dart';
import 'package:google_fonts/google_fonts.dart';

class ChildWalletPage extends StatelessWidget {
  const ChildWalletPage({super.key});

  List<Chore> get unpaidChores =>
      UserService.currentUser!.chores
          .where((c) => c.progress != null && c.progress![UserService.currentUser!.uid] == 'approved' && c.isPaid != true)
          .toList();

  List<Chore> get completedThisMonth =>
      UserService.currentUser!.chores
          .where(
            (c) =>
                c.progress != null && c.progress![UserService.currentUser!.uid] == 'approved' &&
                c.deadline.month == DateTime.now().month &&
                c.deadline.year == DateTime.now().year,
          )
          .toList();

  int getTotalEarnedThisMonth() {
    return completedThisMonth.fold(
      0,
      (sum, chore) => sum + (int.tryParse(chore.reward) ?? 0),
    );
  }

  int getWaitingForPayment() {
    return unpaidChores.fold(
      0,
      (sum, chore) => sum + (int.tryParse(chore.reward) ?? 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 244, 190, 71),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'My Wallet',
          style: TextStyle(
            fontFamily: 'Pacifico',
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color.fromARGB(255, 255, 255, 255),
          ),
        ),
        //centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMoneyCard(
              'Waiting for Payment',
              '₪${getWaitingForPayment()}',
              Colors.orangeAccent,
            ),
            const SizedBox(height: 16),
            _buildMoneyCard(
              'Received This Month',
              '₪${getTotalEarnedThisMonth()}',
              Colors.greenAccent,
            ),
            const SizedBox(height: 16),
            Text(
              'Chores Completed This Month: ${completedThisMonth.length}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Waiting Chores:',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: unpaidChores.length,
                itemBuilder: (context, index) {
                  final chore = unpaidChores[index];
                  return Card(
                    color: const Color.fromARGB(255, 255, 250, 224),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Text(
                        chore.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '₪${chore.reward} - Completed on ${DateFormat.yMMMd().format(chore.deadline ?? DateTime.now())}',
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

  Widget _buildMoneyCard(String label, String value, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
