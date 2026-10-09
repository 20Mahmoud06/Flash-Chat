import 'package:equatable/equatable.dart';

/// Immutable snapshot of the sender/contact-info screen: my nickname and block
/// state for the viewed contact. All of it lives on my own user doc.
class SenderProfileState extends Equatable {
  const SenderProfileState({
    this.loading = true,
    this.isBlocked = false,
    this.blockedMe = false,
    this.myNickname,
  });

  final bool loading;

  /// Whether I have blocked the contact.
  final bool isBlocked;

  /// Whether the contact has blocked me.
  final bool blockedMe;

  final String? myNickname;

  SenderProfileState copyWith({
    bool? loading,
    bool? isBlocked,
    bool? blockedMe,
    String? Function()? myNickname,
  }) {
    return SenderProfileState(
      loading: loading ?? this.loading,
      isBlocked: isBlocked ?? this.isBlocked,
      blockedMe: blockedMe ?? this.blockedMe,
      myNickname: myNickname != null ? myNickname() : this.myNickname,
    );
  }

  @override
  List<Object?> get props => [
        loading,
        isBlocked,
        blockedMe,
        myNickname,
      ];
}