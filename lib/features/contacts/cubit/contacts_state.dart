import 'package:equatable/equatable.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';

/// Immutable snapshot of everything the ContactsScreen needs to render.
class ContactsState extends Equatable {
  const ContactsState({
    this.isLoading = true,
    this.errorMessage = '',
    this.contacts = const [],
    this.myBlockedUids = const {},
    this.isSelectionMode = false,
    this.selectedContacts = const {},
    this.searchQuery = '',
  });

  final bool isLoading;
  final String errorMessage;

  /// App contacts matched from the phone book, always starting with the
  /// current user's own model (when present).
  final List<UserModel> contacts;

  /// Uids I have blocked, live-tracked from my user document so the Blocked
  /// chip reacts immediately when I unblock from anywhere.
  final Set<String> myBlockedUids;

  final bool isSelectionMode;
  final Set<UserModel> selectedContacts;
  final String searchQuery;

  ContactsState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<UserModel>? contacts,
    Set<String>? myBlockedUids,
    bool? isSelectionMode,
    Set<UserModel>? selectedContacts,
    String? searchQuery,
  }) {
    return ContactsState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      contacts: contacts ?? this.contacts,
      myBlockedUids: myBlockedUids ?? this.myBlockedUids,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      selectedContacts: selectedContacts ?? this.selectedContacts,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        errorMessage,
        contacts,
        myBlockedUids,
        isSelectionMode,
        selectedContacts,
        searchQuery,
      ];
}