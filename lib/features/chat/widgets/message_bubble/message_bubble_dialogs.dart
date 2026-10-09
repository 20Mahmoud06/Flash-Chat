import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_text.dart';
import '../../../profile/models/user_model.dart';
import '../../cubit/chat_cubit.dart';
import '../../models/message_model.dart';
import 'group_message_seen.dart';

/// Bottom sheet letting the user pick how long a message stays pinned
/// (1 / 7 / 30 days), then pins it through the chat cubit.
void showMessagePinDurationPicker(BuildContext context, MessageModel message) {
  final chatCubit = context.read<ChatCubit>();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final colors = FcAppColors.of(ctx);
      return Container(
        margin: EdgeInsets.all(8.w),
        decoration: BoxDecoration(
            color: colors.surface, borderRadius: BorderRadius.circular(15.r)),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(16.w),
                child: CustomText(
                  text: 'Pin message for',
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(height: 1),
              for (final (label, duration) in [
                ('1 day', const Duration(days: 1)),
                ('7 days', const Duration(days: 7)),
                ('30 days', const Duration(days: 30)),
              ])
                ListTile(
                  leading: Icon(Icons.schedule, color: colors.textSecondary),
                  title: CustomText(text: label),
                  onTap: () {
                    Navigator.pop(ctx);
                    chatCubit.pinMessage(message, duration);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Full emoji keyboard in a bottom sheet; fires the callback once chosen.
void showMessageEmojiPicker(
    BuildContext context, void Function(String) onEmojiSelected) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) {
          onEmojiSelected(emoji.emoji);
          Navigator.pop(context);
        },
      ),
    ),
  );
}

/// Delivery status + full timestamp of a message.
///
/// Group messages don't carry per-message read state, so this dialog computes
/// "seen" from the group doc: members whose `lastSeen` watermark passed the
/// message timestamp are listed ("Seen by <name> …"). When every member who
/// was in the group at send time has read it, the dialog (and the bubble
/// tick) flip to the blue double-tick, same as a 1:1 "seen".
void showMessageInfoDialog(
  BuildContext context,
  MessageModel message, {
  bool isGroup = false,
  Map<String, UserModel> members = const {},
}) {
  String statusText = "Sent";
  IconData statusIcon = Icons.done;
  Color statusColor = Colors.grey;

  // Computed here (caller's context, which has ChatCubit) and passed into the
  // dialog: the dialog route lives under the root navigator, where the
  // chat-route's ChatCubit provider is out of scope.
  final seenBy = <GroupMessageSeenByEntry>[];

  if (message.status == 'pending') {
    statusText = "Pending";
    statusIcon = Icons.schedule;
    statusColor = Colors.orange;
  } else if (isGroup) {
    final chatCubit = context.read<ChatCubit>();
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) {
      seenBy.clear();
    } else {
      seenBy
        ..clear()
        ..addAll(groupMessageSeenBy(
          message: message,
          members: members,
          memberLastSeen: chatCubit.memberLastSeenNotifier.value,
          memberJoinTimestamps: chatCubit.memberJoinTimestamps,
          myUid: myUid,
        ));
      final total = groupMessageSeenTotal(
        message: message,
        members: members,
        memberJoinTimestamps: chatCubit.memberJoinTimestamps,
        myUid: myUid,
      );
      if (seenBy.isNotEmpty && total > 0) {
        statusText = seenBy.length >= total
            ? "Seen by everyone"
            : seenBy.length == 1
                ? "Seen by ${seenBy.first.user.fullName}"
                : "Seen by "
                    "${seenBy.map((e) => e.user.fullName).join(', ')}";
        statusIcon = Icons.done_all;
        statusColor = Colors.blue;
      }
    }
  } else if (message.status == 'delivered') {
    statusText = "Delivered";
    statusIcon = Icons.done_all;
  } else if (message.status == 'seen') {
    statusText = "Seen";
    statusIcon = Icons.done_all;
    statusColor = Colors.blue;
  }

  final sentAt = intl.DateFormat.yMMMd()
      .add_jm()
      .format(message.timestamp.toDate());

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
      title: CustomText(
          text: "Message Info",
          fontWeight: FontWeight.bold,
          textColor: FcAppColors.of(context).textPrimary),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(statusIcon, color: statusColor),
            title: CustomText(text: statusText),
            subtitle: CustomText(text: sentAt),
          ),
          if (isGroup) ..._buildGroupSeenTiles(context, seenBy),
        ],
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.lightBlueAccent),
          onPressed: () => Navigator.of(context).pop(),
          child: const CustomText(
              text: "OK",
              fontWeight: FontWeight.bold,
              textColor: Colors.white),
        ),
      ],
    ),
  );
}

