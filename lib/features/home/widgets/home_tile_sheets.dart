import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'home_option_sheet.dart';
import 'home_sheet_option_row.dart';

/// Bottom sheet shown when long-pressing a group on the Groups tab.
/// Everyone can pin/unpin and (on an active group) hide it from their own
/// list with "Delete for me". Deleting the whole group is an option ONLY
/// for the creator, and once a group is deleted no delete options are
/// offered at all, so members always keep read access to the history.
void showHomeGroupOptionsSheet({
  required BuildContext context,
  required String groupId,
  required String groupName,
  required bool isPinned,
  required bool isCreator,
  required bool isAdmin,
  required bool isDeleted,
  required VoidCallback onTogglePin,
  required VoidCallback onDeleteForMe,
  required VoidCallback onDeleteGroup,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
    ),
    builder: (ctx) {
      return HomeOptionSheet(
        title: 'Group Options',
        children: [
          HomeSheetOptionRow(
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            iconColor: Colors.lightBlueAccent,
            iconBackground: Colors.lightBlueAccent.withValues(alpha: 0.15),
            title: isPinned ? 'Unpin group' : 'Pin group',
            subtitle: isPinned
                ? 'Show this group normally'
                : 'Pin this group to the top of your list',
            onTap: () {
              Navigator.pop(ctx);
              onTogglePin();
            },
          ),
          const HomeSheetDivider(),
          // "Delete for me" (hide from my list) — available to everyone.
          // This also lets a member remove a DELETED group from their
          // home list, while the read-only archive stays intact for the
          // members who still want to read it.
          HomeSheetOptionRow(
            icon: Icons.delete_outline,
            iconColor: Colors.red.shade400,
            iconBackground: Colors.red.shade50,
            title: 'Delete for me',
            subtitle: 'Delete this group from your list',
            onTap: () {
              Navigator.pop(ctx);
              onDeleteForMe();
            },
          ),
          if ((isCreator || isAdmin) && !isDeleted) ...[
            const HomeSheetDivider(),
            HomeSheetOptionRow(
              icon: Icons.delete_forever,
              iconColor: Colors.red.shade400,
              iconBackground: Colors.red.shade50,
              title: 'Delete Group',
              titleColor: Colors.red.shade400,
              subtitle:
                  'Delete the whole group and make it read-only for everyone',
              onTap: () {
                Navigator.pop(ctx);
                onDeleteGroup();
              },
            ),
          ],
        ],
      );
    },
  );
}

/// Bottom sheet shown when long-pressing a 1-1 chat on the Chats tab.
/// Offers pin/unpin, "Delete for me" and "Delete for everyone". Self-chats
/// never offer "for everyone" (in a self-chat those would be the same as
/// deleting for me).
void showHomeChatOptionsSheet({
  required BuildContext context,
  required String type,
  required String lowerType,
  required bool isPinned,
  bool isSelfChat = false,
  required VoidCallback onTogglePin,
  required VoidCallback onDeleteForMe,
  required VoidCallback onDeleteForEveryone,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
    ),
    builder: (ctx) {
      return HomeOptionSheet(
        title: '$type Options',
        children: [
          // Pin / unpin option
          HomeSheetOptionRow(
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            iconColor: Colors.lightBlueAccent,
            iconBackground: Colors.lightBlueAccent.withValues(alpha: 0.15),
            title: isPinned ? 'Unpin $lowerType' : 'Pin $lowerType',
            subtitle: isPinned
                ? 'Show this $lowerType normally'
                : 'Pin this $lowerType to the top of your list',
            onTap: () {
              Navigator.pop(ctx);
              onTogglePin();
            },
          ),
          const HomeSheetDivider(),
          // Delete for me option
          HomeSheetOptionRow(
            icon: Icons.delete_outline,
            iconColor: Colors.red.shade400,
            iconBackground: Colors.red.shade50,
            title: 'Delete for me',
            subtitle: 'Delete this $lowerType from your list',
            onTap: () {
              Navigator.pop(ctx);
              onDeleteForMe();
            },
          ),
          const HomeSheetDivider(),
          // Delete for everyone option. Hidden for self-chats: in a
          // self-chat "for me" and "for everyone" are the same thing.
          if (!isSelfChat) ...[
            HomeSheetOptionRow(
              icon: Icons.delete_forever,
              iconColor: Colors.red.shade600,
              iconBackground: Colors.red.shade100,
              title: 'Delete for everyone',
              subtitle: 'Remove $lowerType and messages permanently',
              onTap: () {
                Navigator.pop(ctx);
                onDeleteForEveryone();
              },
            ),
          ],
        ],
      );
    },
  );
}