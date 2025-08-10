import 'dart:math';
import 'package:chore_bid/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; 

class ChoreCard extends StatelessWidget {
  final String title;
  final String reward;
  final String status;
  final Map<String, String>? progress; // NEW
  final List<String> assignedTo;
  final VoidCallback? onTap;
  final DateTime deadline;
  final bool isExclusive;

  final int colorSeed;

  const ChoreCard({
    super.key,
    required this.title,
    required this.reward,
    required this.deadline,
    required this.status,
    required this.isExclusive,
    required this.assignedTo,
    required this.progress,
    this.onTap,
    int? seed,
  }) : colorSeed = seed ?? 0;

  static final List<Color> happyColors = [
    Color(0xFFFFF59D),
    Color.fromARGB(255, 237, 176, 157),
    Color.fromARGB(255, 153, 227, 237),
    Color.fromARGB(255, 157, 218, 159),
    Color.fromARGB(255, 184, 162, 224),
    Color(0xFFFFF176),
    Color.fromARGB(255, 237, 161, 169),
  ];

  Color getCardColor() {
    if (progress != null && progress!.containsValue('verified')) return Colors.green[100]!;
    final random = Random(title.hashCode + colorSeed);
    return happyColors[random.nextInt(happyColors.length)];
  }

  String get formattedDeadline {
    final timeFormat = DateFormat.jm();
    return 'Before ${timeFormat.format(deadline)}';
  }

  String getProgressSummary() {
    final claimedCount = progress?.values.where((s) => s != 'assigned').length ?? 0;
    return '$claimedCount/${assignedTo.length} claimed';
  }

  String getCurrentUserStatus() {
    final uid = UserService.currentUser!.uid;
    return progress?[uid] ?? 'Available';
  }

  @override
  Widget build(BuildContext context) {
    final role = UserService.currentUser!.role;
    final isChild = role == 'child';

    return Card(
      color: getCardColor(),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color.fromARGB(255, 30, 2, 49),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 6),
                Text(
                  '₪$reward',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 30, 2, 49),
                  ),
                ),
                Text(
                  ' - $formattedDeadline',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 30, 2, 49),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
        trailing: Builder(
          builder: (context) {
            final currentUserStatus = getCurrentUserStatus();
            final showAvailable = currentUserStatus == 'assigned';

            if (showAvailable) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 243, 117, 86),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'Available',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 255, 255, 255),
                      ),
                    ),
                  ),
                ],
              );
            }

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB2DFDB),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    isExclusive || isChild
                        ? currentUserStatus
                        : getProgressSummary(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00695C),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        onTap: onTap,
      ),
    );
  }
}
