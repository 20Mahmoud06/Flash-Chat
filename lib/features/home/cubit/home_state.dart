import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flash_chat_app/features/groups/models/group_model.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';

/// Immutable snapshot of everything the HomeScreen needs to render.
class HomeState extends Equatable {
  const HomeState({
    this.firstName,
    this.avatarEmoji,
    this.pinnedChatIds = const {},
    this.chats = const [],
    this.groups = const [],
    this.chatsLoading = false,
    this.chatsError,
    this.chatUsersLoading = false,
    this.chatUsersError,
    this.groupsLoading = false,
    this.groupsError,
  });

  final String? firstName;
  final String? avatarEmoji;

  /// Pin keys (canonical chat ids and group ids) taken from my user doc.
  final Set<String> pinnedChatIds;

  final List<HomeChatTileData> chats;
  final List<HomeGroupTileData> groups;

  final bool chatsLoading;
  final String? chatsError;

  /// True only while the very first contact batch is loading (no cached map).
  final bool chatUsersLoading;
  final String? chatUsersError;

  final bool groupsLoading;
  final String? groupsError;

  @override
  List<Object?> get props => [
        firstName,
        avatarEmoji,
        pinnedChatIds,
        chats,
        groups,
        chatsLoading,
        chatsError,
        chatUsersLoading,
        chatUsersError,
        groupsLoading,
        groupsError,
      ];
}

/// Everything a 1-1 chat row needs. The row widget itself still streams its
/// own last message + unread badge; this only carries what the home screen
/// computes from the chats / users / profile snapshots.
class HomeChatTileData extends Equatable {
  const HomeChatTileData({
    required this.chatDocId,
    required this.contactUid,
    required this.displayName,
    required this.avatar,
    required this.isSelfChat,
    required this.isBlocked,
    required this.isDeleted,
    required this.isNewChat,
    required this.isPinned,
    required this.pinId,
    required this.actionChatId,
    required this.unreadCount,
    required this.contact,
  });

  final String chatDocId;
  final String contactUid;

  /// My nickname for the contact if set, else "firstName lastName".
  final String displayName;
  final String avatar;
  final bool isSelfChat;
  final bool isBlocked;
  final bool isDeleted;
  final bool isNewChat;
  final bool isPinned;

  /// Canonical chat id; pin/unpin always target this so the pin survives the
  /// legacy-chat migration.
  final String pinId;

  /// Chat doc the delete actions target (canonical once it exists, else the
  /// picked latest doc).
  final String actionChatId;
  final int unreadCount;
  final UserModel contact;

  @override
  List<Object?> get props => [
        chatDocId,
        contactUid,
        displayName,
        avatar,
        isSelfChat,
        isBlocked,
        isDeleted,
        isNewChat,
        isPinned,
        pinId,
        actionChatId,
        unreadCount,
        contact,
      ];
}

/// Everything a group row needs. The unread count is computed by the row's
/// own message stream against the member's `lastSeen` watermark (written when
/// the group chat is opened), matching the 1-1 badge behavior.
class HomeGroupTileData extends Equatable {
  const HomeGroupTileData({
    required this.group,
    required this.unreadCount,
    required this.isPinned,
    this.lastSeenAt,
  });

  final GroupModel group;
  final int unreadCount;
  final bool isPinned;

  /// The member's last-read watermark (`groups/{id}.lastSeen.{uid}`); messages
  /// from others newer than this are unread. Null = never opened.
  final Timestamp? lastSeenAt;

  @override
  List<Object?> get props => [group, unreadCount, isPinned, lastSeenAt];
}