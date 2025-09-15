// lib/services/auth_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a user with email/password and return the signed-in Firebase [User].
  /// NOTE: We do NOT create a family here. Registration UI will send a verification
  /// email and then wait for verification before proceeding to family creation.
  Future<User?> register({
    required String name,
    required String email,
    required String password,
    required String role,
    String? optionalFamilyCode,
  }) async {
    try {
      // Create user (this signs the user in)
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;
      if (user == null) {
        print('User creation failed');
        return null;
      }
      print('User created: ${user.uid}');

      // Log ID token (debug)
      final idToken = await user.getIdToken();
      print('ID Token: $idToken');

      // Ensure we have a non-null user in the stream
      await _auth.idTokenChanges().firstWhere((u) => u != null);

      // Optional: force refresh token
      await _auth.currentUser?.getIdToken(true);

      // Return user; the caller will trigger email verification flow.
      return user;
    } catch (e) {
      print('Registration error: $e');
      return null;
    }
  }

  /// Sends a verification email to the currently signed-in user (if needed).
  Future<void> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No signed-in user to send verification to.');
    }
    if (user.emailVerified) return; // nothing to do
    await user.sendEmailVerification();
  }

  /// Reload current user and return whether email is verified.
  Future<bool> reloadAndCheckVerified() async {
    await _auth.currentUser?.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// (Optional helper) Poll until email is verified or timeout expires.
  Future<bool> waitForEmailVerification({
    Duration pollEvery = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final ok = await reloadAndCheckVerified();
      if (ok) return true;
      await Future.delayed(pollEvery);
    }
    return false;
  }

  /// Signs the user out.
  /// Also clears this device's FCM token from the user doc (best-effort).
  Future<void> logout({bool clearFcmToken = true}) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (clearFcmToken && uid != null) {
        try {
          await _firestore
              .collection('users')
              .doc(uid)
              .update({'fcmToken': FieldValue.delete()});
        } catch (e) {
          // Non-fatal
          print('FCM token cleanup skipped: $e');
        }
      }
    } finally {
      await _auth.signOut();
    }
  }

  User? get currentUser => _auth.currentUser;
}
