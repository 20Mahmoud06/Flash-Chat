import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  // تحويل User إلى UserModel
  Future<UserModel> _firebaseUserToUserModel(User user) async {
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) {
      return UserModel.fromFirestore(doc);
    } else {
      return UserModel(
        uid: user.uid,
        firstName: '',
        lastName: '',
        email: user.email ?? '',
        phoneNumber: user.phoneNumber ?? '',
        avatarEmoji: '👤',
      );
    }
  }

  Future<UserModel> getUserById(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) throw Exception("User not found");
    return UserModel.fromFirestore(doc);
  }

  Future<void> updateUser(UserModel user) async {
    await _firestore.collection('users').doc(user.uid).update({
      'firstName': user.firstName,
      'lastName': user.lastName,
      'email': user.email,
      'phoneNumber': user.phoneNumber,
      'avatarEmoji': user.avatarEmoji,
    });
  }

  Future<void> deleteUser(String userId) async {
    await _firestore.collection('users').doc(userId).delete();
    final user = _auth.currentUser;
    if (user != null && user.uid == userId) {
      await user.delete();
    }
  }

  // ---------------- Sign In Methods ----------------
  Future<UserModel?> signInWithEmailAndPassword(String email, String password) async {
    try {
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;
      if (user != null) {
        return _firebaseUserToUserModel(user);
      }
      return null;
    } catch (e) {
      print(e);
      return null;
    }
  }

  Future<UserModel?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user != null) {
        return _firebaseUserToUserModel(user);
      }
      return null;
    } catch (e) {
      print('Google Sign-In error: $e');
      return null;
    }
  }

  // ---------------- Sign Up Method ----------------
  Future<UserModel?> createUserWithEmailAndPassword(String email, String password) async {
    try {
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;
      if (user != null) {
        return _firebaseUserToUserModel(user);
      }
      return null;
    } on FirebaseAuthException catch (e) {
      print('Sign Up Error: $e');
      rethrow;
    } catch (e) {
      print('Unexpected Sign Up Error: $e');
      return null;
    }
  }

  // ---------------- Reset Password ----------------
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      print('Reset Password Error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
