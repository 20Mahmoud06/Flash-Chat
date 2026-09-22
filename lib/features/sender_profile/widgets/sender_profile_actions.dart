import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_theme.dart';
import '../../profile/models/user_model.dart';
import '../cubit/sender_profile_state.dart';
import 'sender_profile_card_tile.dart';
import 'sender_profile_media_section.dart';

/// The tappable tiles (nickname, media/gallery, block) on the contact info
/// screen. Config mirrors the current channel state; tapping fires the
/// screen-level callbacks.
class SenderProfileActions extends StatelessWidget {
  final UserModel user;
  final SenderProfileState state;
  final String chatId;
  final VoidCallback onEditNickname;
  final ValueChanged<int> onOpenGallery;
  final VoidCallback onToggleBlock;

  const SenderProfileActions({
    super.key,
    required this.user,
    required this.state,
    required this.chatId,
    required this.onEditNickname,
    required this.onOpenGallery,
    required this.onToggleBlock,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final myNickname = state.myNickname;

    return Column(
      children: [
        SizedBox(height: 16.h),
        SenderProfileCardTile(
          icon: Icons.badge_outlined,
          iconColor: Colors.lightBlueAccent,
          iconBackground: colors.tile,
          title: 'Nickname',
          subtitle: myNickname == null || myNickname.isEmpty
              ? 'Only visible to you'
              : myNickname,
          subtitleColor: myNickname == null ? null : Colors.lightBlueAccent,
          subtitleWeight:
              myNickname == null ? FontWeight.normal : FontWeight.w600,
          trailing: const Icon(Icons.edit_outlined, color: Colors.grey),
          onTap: onEditNickname,
        ),
        SizedBox(height: 16.h),
        SenderProfileMediaSection(
          chatId: chatId,
          onOpenGallery: onOpenGallery,
        ),
        SizedBox(height: 16.h),
        if (state.loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(color: Colors.lightBlueAccent),
          )
        else if (user.isDeleted)
          const SizedBox.shrink()
        else
          SenderProfileCardTile(
            icon: state.isBlocked ? Icons.block : Icons.block_outlined,
            iconColor: state.isBlocked ? Colors.red : colors.textSecondary,
            iconBackground: state.isBlocked ? Colors.red.shade50 : colors.tile,
            title: state.isBlocked
                ? 'Unblock ${user.firstName}'
                : 'Block ${user.firstName}',
            titleColor: state.isBlocked ? Colors.red : null,
            subtitle: state.isBlocked
                ? 'This user is currently blocked'
                : 'Stop receiving messages and calls from this user',
            trailing: Icon(
              state.isBlocked ? Icons.lock_open : Icons.chevron_right,
              color: state.isBlocked ? Colors.red : colors.textWeak,
            ),
            onTap: onToggleBlock,
          ),
        SizedBox(height: 24.h),
      ],
    );
  }
}