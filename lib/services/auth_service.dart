import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  Future<User?> register({
    required String name,
    required String email,
    required String password,
    required String role,
    String? optionalFamilyCode,
  }) async {
    try {
      // Create user
      final result = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await FirebaseAuth.instance.signInWithEmailAndPassword(
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

      await FirebaseAuth.instance.idTokenChanges().firstWhere(
        (user) => user != null,
      );

      // Optional: Force refresh the token (to be extra safe)
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      // Call Cloud Function
      // final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('createUserWithFamily');
      // final response = await callable.call({
      //   'name': name,
      //   'role': role,
      //   if (optionalFamilyCode != null) 'familyCode': optionalFamilyCode,
      // });

      // final String familyId = response.data['familyId'];
      // final prefs = await SharedPreferences.getInstance();
      // await prefs.setString('familyId', familyId);
      // print('Family ID saved: $familyId');
      return user;
    } catch (e) {
      print('Registration error: $e');
      return null;
    }
  }
}