/// One compact row per group member who saw the message: their name and the
/// exact time they read it. Falls back to an empty list when no one has seen
/// it yet. Receives the pre-computed [seenBy] list (built in the caller's
/// context) so the dialog never needs to look up the chat-route's ChatCubit
/// provider, which is out of scope for the dialog route.
List<Widget> _buildGroupSeenTiles(
  BuildContext context,
  List<GroupMessageSeenByEntry> seenBy,
) {
  if (seenBy.isEmpty) return const [];

  final timeFormat = intl.DateFormat.yMMMd().add_jm();
  return [
    const Divider(height: 1),
    for (final entry in seenBy)
      ListTile(
        dense: true,
        leading: const Icon(Icons.done_all, color: Colors.blue),
        title: CustomText(
          text: entry.user.fullName,
          textColor: FcAppColors.of(context).textPrimary,
          fontWeight: FontWeight.w600,
        ),
        subtitle: CustomText(text: timeFormat.format(entry.seenAt)),
      ),
  ];
}

/// Inline editor for re-sending a corrected message text.
void showMessageEditDialog(BuildContext context, MessageModel message) {
  final controller = TextEditingController(text: message.text);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const CustomText(text: "Edit Message"),
      content: TextField(
        decoration: InputDecoration(
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide:
                  const BorderSide(color: Colors.lightBlueAccent)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: BorderSide(color: Colors.grey.shade600)),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
          hintText: "Edit your message",
          filled: true,
          fillColor: FcAppColors.of(ctx).inputFill,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        ),
        cursorColor: FcAppColors.of(ctx).textPrimary,
        maxLines: null,
        strutStyle: const StrutStyle(fontSize: 15),
        controller: controller,
        style: TextStyle(color: FcAppColors.of(ctx).textPrimary),
        textDirection: intl.Bidi.detectRtlDirectionality(controller.text)
            ? TextDirection.rtl
            : TextDirection.ltr,
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: CustomText(
                text: "Cancel", textColor: FcAppColors.of(ctx).textPrimary)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.lightBlueAccent),
          onPressed: () {
            final newText = controller.text.trim();
            if (newText.isNotEmpty && newText != message.text) {
              context
                  .read<ChatCubit>()
                  .editMessage(message.id, newText);
            }
            Navigator.of(ctx).pop();
          },
          child: const CustomText(text: "Save", textColor: Colors.white),
        ),
      ],
    ),
  );
}

/// "Delete for everyone" confirmation.
void showMessageDeleteDialog(BuildContext context, MessageModel message) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const CustomText(text: "Delete Message"),
      content: const CustomText(
          text: "Are you sure you want to delete this message?"),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: CustomText(
                text: "Cancel", textColor: FcAppColors.of(ctx).textPrimary)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            context.read<ChatCubit>().deleteMessage(message.id);
            Navigator.of(ctx).pop();
          },
          child: const CustomText(text: "Delete", textColor: Colors.white),
        ),
      ],
    ),
  );
}

/// "Delete only for me" confirmation (the other side keeps the message).
void showMessageDeleteForMeDialog(BuildContext context, MessageModel message) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const CustomText(text: "Delete for me"),
      content: const CustomText(
          text: "Delete this message only from your chat? The other person "
              "will still see it."),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: CustomText(
                text: "Cancel", textColor: FcAppColors.of(ctx).textPrimary)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            context.read<ChatCubit>().deleteMessageForMe(message.id);
            Navigator.of(ctx).pop();
          },
          child: const CustomText(text: "Delete", textColor: Colors.white),
        ),
      ],
    ),
  );
}