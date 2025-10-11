import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'profile_state.dart';

class ProfileCubit extends Cubit<ProfileState> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  ProfileCubit() : super(ProfileInitial());

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
  }) async {
    emit(ProfileLoading());
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception("No user is currently signed in.");

      // Check if phone number already exists
      final query = await _firestore
          .collection('users')
          .where('phoneNumber', isEqualTo: phoneNumber)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        throw Exception('This phone number is already registered.');
      }

      final userModel = UserModel(
        uid: user.uid,
        email: user.email!,
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        avatarEmoji: '👤',
      );

      await _firestore.collection('users').doc(user.uid).set(userModel.toMap());
      emit(const ProfileUpdateSuccess("Profile completed successfully!"));
    } catch (e) {
      emit(ProfileError(e.toString().replaceFirst("Exception: ", "")));
    }
  }

  // --- UPDATE EXISTING PROFILE ---
  Future<void> updateUserProfile({
    required UserModel originalUser,
    required String newFirstName,
    required String newLastName,
    required String newPhone,
    required String newEmail,
    String? newEmoji,
  }) async {
    emit(ProfileLoading());
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception("User not authenticated");

      final firestoreUpdates = <String, dynamic>{};
      bool emailUpdateInitiated = false;

      // Check for changes and build the update map
      if (newFirstName != originalUser.firstName) firestoreUpdates['firstName'] = newFirstName;
      if (newLastName != originalUser.lastName) firestoreUpdates['lastName'] = newLastName;
      if (newEmoji != null && newEmoji != originalUser.avatarEmoji) firestoreUpdates['avatarEmoji'] = newEmoji;

      // Validate and add phone number if changed
      if (newPhone != originalUser.phoneNumber) {
        final phoneQuery = await _firestore.collection('users').where('phoneNumber', isEqualTo: newPhone).limit(1).get();
        if (phoneQuery.docs.isNotEmpty) {
          throw Exception("This phone number is already in use.");
        }
        firestoreUpdates['phoneNumber'] = newPhone;
      }

      // Initiate email update if changed
      if (newEmail != originalUser.email) {
        await user.verifyBeforeUpdateEmail(newEmail);
        emailUpdateInitiated = true;
      }

      if (firestoreUpdates.isEmpty && !emailUpdateInitiated) {
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
      final user = _auth.currentUser;
      if (user == null) throw Exception("User not found for deletion.");

      // First delete Firestore document, then delete Auth user
      await _firestore.collection('users').doc(user.uid).delete();
      await user.delete();

      emit(ProfileDeleteSuccess());
    } catch (e) {
      emit(ProfileError("Failed to delete account: $e"));
    }
  }
}
