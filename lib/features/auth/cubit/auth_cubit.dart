import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/core/utils/friendly_error_messages.dart';
import 'package:flash_chat_app/features/auth/cubit/auth_state.dart';
import 'package:flash_chat_app/features/auth/services/auth.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthService _authService;
  AuthCubit(this._authService) : super(AuthInitial());

  /// Shown when no account exists for the email the user typed. The Auth
  /// SDK returns the same "invalid credentials" error for a missing email
  /// and for a wrong password (anti-enumeration), so this is decided by a
  /// `fetchSignInMethodsForEmail` check BEFORE the actual sign-in request.
  static const noAccountMessage =
      'No account was found with this email. Please sign up first.';

  static const accountExistsWithOtherMethodMessage =
      'An account already exists with this email. Please use the correct sign-in method.';

  Future<void> checkAuthStatus() async {
    await Future.delayed(const Duration(seconds: 1));
    await _restoreSession();
  }

  /// Resolves the signed-in user on cold start: a completed profile (a
  /// document with a name) goes home, anything else — missing document or a
  /// push-token shell with no name — resumes on the auth screen so the
  /// interrupted sign-up/OTP flow can continue.
  ///
  /// Fresh logins deliberately skip this and emit [AuthLoggedIn] with the
  /// user model already fetched inside the sign-in call. Right after a
  /// sign-in the very first Firestore read can fail on a fresh emulator
  /// (auth propagation), and re-reading the doc here would send an existing
  /// user back to "complete profile" (or fall through to a sign-out).
  /// [AuthService.readUserDocument]'s retry handles the propagation delay on
  /// this cold-start path instead.
  Future<void> _restoreSession() async {
    if (isClosed) return;
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      emit(AuthLoggedOut());
      return;
    }

    // No exception may ever escape here: a cold-start crash (or a splash
    // that never resolves) would brick the app for a user who closed it on
    // the "complete profile" / "verify phone number" screens. Every failure
    // falls back to AuthNeedsProfile, which lands on the auth screen
    // offering Sign In, Sign Up, Verify Phone or Sign Out.
    try {
      final doc = await _authService.readUserDocument(currentUser.uid);

      if (doc == null) {
        // Firestore unreachable (both server + cache failed). Do NOT emit
        // AuthNeedsProfile: the user HAS a profile, we just can't reach
        // Firestore right now. Fall back to the previously-known profile so
        // an existing user still lands home; otherwise show a retry prompt
        // instead of routing to "Complete Profile".
        final known = await _authService.lastKnownProfile(currentUser.uid);
        if (known != null) {
          if (!isClosed) emit(AuthLoggedIn(known));
          return;
        }
        debugPrint('Firestore unreachable on cold start for ${currentUser.uid}');
        if (!isClosed) {
          emit(const AuthError(
            'Could not connect to server. Please check your connection and try again.',
          ));
        }
        return;
      }

      if (!doc.exists) {
        // Auth account exists but no profile document — needs completion.
        if (!isClosed) emit(AuthNeedsProfile(currentUser));
        return;
      }

      // Document exists — parse it directly (avoids the extra round-trip
      // of getUserById which can fail on its own).
      final userModel = UserModel.fromFirestore(doc);

      if (!userModel.isProfileComplete) {
        // The FCM/HMS push services merge a name-less shell doc
        // (`{fcmTokens: [...]}`) the moment the auth account is created, and
        // the OTP flow that writes the name never ran for legacy pre-OTP
        // accounts. An EXISTING document proves the account is real, so it
        // must land Home like any other sign-in — routing it back to the auth
        // screen would force the "close and reopen to reach Home" restart bug.
        // Only a genuinely ABSENT document means the sign-up/OTP flow is still
        // in progress (see the `!doc.exists` branch above).
        if (!isClosed) emit(AuthLoggedIn(userModel));
        return;
      }

      unawaited(_authService.rememberProfile(userModel));
      if (!isClosed) emit(AuthLoggedIn(userModel));
    } catch (e) {
      debugPrint('Reading profile failed, offering auth screen: $e');
      // Parsing or network error: show an error message instead of
      // silently routing to "Complete Profile" (which would lose the
      // user's existing account data).
      if (!isClosed) {
        emit(const AuthError(
          'Failed to load your profile. Please try again.',
        ));
      }
    }
  }

  /// Server-authoritative post-sign-in re-check: ANY existing user document
  /// counts as a completed account (the user goes Home). Legacy pre-OTP
  /// accounts legitimately sit on a name-less push-token shell doc — the
  /// push services create one for every auth account and the OTP flow (which
  /// writes the name) never ran for them — and they must still land Home.
  /// Only a genuinely ABSENT document (a brand-new sign-up mid-flow) returns
  /// null so the profile is completed.
  ///
  /// Used by the login screen when the freshly-fetched profile came back with
  /// an empty name, so an existing user is never bounced into "Complete
  /// Profile" just because the sign-in snapshot raced the profile write or a
  /// cache shell was read — the exact bug that otherwise needs an app restart.
  Future<UserModel?> resolvePostSignIn(String uid) async {
    // A completed profile already known for this account (memory/persisted)
    // means the sign-in snapshot raced the profile write or read a stale
    // cache shell — an existing user who must go Home, never be stuck on
    // "Complete Profile".
    final known = await _authService.lastKnownProfile(uid);
    if (known != null) return known;

    try {
      final doc = await _authService.readUserDocumentAuthoritative(uid);
      if (doc != null && doc.exists) {
        final user = UserModel.fromFirestore(doc);
        // Document exists ⇒ the account is real. Remember it when the profile
        // is complete (so later sign-ins go Home even offline); name-less
        // legacy shells still return so they land Home.
        if (user.isProfileComplete) {
          unawaited(_authService.rememberProfile(user));
        } else {
          debugPrint('resolvePostSignIn: legacy shell doc (no name) for $uid');
        }
        return user;
      }
    } catch (e) {
      debugPrint('resolvePostSignIn failed for $uid, using cache: $e');
    }
    return null;
  }

  Future<void> loginWithEmail(String email, String password) async {
    emit(AuthLoading());
    try {
      // Distinguish "email doesn't exist" from "wrong password" BEFORE the
      // sign-in attempt: the Auth SDK deliberately returns the same
      // `invalid-credential` for both to prevent account enumeration.
      //
      // IMPORTANT: only a NON-EMPTY result is definitive. When the project
      // enables email enumeration protection, `fetchSignInMethodsForEmail`
      // deliberately returns an EMPTY list for EVERY address (existing and
      // not) so it can't be used to tell whether an account exists. An empty
      // list must never be treated as "no account" or existing users are
      // locked out ("normal login" failing while Google Sign-In works).
      // Null/empty ⇒ unknown ⇒ fall through to the real sign-in.
      final methods = await _authService.fetchSignInMethodsForEmail(email);
      if (methods != null && methods.isNotEmpty && !methods.contains('password')) {
        emit(const AuthError(accountExistsWithOtherMethodMessage));
        return;
      }

      final user = await _authService.signInWithEmailAndPassword(email, password);

      if (user == null) {
        emit(const AuthError('Error, please try again.'));
      } else {
        if (!isClosed) emit(AuthLoggedIn(user));
      }
    } catch (e) {
      emit(AuthError(friendlyErrorMessage(e)));
    }
  }

  Future<void> loginWithGoogle() async {
    emit(AuthLoading());
    try {
      final user = await _authService.signInWithGoogle();

      if (user == null) {
        // null only means the user cancelled the Google sheet: do not treat
        // it as a failure, just stay on the current screen.
        return;
      }
      if (!isClosed) emit(AuthLoggedIn(user));
    } catch (e) {
      emit(AuthError(friendlyErrorMessage(e)));
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    emit(AuthLoading());
    try {
      final user = await _authService.createUserWithEmailAndPassword(email, password);

      if (user == null) {
        emit(const AuthError('Error, please try again.'));
      } else {
        if (!isClosed) emit(AuthLoggedIn(user));
      }
    } catch (e) {
      emit(AuthError(friendlyErrorMessage(e)));
    }
  }

  Future<void> resetPassword(String email) async {
    emit(AuthLoading());
    try {
      // `sendPasswordResetEmail` returns success even for emails that do
      // not exist (anti-enumeration), which would make the user believe a
      // reset link was sent to a non-existent account. Verify first; a null
      // lookup ("unknown") falls back to the plain reset as before.
      final methods = await _authService.fetchSignInMethodsForEmail(email);
      if (methods != null && methods.isEmpty) {
        emit(const AuthError(noAccountMessage));
        return;
      }

      await _authService.sendPasswordResetEmail(email);
      emit(AuthPasswordResetSent());
    } catch (e) {
      emit(AuthError(friendlyErrorMessage(e)));
    }
  }

  Future<void> logout() async {
    await _authService.signOut();
    try {
      await FirebaseFirestore.instance.clearPersistence();
    } catch (_) {}
    emit(AuthLoggedOut());
  }
}