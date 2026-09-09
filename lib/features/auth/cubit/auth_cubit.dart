import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/features/auth/cubit/auth_state.dart';
import 'package:flash_chat_app/services/auth/auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthService _authService;
  AuthCubit(this._authService) : super(AuthInitial());

  Future<void> checkAuthStatus() async {
    await Future.delayed(const Duration(seconds: 1));

    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      emit(AuthLoggedOut());
      return;
    }

    // No exception may ever escape here: a cold-start crash (or a splash
    // that never resolves) would brick the app for a user who closed it on
    // the "complete profile" / "verify phone number" screens. Every failure
    // falls back to AuthNeedsProfile / AuthLoggedOut, which land on the
    // auth screen offering Sign In, Sign Up, Verify Phone or Sign Out.
    try {
      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);

      // Normal read (server first, falls back to the on-device cache). When
      // that fails entirely (offline with no cache), retry from the local
      // cache so a signed-in user can still open the app and read chats.
      DocumentSnapshot userDoc;
      try {
        userDoc = await userDocRef.get();
      } catch (_) {
        try {
          userDoc =
              await userDocRef.get(const GetOptions(source: Source.cache));
        } catch (_) {
          // Cannot reach Firestore at all and there is no cached doc: we
          // cannot tell whether the profile exists, so treat the session as
          // unknown (logged out) — stale deep links must not fire either.
          emit(AuthLoggedOut());
          return;
        }
      }

      final data =
          userDoc.exists ? userDoc.data() as Map<String, dynamic>? : null;
      if (userDoc.exists && (data?['firstName'] as String? ?? '').isNotEmpty) {
        final userModel = await _authService.getUserById(currentUser.uid);
        emit(AuthLoggedIn(userModel));
      } else {
        // Auth account exists but the profile was never completed (closed
        // the app on the OTP verify or complete profile screen): offer to
        // resume exactly where the user left off.
        emit(AuthNeedsProfile(currentUser));
      }
    } catch (e) {
      debugPrint('checkAuthStatus failed, falling back to auth screen: $e');
      if (!isClosed) emit(AuthNeedsProfile(currentUser));
    }
  }

  Future<void> loginWithEmail(String email, String password) async {
    emit(AuthLoading());
    try {
      final user = await _authService.signInWithEmailAndPassword(email, password);

      if (user == null) {
        emit(const AuthError("Error, please try again."));
      } else {
        emit(AuthLoggedIn(user));
      }
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> loginWithGoogle() async {
    emit(AuthLoading());
    try {
      final user = await _authService.signInWithGoogle();

      if (user == null) {
        emit(const AuthError("Error, please try again."));
      } else {
        emit(AuthLoggedIn(user));
      }
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    emit(AuthLoading());
    try {
      final user = await _authService.createUserWithEmailAndPassword(email, password);

      if (user == null) {
        emit(const AuthError("Error, please try again."));
      } else {
        emit(AuthLoggedIn(user));
      }
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> resetPassword(String email) async {
    emit(AuthLoading());
    try {
      await _authService.sendPasswordResetEmail(email);
      emit(AuthPasswordResetSent());
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> logout() async {
    await _authService.signOut();
    emit(AuthLoggedOut());
  }
}
