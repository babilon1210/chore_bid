import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class SignInCode {
  final String code;
  final DateTime? expiresAt;
  SignInCode({required this.code, required this.expiresAt});
}

class SignInStatus {
  final String state; // 'waiting', 'used', 'revoked', 'expired', 'missing'
  final DateTime? when; // usedAt or expiresAt
  const SignInStatus._(this.state, [this.when]);

  factory SignInStatus.waiting(DateTime? expiresAt) => SignInStatus._('waiting', expiresAt);
  factory SignInStatus.used(DateTime? usedAt) => SignInStatus._('used', usedAt);
  factory SignInStatus.revoked() => const SignInStatus._('revoked');
  factory SignInStatus.expired() => const SignInStatus._('expired');
  factory SignInStatus.missing() => const SignInStatus._('missing');
}

class SignInService {
  final _db = FirebaseFirestore.instance;
  final _fn = FirebaseFunctions.instance;

  Future<SignInCode> createChildSignInCode(String childUid) async {
    final res = await _fn.httpsCallable('createChildSignInCode').call({'childUid': childUid});
    final data = Map<String, dynamic>.from(res.data as Map);
    final code = data['code'] as String;
    final expiresAt = DateTime.tryParse((data['expiresAt'] as String?) ?? '');
    return SignInCode(code: code, expiresAt: expiresAt);
  }

  /// Watch a single sign-in code; emits when consumed/revoked/expired.
  Stream<SignInStatus> watchCode(String code) {
    return _db.collection('signInCodes').doc(code).snapshots().map((snap) {
      if (!snap.exists) return SignInStatus.missing();
      final d = snap.data()!;
      final revoked = (d['revoked'] as bool?) ?? false;
      final used = (d['used'] as bool?) ?? false;
      final expiresAt = (d['expiresAt'] as Timestamp?)?.toDate();
      final usedAt = (d['usedAt'] as Timestamp?)?.toDate();
      final expired = expiresAt != null && DateTime.now().isAfter(expiresAt);
      if (used) return SignInStatus.used(usedAt);
      if (revoked) return SignInStatus.revoked();
      if (expired) return SignInStatus.expired();
      return SignInStatus.waiting(expiresAt);
    });
  }
}
