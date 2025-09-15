import 'package:cloud_firestore/cloud_firestore.dart';

class InviteStatus {
  final String state; // 'waiting', 'used', 'missing'
  final String? childUid;
  final DateTime? usedAt;
  const InviteStatus._(this.state, {this.childUid, this.usedAt});

  factory InviteStatus.waiting() => const InviteStatus._('waiting');
  factory InviteStatus.used(String? childUid, DateTime? usedAt) =>
      InviteStatus._('used', childUid: childUid, usedAt: usedAt);
  factory InviteStatus.missing() => const InviteStatus._('missing');
}

class InviteService {
  final _db = FirebaseFirestore.instance;

  /// Watch a single invite by code; emits when the child scans it.
  Stream<InviteStatus> watchInvite(String code) {
    return _db.collection('invites').doc(code).snapshots().map((snap) {
      if (!snap.exists) return InviteStatus.missing();
      final d = snap.data()!;
      final used = (d['used'] as bool?) ?? false;
      if (!used) return InviteStatus.waiting();
      final usedAt = (d['usedAt'] as Timestamp?)?.toDate();
      final childUid = d['childUid'] as String?;
      return InviteStatus.used(childUid, usedAt);
    });
  }
}
