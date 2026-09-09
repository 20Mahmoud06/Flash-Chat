import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/features/profile/cubit/profile_state.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/services/auth/auth.dart';
import 'package:flash_chat_app/services/auth/phone_registry.dart';
import 'package:flash_chat_app/services/presence/presence_service.dart';
import 'package:flutter/foundation.dart';

class ProfileCubit extends Cubit<ProfileState> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  /// Last successfully loaded profile. Lets the UI keep showing the loaded
  /// profile even while a transient error state (e.g. a failed delete or a
  /// temporary connectivity error) is set, instead of flipping to a bare
  /// "Could not load profile" screen.
  UserModel? _lastLoadedUser;

  UserModel? get lastLoadedUser => _lastLoadedUser;

  ProfileCubit() : super(ProfileInitial());

  /// Claims [phone] for [uid] inside [tx] by writing the registry document.
  /// The read-then-write on that document makes concurrent claims of the
  /// same number race each other, so only one can commit. [legacyTaken]
  /// comes from a scan done before the transaction and covers accounts
  /// whose docs predate the registry. Throws if the number belongs to a
  /// live user other than [uid].
  Future<void> _claimPhoneInTransaction(
    Transaction tx,
    String phone,
    String uid,
    bool legacyTaken,
    String alreadyRegisteredMessage,
  ) async {
    if (legacyTaken) throw Exception(alreadyRegisteredMessage);

    final registryRef = PhoneRegistry.instance.claimRef(phone);
    final claim = await tx.get(registryRef);
    if (claim.exists) {
      final owner = claim.data()?['uid'] as String?;
      if (owner != null && owner.isNotEmpty && owner != uid) {
        final ownerSnap =
            await tx.get(_firestore.collection('users').doc(owner));
        if (ownerSnap.exists && ownerSnap.data()?['isDeleted'] != true) {
          throw Exception(alreadyRegisteredMessage);
        }
      }
    }

    tx.set(registryRef, {
      'uid': uid,
      'claimedAt': FieldValue.serverTimestamp(),
    });
  }

  /// True when another live user's profile (created before the phone
  /// registry existed) already stores [phone].
  Future<bool> _legacyPhoneTaken(String phone, String uid) async {
    final legacy = await _firestore
        .collection('users')
        .where('phoneNumber', isEqualTo: phone)
        .limit(10)
        .get();
    return legacy.docs
        .any((d) => d.id != uid && d.data()['isDeleted'] != true);
  }

  // --- FETCH USER DATA ---
  Future<void> loadUserProfile() async {
    // Don't show loading indicator if we already have data
    if (state is! ProfileLoaded) {
      emit(ProfileLoading());
    }
    try {
      final user = _auth.currentUser;
      if (user == null) {
        emit(const ProfileError("User is not authenticated."));
        return;
      }
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        emit(const ProfileError("User profile does not exist."));
        return;
      }
      final userModel = UserModel.fromFirestore(doc);
      _lastLoadedUser = userModel;
      emit(ProfileLoaded(userModel));
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  // --- COMPLETE NEW USER PROFILE ---
  Future<void> completeUserProfile({
    required String firstName,
    required String lastName,
    required String phoneNumber,
    bool phoneVerified = false,
  }) async {
    emit(ProfileLoading());
    try {
final user = _auth.currentUser;
      if (user == null) throw Exception("No user is currently signed in.");

      final phone = PhoneRegistry.toE164(phoneNumber);
      if (PhoneRegistry.normalizeDigits(phone).isEmpty) {
        throw Exception('Please enter a valid phone number.');
      }

      // Update Firebase Auth user with display name
      if (user.displayName == null || user.displayName!.isEmpty) {
        await user.updateDisplayName('$firstName $lastName');
      }

      // Claim the number inside a transaction: the registry read + write
      // races every other concurrent sign-up, so two users can never both
      // register the same number.
      final uid = user.uid;
      final email = user.email ?? '';
      final legacyTaken = await _legacyPhoneTaken(phone, uid);
      await _firestore.runTransaction((tx) async {
        await _claimPhoneInTransaction(
          tx,
          phone,
          uid,
          legacyTaken,
          'This phone number is already registered.',
        );

        // MERGE only the identity fields: this flow also runs on reinstall if
        // the profile doc is missing/incomplete, and a full overwrite would
        // wipe chats-related data (mutedChats, nicknames, blockedUids, push
        // tokens). Merge keeps every pre-existing field intact.
        tx.set(_firestore.collection('users').doc(uid), {
          'uid': uid,
          'email': email,
          'firstName': firstName,
          'lastName': lastName,
          'phoneNumber': phone,
          'avatarEmoji': '👤',
          'phoneVerified': phoneVerified,
        }, SetOptions(merge: true));
      });

      // Reload the user to get the updated data
      await user.reload();

      emit(const ProfileUpdateSuccess("Profile completed successfully!"));
    } catch (e) {
      emit(ProfileError(e.toString().replaceFirst("Exception: ", "")));
    }
  }

  // --- COMPLETE PHONE VERIFICATION ---
  Future<void> completePhoneVerification({
    required String firstName,
    required String lastName,
    required String phoneNumber,
  }) async {
    emit(ProfileLoading());
    try {
      // Guard against a stalled Firestore transaction that never resolves:
      // emit a non-loading error instead of leaving the UI on the loading
      // spinner forever.
      await _completePhoneVerificationInner(
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
      ).timeout(const Duration(seconds: 30));
      emit(const ProfileUpdateSuccess("Phone verified successfully!"));
    } on TimeoutException {
      emit(const ProfileError(
          'Verification is taking too long. Please check your connection and try again.'));
    } catch (e) {
      emit(ProfileError(e.toString().replaceFirst("Exception: ", "")));
    }

    // Refresh the Firebase Auth user in the background. MUST NOT block the
    // success UI: on some devices/emulators `user.reload()` can stall even
    // after the Firestore write succeeded, which would leave the screen on
    // the loading spinner forever. The transaction commit is the source of
    // truth that the phone is verified, so we emit success above first.
    unawaited(_refreshAuthUser());
  }

  Future<void> _refreshAuthUser() async {
    try {
      await _auth.currentUser?.reload();
    } catch (e) {
      debugPrint('Failed to reload auth user after phone verification: $e');
    }
  }

  Future<void> _completePhoneVerificationInner({
    required String firstName,
    required String lastName,
    required String phoneNumber,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("No user is currently signed in.");

    final phone = PhoneRegistry.toE164(phoneNumber);
    if (PhoneRegistry.normalizeDigits(phone).isEmpty) {
      throw Exception('Please enter a valid phone number.');
    }

    // Update Firebase Auth user with display name if not set
    if (user.displayName == null || user.displayName!.isEmpty) {
      await user.updateDisplayName('$firstName $lastName');
    }

    // Claim the number inside a transaction: the registry read + write
    // races every other concurrent sign-up, so two users can never both
    // register the same number.
    final uid = user.uid;
    final email = user.email ?? '';
    final legacyTaken = await _legacyPhoneTaken(phone, uid);
    await _firestore.runTransaction((tx) async {
      await _claimPhoneInTransaction(
        tx,
        phone,
        uid,
        legacyTaken,
        'This phone number is already registered.',
      );

      // Update Firestore with verified phone number
      tx.set(_firestore.collection('users').doc(uid), {
        'uid': uid,
        'email': email,
        'firstName': firstName,
        'lastName': lastName,
        'phoneNumber': phone,
        'avatarEmoji': '👤',
        'phoneVerified': true,
      }, SetOptions(merge: true));
    });
  }

  // --- UPDATE EXISTING PROFILE ---
  Future<void> updateUserProfile({
    required UserModel originalUser,
    required String newFirstName,
    required String newLastName,
    required String newPhone,
    required String newEmail,
    String? newEmoji,
    String? newBio,
  }) async {
    emit(ProfileLoading());
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception("User not authenticated");

      final firestoreUpdates = <String, dynamic>{};
      bool emailUpdateInitiated = false;
      bool phoneChanged = false;

      // Check for changes and build the update map
      if (newFirstName != originalUser.firstName) firestoreUpdates['firstName'] = newFirstName;
      if (newLastName != originalUser.lastName) firestoreUpdates['lastName'] = newLastName;
      if (newEmoji != null && newEmoji != originalUser.avatarEmoji) firestoreUpdates['avatarEmoji'] = newEmoji;
      if (newBio != originalUser.bio) firestoreUpdates['bio'] = newBio;

      // Initiate email update if changed. Runs before the phone claim so a
      // rejected email change never leaves the new phone already committed.
      if (newEmail != originalUser.email) {
        await user.verifyBeforeUpdateEmail(newEmail);
        emailUpdateInitiated = true;
      }

      // Validate and add phone number if changed (deleted-account
      // tombstones don't block reuse of the number). The new number is
      // claimed in a transaction so concurrent changes can't collide.
      if (newPhone != originalUser.phoneNumber) {
        final phone = PhoneRegistry.toE164(newPhone);
        if (PhoneRegistry.normalizeDigits(phone).isEmpty) {
          throw Exception('Please enter a valid phone number.');
        }
        final legacyTaken = await _legacyPhoneTaken(phone, user.uid);
        await _firestore.runTransaction((tx) async {
          await _claimPhoneInTransaction(
            tx,
            phone,
            user.uid,
            legacyTaken,
            "This phone number is already in use.",
          );
          tx.set(_firestore.collection('users').doc(user.uid),
              {'phoneNumber': phone}, SetOptions(merge: true));
        });
        // The old number is only released once the new claim committed.
        await PhoneRegistry.instance.release(originalUser.phoneNumber);
        phoneChanged = true;
      }

      if (firestoreUpdates.isEmpty && !emailUpdateInitiated && !phoneChanged) {
        throw Exception("You haven't made any changes.");
      }

      if (firestoreUpdates.isNotEmpty) {
        await _firestore.collection('users').doc(user.uid).update(firestoreUpdates);
      }

      String successMessage = "Your profile has been updated!";
      if (emailUpdateInitiated) {
        successMessage = "Profile updated! A verification link has been sent to your new email.";
      }
      emit(ProfileUpdateSuccess(successMessage));

      // Reload profile to reflect changes instantly
      await loadUserProfile();

    } on FirebaseAuthException catch (e) {
      String errorMessage = "An error occurred. Please try again.";
      if (e.code == 'email-already-in-use') errorMessage = 'This email is already in use.';
      if (e.code == 'requires-recent-login') errorMessage = 'This is a sensitive action. Please log in again to update your email.';
      emit(ProfileError(errorMessage));
    } catch (e) {
      emit(ProfileError(e.toString().replaceFirst("Exception: ", "")));
    }
  }

  // --- ONLINE STATUS PRIVACY ---
  Future<void> updatePresenceEnabled(bool value) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'presenceEnabled': value,
      });
      await PresenceService.instance.setPresenceEnabled(value);
      await loadUserProfile();
    } catch (e) {
      debugPrint('Failed to update presence setting: $e');
      emit(ProfileError("Failed to update setting: $e"));
    }
  }

  // --- LOGOUT ---
  Future<void> logout() async {
    emit(ProfileLoading());
    try {
      await _auth.signOut();
      emit(ProfileLogoutSuccess());
    } catch (e) {
      emit(ProfileError("Failed to log out: $e"));
    }
  }

  // --- DELETE ACCOUNT ---
  Future<void> deleteAccount() async {
    emit(ProfileLoading());
    try {
      await _performDelete();
      emit(ProfileDeleteSuccess());
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // Re-authentication is needed before the sensitive delete can run.
        emit(ProfileReauthRequired());
        return;
      }
      emit(ProfileError(_friendlyDeleteError(e)));
    } catch (e) {
      emit(ProfileError(_friendlyDeleteError(e)));
    }
  }

  /// Re-authenticates the user and then deletes the account.
  ///
  /// [password] is required for email/password accounts. For Google accounts
  /// a fresh Google sign-in is triggered instead.
  Future<void> reauthenticateAndDelete({String? password}) async {
    emit(ProfileLoading());
    final authService = AuthService();
    try {
      if (authService.primaryProvider == 'google.com') {
        final ok = await authService.reauthenticateWithGoogle();
        if (!ok) {
          // User cancelled the Google sign-in sheet; restore the loaded view.
          if (_lastLoadedUser != null) {
            emit(ProfileLoaded(_lastLoadedUser!));
          } else {
            emit(ProfileInitial());
          }
          return;
        }
      } else {
        if (password == null || password.isEmpty) {
          emit(const ProfileError('Please enter your password to continue.'));
          return;
        }
        await authService.reauthenticateWithPassword(password);
      }
    } on FirebaseAuthException catch (e) {
      emit(ProfileError(_friendlyReauthError(e)));
      return;
    } catch (e) {
      emit(ProfileError(_friendlyReauthError(e)));
      return;
    }

    await _performDelete();
    emit(ProfileDeleteSuccess());
  }

  /// Tombstones the profile, releases the phone claim, then deletes the
  /// Firebase Auth user. Assumes the user is already re-authenticated.
  Future<void> _performDelete() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not found for deletion.");

    // First tombstone the profile document (red X + read-only everywhere
    // for contacts who still have this chat), then delete the Auth user.
    // The document is kept on purpose: it tells other apps this account
    // was deleted and lets a future re-registration reuse the phone.
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'fcmToken': FieldValue.delete(),
      });
    } catch (_) {}

    // Release the phone-number claim so the number can be re-registered.
    try {
      final profileDoc =
          await _firestore.collection('users').doc(user.uid).get();
      final phone = profileDoc.data()?['phoneNumber'] as String?;
      if (phone != null && phone.isNotEmpty) {
        await PhoneRegistry.instance.release(phone);
      }
    } catch (_) {}

    await user.delete();
  }

  String _friendlyDeleteError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'requires-recent-login':
          return 'For security, please sign in again before deleting your account.';
        case 'network-request-failed':
          return 'No internet connection. Please try again.';
        default:
          return 'We could not delete your account. Please try again.';
      }
    }
    return 'We could not delete your account. Please try again.';
  }

  String _friendlyReauthError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect password. Please try again.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a moment and try again.';
        default:
          return 'Could not verify your identity. Please try again.';
      }
    }
    return 'Could not verify your identity. Please try again.';
  }
}