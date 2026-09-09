import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Display info (name + emoji avatar) of a call participant.
class CallParticipantInfo {
  final String name;
  final String? avatarEmoji;

  const CallParticipantInfo({required this.name, this.avatarEmoji});
}

/// Resolves the emoji avatars shown during voice / video calls:
/// the current user's own avatar and, for group calls, the avatar and
/// name of every member keyed by their Agora UID.
class CallAvatarLoader {
  static const String _defaultAvatar = '👤';

  /// The current user's own avatar emoji from Firestore.
  static Future<String?> loadOwnAvatar() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      return doc.data()?['avatarEmoji'] as String?;
    } catch (e) {
      debugPrint('Failed to load own avatar: $e');
      return null;
    }
  }

  /// Fetches every group member and maps their Agora UID to display info.
  static Future<Map<int, CallParticipantInfo>> loadGroupParticipants(
      String groupId) async {
    final result = <int, CallParticipantInfo>{};
    try {
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();
      final memberUids = List<String>.from(
          groupDoc.data()?['memberUids'] ?? const []);

      for (final uid in memberUids) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final data = doc.data() ?? {};
        final firstName = data['firstName'] as String? ?? '';
        final lastName = data['lastName'] as String? ?? '';
        final name = '$firstName $lastName'.trim();
        result[uid.hashCode & 0x7fffffff] = CallParticipantInfo(
          name: name.isEmpty ? 'Member' : name,
          avatarEmoji: data['avatarEmoji'] as String? ?? _defaultAvatar,
        );
      }
    } catch (e) {
      debugPrint('Failed to load group participants: $e');
    }
    return result;
  }
}
