import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/user_model.dart';

abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
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
