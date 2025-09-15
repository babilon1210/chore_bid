// lib/services/auth_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<User?> register({
    required String name,
    required String email,
    required String password,
    required String role,
    String? optionalFamilyCode,
  }) async {
    try {
      // Create user
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Explicit sign-in (usually already signed in after create, but kept for parity)
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;
      if (user == null) {
        print('User creation failed');
        return null;
      }
      print('User created: ${user.uid}');

      // Log ID token
      final idToken = await user.getIdToken();
      print('ID Token: $idToken');

      // Wait for a non-null user on the auth stream
      await _auth.idTokenChanges().firstWhere((u) => u != null);

      // Optional: Force refresh the token (to be extra safe)
      await _auth.currentUser?.getIdToken(true);

      // If you later re-enable the CF path, keep it here.
      // return familyId / user as needed.
      return user;
    } catch (e) {
      print('Registration error: $e');
      return null;
    }
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
          // Non-fatal: user doc may not exist / missing permission. Proceed to sign out.
          print('FCM token cleanup skipped: $e');
        }
      }
    } finally {
      await _auth.signOut();
    }
  }

  User? get currentUser => _auth.currentUser;
}
