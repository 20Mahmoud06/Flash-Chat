import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../profile/models/user_model.dart';
import 'phone_registry.dart';

class AuthService {
  static const String _profileCacheKeyPrefix = 'cached_user_profile_';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// The most recently loaded, completed profile (memory slot for
  /// [lastKnownProfile]); the persisted copy lives in SharedPreferences.
  UserModel? _lastKnownUser;

  User? get currentUser => _auth.currentUser;

  Future<UserModel> _firebaseUserToUserModel(User user) async {
    final doc = await readUserDocumentAuthoritative(user.uid);

    if (doc == null) {
      // The server read failed across all retries (unreachable). Prefer a
      // previously-known profile for this uid over a blank user, which would
      // trick the caller into thinking a finished account is incomplete and
      // route it to the complete-profile screen. Only if we know nothing do
      // we throw so the cubit can surface an error instead.
      final known = await lastKnownProfile(user.uid);
      if (known != null) return known;
      throw Exception(
        'Could not load your profile. Please check your connection and try again.',
      );
    }

    if (!doc.exists) {
      // The server confirms (across the authoritative retries) there is no
      // Firestore document for this auth account — genuinely a new user who
      // needs to complete their profile. Unless a completed profile is already
      // known for this uid (the doc may have raced the server timestamp), in
      // which case keep it.
      final known = await lastKnownProfile(user.uid);
      if (known != null) return known;
      return UserModel(
        uid: user.uid,
        firstName: '',
        lastName: '',
        email: user.email ?? '',
        phoneNumber: user.phoneNumber ?? '',
        avatarEmoji: '👤',
      );
    }

    // Doc exists — parse it.  Wrap in try-catch so a data-shape mismatch
    // (e.g. after a schema change or R8 field renaming) surfaces as a
    // clear error instead of silently falling through to the blank-user
    // path that routes to OTP.
    try {
      final userModel = UserModel.fromFirestore(doc);
      unawaited(rememberProfile(userModel));
      return userModel;
    } catch (e) {
      debugPrint('Failed to parse UserModel for ${user.uid}: $e');
      throw Exception(
        'Failed to load your profile data. Please try again.',
      );
    }
  }

  /// Remembers the last successfully loaded profile so a slow or failed
  /// Firestore read on a later sign-in can fall back to it instead of
  /// mis-routing an existing user to the complete-profile screen.
  Future<void> rememberProfile(UserModel user) async {
    _lastKnownUser = user;
    if (user.firstName.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_profileCacheKeyPrefix${user.uid}',
        jsonEncode(user.toMap()),
      );
    } catch (_) {}
  }

  /// The last completed profile known for [uid] (memory, then on-disk).
  /// Returns null when the user genuinely has no completed profile yet.
  Future<UserModel?> lastKnownProfile(String uid) async {
    final inMemory = _lastKnownUser;
    if (inMemory?.uid == uid && inMemory!.firstName.isNotEmpty) {
      return inMemory;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_profileCacheKeyPrefix$uid');
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final user = _decodeProfile(json);
      if (user != null && user.uid == uid && user.firstName.isNotEmpty) {
        _lastKnownUser = user;
        return user;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  UserModel? _decodeProfile(Map<String, dynamic> json) {
    try {
      return UserModel(
        uid: json['uid'] as String? ?? '',
        email: json['email'] as String? ?? '',
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        phoneNumber: json['phoneNumber'] as String? ?? '',
        avatarEmoji: json['avatarEmoji'] as String? ?? '👤',
        bio: json['bio'] as String?,
        fcmToken: json['fcmToken'] as String?,
        blockedUids: List<String>.from(json['blockedUids'] ?? const []),
        isDeleted: json['isDeleted'] ?? false,
        phoneVerified: json['phoneVerified'] ?? false,
        presenceEnabled: json['presenceEnabled'] != false,
        nicknames: json['nicknames'] is Map
            ? (json['nicknames'] as Map)
                .map((k, v) => MapEntry(k.toString(), v.toString()))
            : const <String, String>{},
      );
    } catch (_) {
      return null;
    }
  }

  /// Reads the user document for [uid] with ONE fast server attempt (plus an
  /// on-device cache fallback) and, when the first read fails or comes back
  /// missing, a single short re-check. No artificial backoff sleeps.
  ///
  /// Returns a snapshot with `exists == false` only when the server (and a
  /// re-check) genuinely reports the document is absent. Returns null only
  /// when Firestore is unreachable AND there is no cached document. Callers
  /// must NOT treat a transient failure as "no profile".
  Future<DocumentSnapshot?> readUserDocument(String uid) async {
    var doc = await _readUserDocOnce(uid);
    if (doc != null && doc.exists) return doc;

    // First read failed or returned a cache-miss snapshot that may have raced
    // the server document landing: verify once more before concluding the
    // profile genuinely does not exist (this is what fixed existing users
    // landing on the complete-profile screen until the app was reopened).
    final retry = await _readUserDocOnce(uid);
    if (retry != null && retry.exists) return retry;
    if (retry != null) doc = retry;
    return doc;
  }

  Future<DocumentSnapshot?> _readUserDocOnce(String uid) async {
    try {
      return await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      try {
        return await _firestore
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        return null;
      }
    }
  }

  /// Server-only profile read, retried a few times across the transient
  /// window right after a sign-in (the first Firestore request can be
  /// rejected until the fresh ID token propagates). NEVER serves the on-device
  /// cache: the signup flow leaves a name-less shell doc in that cache, so
  /// trusting it right after login is what bounced existing users into
  /// "Complete Profile" until they restarted the app. Callers that need to
  /// tell "genuinely new user" from "existing user" must use this, not
  /// [readUserDocument].
  Future<DocumentSnapshot?> readUserDocumentAuthoritative(String uid) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final doc = await _firestore
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 4));
        return doc;
      } catch (e) {
        debugPrint('Authoritative read attempt ${attempt + 1} failed for $uid: $e');
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    }
    return null;
  }

  Future<UserModel> getUserById(String userId) async {
    final doc = await readUserDocument(userId);
    if (doc == null || !doc.exists) throw Exception("User not found");
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
    } on FirebaseAuthException catch (e) {
      debugPrint('Sign in error: $e');
      rethrow;
    } catch (e) {
      debugPrint('Sign in error: $e');
      return null;
    }
  }

  /// Returns the sign-in methods registered for [email] (`password`,
  /// `google.com`, ...), an empty list when no account exists for that
  /// email, or `null` when the lookup itself failed (e.g. the project has
  /// email enumeration protection enabled, or there is no connectivity).
  /// Callers must treat `null` as "unknown" and fall back to the plain flow.
  Future<List<String>?> fetchSignInMethodsForEmail(String email) async {
    try {
      // ignore: deprecated_member_use
      return await _auth.fetchSignInMethodsForEmail(email);
    } catch (e) {
      debugPrint('Could not check sign-in methods: $e');
      return null;
    }
  }

  Future<UserModel?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      // null = the user cancelled the Google account picker, not an error.
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
    } on FirebaseAuthException catch (e) {
      debugPrint('Google Sign-In error: $e');
      rethrow;
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      rethrow;
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