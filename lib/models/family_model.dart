import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyModel {
  final String id; // Firestore doc ID
  final String familyCode;
  final List<String> parentIds;
  final List<String> childIds;
  final Timestamp createdAt;

  FamilyModel({
    required this.id,
    required this.familyCode,
    required this.parentIds,
    required this.childIds,
    required this.createdAt,
  });

  factory FamilyModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FamilyModel(
      id: doc.id,
      familyCode: data['familyCode'] ?? '',
      parentIds: List<String>.from(data['parentIds'] ?? []),
      childIds: List<String>.from(data['childIds'] ?? []),
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'familyCode': familyCode,
      'parentIds': parentIds,
      'childIds': childIds,
      'createdAt': createdAt,
    };
  }
}
