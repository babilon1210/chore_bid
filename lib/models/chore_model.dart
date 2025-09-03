// ======================= models/chore_model.dart =======================
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

  /// NEW: progress now stores an object per child:
  /// progress: {
  ///   "<childUid>": { "status": "paid", "time": Timestamp? }
  /// }
  /// (Legacy data where value is a String is still tolerated at read-time.)
  final Map<String, dynamic>? progress;

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
    final deadlineRaw = data['deadline'];
    DateTime deadline;
    if (deadlineRaw is Timestamp) {
      deadline = deadlineRaw.toDate();
    } else if (deadlineRaw is DateTime) {
      deadline = deadlineRaw;
    } else {
      deadline = DateTime.now();
    }

    return Chore(
      id: id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      reward: data['reward'] ?? '',
      status: data['status'] ?? '',
      deadline: deadline,
      assignedTo: List<String>.from(data['assignedTo'] ?? []),
      // Store as dynamic map so we can support both legacy (String) and new ({status,time})
      progress: (data['progress'] is Map)
          ? Map<String, dynamic>.from(data['progress'] as Map)
          : null,
      isExclusive: data['isExclusive'] ?? true,
      isPaid: data['isPaid'] ?? false,
      paidAt: (data['paidAt'] is Timestamp)
          ? (data['paidAt'] as Timestamp).toDate()
          : (data['paidAt'] is DateTime ? data['paidAt'] as DateTime : null),
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
      'progress': progress, // expected to be { childUid: {status, time} }
      'isExclusive': isExclusive,
      'isPaid': isPaid,
      'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
    };
  }
}
