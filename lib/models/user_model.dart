import 'package:chore_bid/models/chore_model.dart';

class UserModel {
  final String uid;
  final String name;
  final String role; // "parent" or "child"
  final String? familyId;

  final List<Chore> chores; // local cache of chores

  UserModel({
    required this.uid,
    required this.name,
    required this.role,
    required this.familyId,
    List<Chore>? chores,
  }) : chores = chores ?? [];

  factory UserModel.fromMap(String uid, Map<String, dynamic> data) {
    return UserModel(
      uid: uid,
      name: data['name'] ?? '',
      role: data['role'] ?? 'child',
      familyId: data['familyId'],
    );
  }

  void addChore(Chore chore) {
    chores.add(chore);
  }

  void clearChores() {
    chores.clear();
  }
}
