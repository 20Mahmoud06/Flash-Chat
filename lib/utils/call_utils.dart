import 'package:firebase_auth/firebase_auth.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';

String buildChannelName({
  required bool isGroup,
  GroupModel? group,
  String? groupId,
  UserModel? contact,
  String? otherUid,
}) {
  final currentUserId = FirebaseAuth.instance.currentUser!.uid;

  if (isGroup) {
    final id = group?.id ?? groupId;
    if (id == null) throw Exception("Group ID required for group call");
    return "group_$id";
  } else {
    final peerId = contact?.uid ?? otherUid;
    if (peerId == null) throw Exception("Peer ID required for 1-1 call");
    final ids = [currentUserId, peerId]..sort();
    return "chat_${ids.join('_')}";
  }
}