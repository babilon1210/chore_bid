import 'package:cloud_firestore/cloud_firestore.dart';

class Chore {
  final String id;
  final String title;
  final String reward;
  final String status;
  final String description;
  final DateTime deadline;
  final bool isPaid;
  final DateTime? paidAt;
  final List<String> assignedTo;
  final Map<String, String>? progress;
  final bool isExclusive;

  Chore({
    required this.id,
    required this.title,
    required this.reward,
    required this.deadline,
    required this.status,
    required this.assignedTo,
    required this.isExclusive,
    required this.description,
    this.progress,
    this.isPaid = false,
    this.paidAt,
  });

  factory Chore.fromMap(Map<String, dynamic> data, String id) {
    return Chore(
      id: id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      reward: data['reward'] ?? '',
      status: data['status'] ?? '',
      deadline: (data['deadline'] as Timestamp).toDate(),
      assignedTo: List<String>.from(data['assignedTo'] ?? []),
      progress: data['progress'] != null
          ? Map<String, String>.from(data['progress'])
          : null,
      isExclusive: data['isExclusive'] ?? true,
      isPaid: data['isPaid'] ?? false,
      paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'reward': reward,
      'status': status,
      'description': description,
      'deadline': Timestamp.fromDate(deadline),
      'assignedTo': assignedTo,
      'progress': progress,
      'isExclusive': isExclusive,
      'isPaid': isPaid,
      'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
    };
  }
}
