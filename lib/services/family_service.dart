import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/family_model.dart';

/// Lightweight model for a child user in the family list.
class FamilyChild {
  final String uid;
  final String name;
  final Timestamp? createdAt;

  FamilyChild({
    required this.uid,
    required this.name,
    this.createdAt,
  });

  factory FamilyChild.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return FamilyChild(
      uid: doc.id,
      name: (data['name'] as String?) ?? 'Child',
      createdAt: data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : null,
    );
  }
}

/// Lightweight model for a pending child invite.
class ChildInvite {
  final String code; // invite document id
  final String name;
  final String familyId;
  final bool used;
  final Timestamp? createdAt;

  ChildInvite({
    required this.code,
    required this.name,
    required this.familyId,
    required this.used,
    this.createdAt,
  });

  factory ChildInvite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ChildInvite(
      code: doc.id,
      name: (data['name'] as String?) ?? 'New child',
      familyId: (data['familyId'] as String?) ?? '',
      used: (data['used'] as bool?) ?? false,
      createdAt: data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : null,
    );
  }
}

class FamilyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot>? _familySub;

  FamilyModel? currentFamily;
  final StreamController<FamilyModel?> _familyController =
      StreamController.broadcast();

  /// Stream of the whole family model
  Stream<FamilyModel?> get familyStream => _familyController.stream;

  /// Convenience: just the family's currency (updates live)
  Stream<String?> get currencyStream => familyStream.map((f) => f?.currency);

  /// Convenience: current currency (or a sensible default)
  String get currentCurrency => currentFamily?.currency ?? r'$';

  /// Start listening to changes on a family document
  void listenToFamily(String familyId) {
    _familySub?.cancel(); // Cancel previous listener if exists
    _familySub = _firestore
        .collection('families')
        .doc(familyId)
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        currentFamily = FamilyModel.fromDoc(doc);
        _familyController.add(currentFamily);
      } else {
        currentFamily = null;
        _familyController.add(null);
      }
    });
  }

  /// Stop listening to family updates (e.g., on logout)
  void dispose() {
    _familySub?.cancel();
    _familyController.close();
  }

  /// Fetch family once (without listening)
  Future<FamilyModel?> fetchFamily(String familyId) async {
    final doc = await _firestore.collection('families').doc(familyId).get();
    return doc.exists ? FamilyModel.fromDoc(doc) : null;
  }

  /// Update the family's currency
  Future<void> setFamilyCurrency(String familyId, String currency) async {
    await _firestore.collection('families').doc(familyId).set(
      {'currency': currency},
      SetOptions(merge: true),
    );
  }

  /// Add a child to the family (helper)
  Future<void> addChild(String familyId, String childUid) async {
    await _firestore.collection('families').doc(familyId).update({
      'childIds': FieldValue.arrayUnion([childUid])
    });
  }

  /// Add a parent to the family (helper)
  Future<void> addParent(String familyId, String parentUid) async {
    await _firestore.collection('families').doc(familyId).update({
      'parentIds': FieldValue.arrayUnion([parentUid])
    });
  }

  /// Fetch a user document by uid (helper)
  Future<DocumentSnapshot?> getUserById(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.exists ? doc : null;
  }

  /// One-off: returns a map of childId -> name using the family's childIds list.
  Future<Map<String, String>> getChildrenNamesMap(String familyId) async {
    final family = await fetchFamily(familyId);
    if (family == null || family.childIds.isEmpty) return {};

    // If childIds > 10, you may need to chunk; typical families are small.
    final childrenSnapshot = await _firestore
        .collection('users')
        .where(FieldPath.documentId, whereIn: family.childIds)
        .get();

    return {
      for (var doc in childrenSnapshot.docs)
        doc.id: (doc.data()['name'] as String?) ?? 'Unnamed',
    };
  }

  /// **Stream** of children in the family (id + name), ordered by createdAt desc.
  Stream<List<FamilyChild>> childrenStream(String familyId) {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'child')
        .where('familyId', isEqualTo: familyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map((d) => FamilyChild.fromDoc(d)).toList());
  }

  /// **Stream** of pending child invites for this family.
  Stream<List<ChildInvite>> pendingChildInvitesStream(String familyId) {
    return _firestore
        .collection('invites')
        .where('type', isEqualTo: 'childInvite')
        .where('familyId', isEqualTo: familyId)
        .where('used', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map((d) => ChildInvite.fromDoc(d)).toList());
  }
}
