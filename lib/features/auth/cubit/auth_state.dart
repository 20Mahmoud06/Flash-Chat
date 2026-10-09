import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../profile/models/user_model.dart';

abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

/// Where a restored session should be sent on a cold start.
enum SessionDestination {
  /// Fully set up: open Home.
  home,

  /// Still owes a profile and/or a verified phone number: open the auth
  /// screen so it can offer to resume.
  needsProfile,
}

/// The single source of truth for cold-start routing, extracted from the cubit
/// so the precedence rules can be pinned by tests.
///
/// The order is load-bearing and was the source of a real bug — an account that
/// quit the app while waiting for its sign-up code used to be dropped into an
/// empty Home:
///
/// 1. [onboardingPending] beats everything. The profile document is written to
///    Firestore *before* the code is sent, so a user waiting on a code already
///    has a name and looks "profile complete". The marker — written at sign-up,
///    cleared only when the code is verified — is the only signal that
///    distinguishes them.
/// 2. A completed profile then means Home.
/// 3. A missing document means the account still needs onboarding.
/// 4. A document with no name and no marker is a legacy account that predates
///    the OTP flow. Its existence proves the account is real, so it goes Home
///    like any other sign-in; sending it back to onboarding would lock
///    established users out of the app.
/// 5. [hasLocalDraft] is a last-resort signal for an account whose marker write
///    failed (it is best-effort, so an offline or denied write loses it). A
///    draft only ever exists for an account that was mid-sign-up on this device,
///    and it is uid-scoped, so treating it as "owes onboarding" can only
///    misroute an account that was genuinely never finished — never a completed
///    one, whose draft is cleared on success and on logout.
///
/// Checked AFTER [profileComplete] on purpose: the profile step re-asserts the
/// marker in the same transaction that writes it, so an account waiting on its
/// code is already covered by rule 1. Were the draft to override rule 2 as well,
/// a stale draft left behind by a completed account would drag that user back
/// out of Home.
SessionDestination resolveSessionDestination({
  required bool docExists,
  required bool profileComplete,
  required bool onboardingPending,
  bool hasLocalDraft = false,
}) {
  if (onboardingPending) return SessionDestination.needsProfile;
  if (profileComplete) return SessionDestination.home;
  if (!docExists) return SessionDestination.needsProfile;
  if (hasLocalDraft) return SessionDestination.needsProfile;
  return SessionDestination.home;
}

class AuthNeedsProfile extends AuthState {
  final User user;
  const AuthNeedsProfile(this.user);

  @override
  List<Object?> get props => [user];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthLoggedIn extends AuthState {
  final UserModel user;
  const AuthLoggedIn(this.user);

  @override
  List<Object?> get props => [user];
}

class AuthPasswordResetSent extends AuthState {}

class AuthLoggedOut extends AuthState {}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}
