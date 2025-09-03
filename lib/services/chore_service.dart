import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/chore_model.dart';
import 'user_service.dart';

/// ChoreService
/// ------------------------------
/// Progress schema CHANGE:
/// We now store per-child progress as an object with both status and time.
/// Example:
/// progress: {
///   "<childUid>": { "status": "paid", "time": <server timestamp> }
/// }
///
/// ⚠️ If other parts of the app still expect `progress[childId]` to be a string,
/// you must update those reads to use `progress[childId]['status']`.
class ChoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Add a new chore to Firestore under the current user's family
  Future<void> addChore({
    required String familyId,
    required String title,
    required String description,
    required String reward,
    required DateTime deadline,
    required List<String> assignedTo,
    required bool isExclusive,
  }) async {
    await FirebaseFunctions.instance
        .httpsCallable('createChoreWithTasks')
        .call({
          'familyId': familyId,
          'title': title,
          'description': description,
          'reward': reward,
          'deadline': deadline.toUtc().toIso8601String(),
          'assignedTo': assignedTo,
          'isExclusive': isExclusive,
        });
  }

  Future<void> updateChore({
    required String familyId,
    required String choreId,
    required String title,
    required String reward,
    required DateTime deadline,
    required List<String> assignedTo,
  }) async {
    await _firestore
        .collection('families')
        .doc(familyId)
        .collection('chores')
        .doc(choreId)
        .update({
          'title': title,
          'reward': reward,
          'deadline': deadline,
          'assignedTo': assignedTo,
        });
  }

  Future<void> deleteChore({
    required String familyId,
    required String choreId,
  }) async {
    await _firestore
        .collection('families')
        .doc(familyId)
        .collection('chores')
        .doc(choreId)
        .delete();
  }

  /// Helper: build the nested progress payload for a single child.
  /// If [time] is null, uses serverTimestamp().
  Map<String, dynamic> _progressEntry(String status, {DateTime? time}) {
    return {
      'status': status,
      'time':
          time != null
              ? Timestamp.fromDate(time.toUtc())
              : FieldValue.serverTimestamp(),
    };
  }

  /// Helper: upsert progress for one child (merge)
  Future<void> _setProgress({
    required String familyId,
    required String choreId,
    required String childId,
    required String status,
    DateTime? time,
  }) async {
    final choreRef = _firestore
        .collection('families')
        .doc(familyId)
        .collection('chores')
        .doc(choreId);

    await choreRef.set({
      'progress': {childId: _progressEntry(status, time: time)},
    }, SetOptions(merge: true));
  }

  Future<void> claimChore({
    required String familyId,
    required String choreId,
    required String childId,
  }) async {
    await _setProgress(
      familyId: familyId,
      choreId: choreId,
      childId: childId,
      status: 'claimed',
    );
  }

  Future<void> unclaimChore({
    required String familyId,
    required String choreId,
    required String childId,
  }) async {
    final choreRef = _firestore
        .collection('families')
        .doc(familyId)
        .collection('chores')
        .doc(choreId);

    // delete only this child's progress object
    await choreRef.update({'progress.$childId': FieldValue.delete()});
  }

  Future<void> markChoreAsComplete({
    required String familyId,
    required String choreId,
    required String childId,
    required DateTime time,
  }) async {
    await _setProgress(
      familyId: familyId,
      choreId: choreId,
      childId: childId,
      status: 'complete',
      time: time,
    );
  }

  Future<void> markChoreAsVerified({
    required String familyId,
    required String choreId,
    required String childId,
    required DateTime time,
  }) async {
    await _setProgress(
      familyId: familyId,
      choreId: choreId,
      childId: childId,
      status: 'verified',
      time: time,
    );
  }


  Future<void> markChoreAsPaid({
    required String familyId,
    required String choreId,
    required String childId,
    required int amountCents,
    required DateTime paidAt,
    String currency = 'ILS',
    String method = 'cash',
    String? txRef,
    String? paidByUid,
  }) async {
    final choreRef = _firestore
        .collection('families')
        .doc(familyId)
        .collection('chores')
        .doc(choreId);

    final paymentsRef =
        choreRef.collection('payments').doc(); // or .doc(childId) if 1:1
    final batch = _firestore.batch();

    // 1) Update child's progress to a structured {status, time}
    batch.set(choreRef, {
      'progress': {childId: _progressEntry('paid', time: paidAt)},
    }, SetOptions(merge: true));

    // 2) Add a payment record
    batch.set(paymentsRef, {
      'childId': childId,
      'amountCents': amountCents,
      'currency': currency,
      'method': method,
      'txRef': txRef,
      'paidBy': paidByUid,
      'paidAt':
          paidAt != null
              ? Timestamp.fromDate(paidAt.toUtc())
              : FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Stream all chores for the current user's family and update global model
  Stream<List<Chore>> listenToChores(String familyId) {
    const activeStatuses = [
      'available',
      'claimed',
      'complete',
      'verified',
      'paid',
    ];
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('chores')
        .where('status', whereIn: activeStatuses)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          final updatedChores =
              snapshot.docs
                  .map((doc) => Chore.fromMap(doc.data(), doc.id))
                  .toList();

          // ✅ Update global model
          if (UserService.currentUser != null) {
            UserService.currentUser!.clearChores();
            for (var chore in updatedChores) {
              UserService.currentUser!.addChore(chore);
            }
          }

          return updatedChores;
        });
  }
}
