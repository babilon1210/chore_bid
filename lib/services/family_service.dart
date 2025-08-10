import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/family_model.dart';

class FamilyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot>? _familySub;

  FamilyModel? currentFamily;
  final StreamController<FamilyModel?> _familyController = StreamController.broadcast();

  Stream<FamilyModel?> get familyStream => _familyController.stream;

  /// Start listening to changes on a family document
  void listenToFamily(String familyId) {
    _familySub?.cancel(); // Cancel previous listener if exists
    _familySub = _firestore.collection('families').doc(familyId).snapshots().listen((doc) {
      if (doc.exists) {
        currentFamily = FamilyModel.fromDoc(doc);
        _familyController.add(currentFamily);
      } else {
        _familyController.add(null);
      }
    });
  }

  /// Stop listening to family updates (e.g., on logout)
  void dispose() {
    _familySub?.cancel();
    _familyController.close();
  }

  /// Optional: Fetch family once (without listening)
  Future<FamilyModel?> fetchFamily(String familyId) async {
    final doc = await _firestore.collection('families').doc(familyId).get();
    return doc.exists ? FamilyModel.fromDoc(doc) : null;
  }

  /// Optional: Add a child to the family
  Future<void> addChild(String familyId, String childUid) async {
    await _firestore.collection('families').doc(familyId).update({
      'childIds': FieldValue.arrayUnion([childUid])
    });
  }

  /// Optional: Add a parent to the family
  Future<void> addParent(String familyId, String parentUid) async {
    await _firestore.collection('families').doc(familyId).update({
      'parentIds': FieldValue.arrayUnion([parentUid])
    });
  }

  Future<DocumentSnapshot?> getUserById(String uid) async {
  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  return doc.exists ? doc : null;
}

Future<Map<String, String>> getChildrenNamesMap(String familyId) async {
  final family = await fetchFamily(familyId);
  if (family == null) return {};

  final childrenSnapshot = await FirebaseFirestore.instance
      .collection('users')
      .where(FieldPath.documentId, whereIn: family.childIds)
      .get();

  return {
    for (var doc in childrenSnapshot.docs)
      doc.id: doc.data()['name'] ?? 'Unnamed',
  };
}


}
