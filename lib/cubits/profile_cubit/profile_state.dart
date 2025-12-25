import 'package:equatable/equatable.dart';
import '../../models/user_model.dart';

abstract class ProfileState extends Equatable {
  const ProfileState();
  @override
  List<Object?> get props => [];
}

class ProfileInitial extends ProfileState {}

class ProfileLoading extends ProfileState {}

class ProfileLoaded extends ProfileState {
  final UserModel user;
  const ProfileLoaded(this.user);

  @override
  List<Object?> get props => [user];
}

class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}

// Specific success state for updates to show a confirmation
class ProfileUpdateSuccess extends ProfileState {
  final String message;
  const ProfileUpdateSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

// Specific state for successful logout to trigger navigation
class ProfileLogoutSuccess extends ProfileState {}

// Specific state for successful deletion to trigger navigation
class ProfileDeleteSuccess extends ProfileState {}