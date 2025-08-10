import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/chore_model.dart';
import 'user_service.dart';

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

  Future<void> claimChore({
  required String familyId,
  required String choreId,
  required String childId,
}) async {
  final choreRef = _firestore
      .collection('families')
      .doc(familyId)
      .collection('chores')
      .doc(choreId);

  await choreRef.set({
  'progress': {
    childId: 'claimed',
  }
}, SetOptions(merge: true));
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

  await choreRef.update({
    'progress.$childId': FieldValue.delete(),
  });
}


  Future<void> markChoreAsVerified({
  required String familyId,
  required String choreId,
  required String childId,
}) async {
  final choreRef = _firestore
      .collection('families')
      .doc(familyId)
      .collection('chores')
      .doc(choreId);

  await choreRef.set({
    'progress.$childId': 'verified',
  }, SetOptions(merge: true));
}

  Future<void> markChoreAsComplete({
  required String familyId,
  required String choreId,
  required String childId,
}) async {
  final choreRef = _firestore
      .collection('families')
      .doc(familyId)
      .collection('chores')
      .doc(choreId);

  await choreRef.set({
    'progress.$childId': 'complete',
  }, SetOptions(merge: true));
}

  /// Stream all chores for the current user's family and update global model
  Stream<List<Chore>> listenToChores(String familyId) {
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('chores')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          final updatedChores =
              snapshot.docs.map((doc) {
                return Chore.fromMap(doc.data(), doc.id);
              }).toList();

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
