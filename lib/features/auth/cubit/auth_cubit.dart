import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/core/utils/friendly_error_messages.dart';
import 'package:flash_chat_app/features/auth/cubit/auth_state.dart';
import 'package:flash_chat_app/features/auth/services/auth.dart';
import 'package:flash_chat_app/features/auth/services/pending_signup_service.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthService _authService;
  AuthCubit(this._authService) : super(AuthInitial());

  static const accountExistsWithOtherMethodMessage =
      'An account already exists with this email. Please use the correct sign-in method.';

  /// Shown when the Auth SDK confirms no account exists for the address the
  /// user typed on the forgot-password screen.
  static const noAccountMessage =
      'No account was found with this email. Please sign up first.';

  Future<void> checkAuthStatus() async {
    await Future.delayed(const Duration(seconds: 1));
    await _restoreSession();
  }

  /// Resolves the signed-in user on cold start.
  ///
  /// The outcome is one of three things:
  /// - a completed profile → [AuthLoggedIn] → Home, no onboarding gate. This
  ///   covers every established account, whether it signed up with Google or
  ///   email/password, and every legacy account sitting on a name-less
  ///   push-token shell document.
  /// - an account created on this device whose sign-up was never finished →
  ///   [AuthNeedsProfile] → Home *with* a "Complete Profile" / "Complete OTP"
  ///   button, never the auth screen.
  /// - no session at all → [AuthLoggedOut] → the auth screen.
  ///
  /// Fresh logins deliberately skip this and emit [AuthLoggedIn] with the user
  /// model already fetched inside the sign-in call. Right after a sign-in the
  /// very first Firestore read can fail on a fresh emulator (auth
  /// propagation), and re-reading the doc here would send an existing user
  /// back to "complete profile". [AuthService.readUserDocument]'s retry
  /// handles the propagation delay on this cold-start path instead.
  Future<void> _restoreSession() async {
    if (isClosed) return;
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      emit(AuthLoggedOut());
      return;
    }

    // FAST PATH. A completed profile is cached locally on every successful
    // read (AuthService.rememberProfile), so an established account can be
    // restored from disk in milliseconds instead of waiting on Firestore.
    //
    // This must not block on the network: the splash screen has a watchdog, and
    // a restore that only resolves once several read timeouts have elapsed gets
    // force-routed to the welcome screen, throwing away a perfectly valid
    // session. The server is still consulted (below) so the destination stays
    // authoritative — it just no longer gates the first frame.
    final cached = await _authService.lastKnownProfile(currentUser.uid);
    if (isClosed) return;
    if (cached != null && cached.isProfileComplete) {
      if (!isClosed) emit(AuthLoggedIn(cached));
      // Revalidate behind the restored session. If the account actually turned
      // out to owe onboarding (e.g. the marker write landed late), correct the
      // destination now that the user is already in the app.
      unawaited(_revalidateSession(currentUser.uid, cached));
      return;
    }

    // No exception may ever escape here: a cold-start crash (or a splash
    // that never resolves) would brick the app for a user who closed it on
    // the "complete profile" / "verify phone number" screens. Every failure
    // falls back to an error state, which lands on the auth screen.
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
        debugPrint(
            'Firestore unreachable on cold start for ${currentUser.uid}');
        if (!isClosed) {
          emit(const AuthError(
            'Could not connect to server. Please check your connection and try again.',
          ));
        }
        return;
      }

      final userModel = doc.exists ? UserModel.fromFirestore(doc) : null;

      // A document without a name is NOT enough to conclude "sign-up
      // unfinished": the push services create a name-less shell document
      // (`{fcmTokens: [...]}`) the instant an auth account is made, so that is
      // also the shape of every legacy account that predates the OTP flow.
      // The `onboardingPending` marker WE write at sign-up is what actually
      // separates the two, and because it lives in the cloud it survives a
      // wiped secure store, a reinstall and a sign-in on another device.
      final onboardingPending =
          doc.get(AuthService.onboardingPendingField) == true;

      // The marker is written best-effort at sign-up, so an offline or denied
      // write can lose it. The uid-scoped draft is the fallback that keeps such
      // an account out of an empty Home: it only exists for accounts that were
      // mid-sign-up here. Awaited (a local read) so the decision is made with
      // the value in hand rather than racing it.
      final hasLocalDraft =
          await PendingSignupService.instance.loadFor(currentUser.uid) != null;

      final destination = resolveSessionDestination(
        docExists: doc.exists,
        profileComplete: userModel?.isProfileComplete ?? false,
        onboardingPending: onboardingPending,
        hasLocalDraft: hasLocalDraft,
      );

      if (destination == SessionDestination.needsProfile) {
        // A local draft is loaded only to tell the auth screen WHICH button to
        // offer (profile vs OTP) — never to decide this routing, which is why
        // losing the draft can no longer leak an unfinished account into an
        // empty Home.
        unawaited(PendingSignupService.instance.loadFor(currentUser.uid));
        if (!isClosed) emit(AuthNeedsProfile(currentUser));
        return;
      }

      // Home. A completed profile is cached so the splash screen can render
      // immediately next launch; a stale draft is dropped so the user who
      // finished on another device never sees a resume button.
      if (userModel != null && userModel.isProfileComplete) {
        unawaited(PendingSignupService.instance.clear());
        unawaited(_authService.rememberProfile(userModel));
      }
      if (!isClosed) emit(AuthLoggedIn(userModel!));
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

  /// Second pass behind [_restoreSession]'s fast path.
  ///
  /// The user has already been admitted Home from the locally cached profile;
  /// this confirms against the server that the account really is complete and,
  /// if it is not, corrects the destination. Failures are swallowed on purpose:
  /// the cached profile is a legitimate answer, so an unreachable Firestore
  /// must never bounce an already-restored user back out to the auth screen.
  Future<void> _revalidateSession(String uid, UserModel cached) async {
    if (isClosed) return;
    try {
      final doc = await _authService.readUserDocument(uid);
      if (isClosed || doc == null) return;
      if (!doc.exists) return;

      if (doc.get(AuthService.onboardingPendingField) == true) {
        // The account is genuinely mid-onboarding (the marker write landed
        // after the profile was cached). Send it back to the resume flow.
        if (!isClosed) emit(AuthNeedsProfile(_authService.currentUser!));
        return;
      }

      final fresh = UserModel.fromFirestore(doc);
      if (!fresh.isProfileComplete) return;
      unawaited(PendingSignupService.instance.clear());
      unawaited(_authService.rememberProfile(fresh));
      // Only re-emit when something actually changed, so an identical profile
      // does not push a redundant AuthLoggedIn through the whole tree.
      if (!isClosed && fresh != cached) emit(AuthLoggedIn(fresh));
    } catch (e) {
      debugPrint('Session revalidation skipped for $uid: $e');
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
      if (methods != null &&
          methods.isNotEmpty &&
          !methods.contains('password')) {
        emit(const AuthError(accountExistsWithOtherMethodMessage));
        return;
      }

      final user =
          await _authService.signInWithEmailAndPassword(email, password);

      if (user == null) {
        emit(const AuthError('Error, please try again.'));
      } else {
        if (!isClosed) emit(AuthLoggedIn(user));
      }
    } catch (e) {
      emit(AuthError(friendlyErrorMessage(e)));
    }
  }

  /// Signs in with Google.
  ///
  /// [isSignUp] is true only when the Sign Up screen triggered it. A Google
  /// account reached from the *Log In* screen is an established user and must
  /// never be pushed back through onboarding, so the two callers are told
  /// apart here rather than guessed at from the resulting profile.
  Future<void> loginWithGoogle({bool isSignUp = false}) async {
    emit(AuthLoading());
    try {
      final user = await _authService.signInWithGoogle();

      if (user == null) {
        // null only means the user cancelled the Google sheet: do not treat
        // it as a failure, just stay on the current screen.
        return;
      }
      if (isSignUp) unawaited(_startOnboardingIfIncomplete(user));
      if (!isClosed) emit(AuthLoggedIn(user));
    } catch (e) {
      emit(AuthError(friendlyErrorMessage(e)));
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    emit(AuthLoading());
    try {
      final user =
          await _authService.createUserWithEmailAndPassword(email, password);

      if (user == null) {
        emit(const AuthError('Error, please try again.'));
      } else {
        unawaited(_startOnboardingIfIncomplete(user));
        if (!isClosed) emit(AuthLoggedIn(user));
      }
    } catch (e) {
      emit(AuthError(friendlyErrorMessage(e)));
    }
  }

  /// Records that a freshly created account still owes us a profile and a
  /// verified phone number, so a later cold start can tell it apart from an
  /// established account instead of dropping it into an empty Home.
  ///
  /// Two records are written, on purpose, because they fail differently:
  /// - the cloud `onboardingPending` marker is the AUTHORITATIVE signal for
  ///   routing. It survives a reinstall, a wiped secure store and a sign-in on
  ///   another device.
  /// - the on-phone draft is only a convenience, recording WHICH step to
  ///   resume at (profile vs OTP). Losing it costs a less specific button, not
  ///   a wrong destination.
  ///
  /// Only ever called on the sign-up path: an account that already has a
  /// completed profile is an existing user and is left alone.
  Future<void> _startOnboardingIfIncomplete(UserModel user) async {
    if (user.isProfileComplete) return;
    unawaited(_authService.markOnboardingPending(user.uid));
    try {
      await PendingSignupService.instance.save(PendingSignup.atProfile(
        uid: user.uid,
        firstName: user.firstName,
        lastName: user.lastName,
      ));
    } catch (e) {
      // Losing the draft only costs the user the ability to *resume*; the
      // sign-up itself still works from the complete-profile screen.
      debugPrint('Could not save onboarding draft: $e');
    }
  }

  Future<void> resetPassword(String email) async {
    emit(AuthLoading());
    try {
      // `sendPasswordResetEmail` reports success even for addresses that have
      // no account (Firebase hides account existence on this endpoint), so
      // the pre-check is what lets us tell the user "no account with this
      // email" instead of a link that will never arrive.
      //
      // REQUIRES email enumeration protection to be OFF for this project:
      // Firebase console → Authentication → Settings → User account
      // management → User actions → "Email enumeration protection" → Clear →
      // Save. With it left ON, `fetchSignInMethodsForEmail` returns an empty
      // list for EVERY address and this branch rejects every user.
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
    // The draft belongs to the account that just signed out, so it must not
    // survive into the next session and offer to resume someone else's
    // half-finished sign-up.
    unawaited(PendingSignupService.instance.clear());
    emit(AuthLoggedOut());
  }
}
