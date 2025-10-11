import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/auth.dart';
import 'auth_state.dart';

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

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (userDoc.exists &&
          userDoc.data()?['firstName'] != null &&
          userDoc.data()?['firstName'].isNotEmpty) {

        final userModel = await _authService.getUserById(currentUser.uid);
        emit(AuthLoggedIn(userModel));
      } else {
        emit(AuthNeedsProfile(currentUser));
      }
    } catch (e) {
      emit(AuthLoggedOut());
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
