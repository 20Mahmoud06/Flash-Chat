/// Metadata needed to reopen a minimized call's page (via the global
/// "call in progress" pill) and to rebuild the same Agora channel name.
class CallInfo {
  final bool isGroup;
  final bool isVideo;
  final String channelName;
  final String callId;

  /// 1:1 calls: uid of the other party (needed by [buildChannelName]).
  final String? peerUid;

  /// Group calls: the group id.
  final String? groupId;

  final String displayName;
  final String? avatarEmoji;

  /// Uid of the user who placed the call (needed to write the call-history
  /// message and to show the correct caller name to both participants).
  final String? callerId;

  const CallInfo({
    required this.isGroup,
    required this.isVideo,
    required this.channelName,
    required this.callId,
    this.peerUid,
    this.groupId,
    required this.displayName,
    this.avatarEmoji,
    this.callerId,
  });
}
