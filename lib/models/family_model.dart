import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyModel {
  final String id; // Firestore doc ID
  final String familyCode;
  final List<String> parentIds;
  final List<String> childIds;
  final Timestamp createdAt;

  /// Currency for this family (store either a symbol like "₪" / "$"
  /// or a code like "ILS" / "USD" based on your backend choice).
  final String currency;

  FamilyModel({
    required this.id,
    required this.familyCode,
    required this.parentIds,
    required this.childIds,
    required this.createdAt,
    required this.currency,
  });

  factory FamilyModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    return FamilyModel(
      id: doc.id,
      familyCode: (data['familyCode'] as String?) ?? '',
      parentIds: List<String>.from(data['parentIds'] ?? const []),
      childIds: List<String>.from(data['childIds'] ?? const []),
      createdAt: (data['createdAt'] as Timestamp?) ?? Timestamp.now(),
      currency: (data['currency'] as String?) ?? r'$', // sensible fallback
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'familyCode': familyCode,
      'parentIds': parentIds,
      'childIds': childIds,
      'createdAt': createdAt,
      'currency': currency,
    };
  }

  FamilyModel copyWith({
    String? familyCode,
    List<String>? parentIds,
    List<String>? childIds,
    Timestamp? createdAt,
    String? currency,
  }) {
    return FamilyModel(
      id: id,
      familyCode: familyCode ?? this.familyCode,
      parentIds: parentIds ?? this.parentIds,
      childIds: childIds ?? this.childIds,
      createdAt: createdAt ?? this.createdAt,
      currency: currency ?? this.currency,
    );
  }
}
