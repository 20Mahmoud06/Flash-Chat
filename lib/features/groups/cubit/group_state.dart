import 'package:equatable/equatable.dart';
import '../models/group_model.dart';
import '../../profile/models/user_model.dart';

abstract class GroupState extends Equatable {
  const GroupState();

  @override
  List<Object?> get props => [];
}

class GroupInitial extends GroupState {}

class GroupLoading extends GroupState {}

class GroupCreating extends GroupState {}

class GroupCreated extends GroupState {
  final GroupModel group;

  const GroupCreated(this.group);

  @override
  List<Object?> get props => [group];
}

class GroupUpdating extends GroupState {}

class GroupUpdated extends GroupState {
  final GroupModel group;

  const GroupUpdated(this.group);

  @override
  List<Object?> get props => [group];
}

class GroupMembersLoaded extends GroupState {
  final GroupModel group;
  final List<UserModel> members;
  final bool isAdmin;

  const GroupMembersLoaded({
    required this.group,
    required this.members,
    required this.isAdmin,
  });

  @override
  List<Object?> get props => [group, members, isAdmin];
}

class GroupError extends GroupState {
  final String message;

  const GroupError(this.message);

  @override
  List<Object?> get props => [message];
}

class GroupMemberRemoved extends GroupState {}

/// Emitted after the creator deletes the whole group. The group becomes
/// read-only for everyone but stays readable, so the UI just closes the
/// info screen and lets the live group-doc listener flip the chat to
/// read-only mode.
class GroupDeleted extends GroupState {}