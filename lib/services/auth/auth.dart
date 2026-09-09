import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/user_model.dart';
import 'phone_registry.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

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
    // Tombstone the profile document first so other apps can show the
    // deleted state (red X, read-only chat), then delete the Auth user.
    try {
      await _firestore.collection('users').doc(userId).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'fcmToken': FieldValue.delete(),
      });
    } on FirebaseException catch (_) {
      // The document may already be gone; deleting the Auth user is what
      // actually removes the account.
    }

    // Release the phone-number claim so the number can be registered again.
    try {
      final profileDoc =
          await _firestore.collection('users').doc(userId).get();
      final phone = profileDoc.data()?['phoneNumber'] as String?;
      if (phone != null && phone.isNotEmpty) {
        await PhoneRegistry.instance.release(phone);
      }
    } catch (_) {}

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
       debugPrint('Sign in error: $e');
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
      debugPrint('Google Sign-In error: $e');
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
      debugPrint('Sign Up Error: $e');
      rethrow;
    } catch (e) {
      debugPrint('Unexpected Sign Up Error: $e');
      return null;
    }
  }

  // ---------------- Reset Password ----------------
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      debugPrint('Reset Password Error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// The primary sign-in provider for the current account: `password`,
  /// `google.com`, or `null` (not signed in / unknown).
  String? get primaryProvider {
    final user = _auth.currentUser;
    if (user == null) return null;
    for (final info in user.providerData) {
      if (info.providerId == 'password') return 'password';
      if (info.providerId == 'google.com') return 'google.com';
    }
    return user.providerData.isNotEmpty
        ? user.providerData.first.providerId
        : null;
  }

  // ---------------- Re-authentication ----------------

  /// Re-authenticates an email/password account so sensitive operations
  /// (e.g. `user.delete()`) no longer fail with `requires-recent-login`.
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Not signed in.");
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw Exception("No email address on this account.");
    }
    final credential =
        EmailAuthProvider.credential(email: email, password: password);
    await user.reauthenticateWithCredential(credential);
  }

  /// Re-authenticates a Google account by triggering a Google sign-in again.
  /// Returns `false` if the user cancelled the Google sheet.
  Future<bool> reauthenticateWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Not signed in.");

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return false;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );
    await user.reauthenticateWithCredential(credential);
    return true;
  }
}
