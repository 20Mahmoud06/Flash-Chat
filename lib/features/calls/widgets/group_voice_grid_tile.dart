import 'dart:math' as math;

import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';

/// One participant tile of the group voice-call grid.
///
/// Everything inside is sized from the tile box itself (avatar, name, badges)
/// so the tile stays readable and never overflows, no matter how many
/// participants the grid packs into the screen.
class GroupVoiceGridTile extends StatelessWidget {
  final String name;
  final String? avatarEmoji;
  final bool isMuted;
  final bool isLocal;
  final bool isSpeaking;

  const GroupVoiceGridTile({
    super.key,
    required this.name,
    this.avatarEmoji,
    required this.isMuted,
    this.isLocal = false,
    this.isSpeaking = false,
  });

  String _getInitials(String name) {
    if (name.trim().isEmpty) return "?";
    final parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.callCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSpeaking
              ? AppColors.speakingBorder
              : (isLocal
                  ? Colors.lightBlueAccent.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.12)),
          width: isSpeaking ? 2.5 : 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double width = constraints.maxWidth;
          final double height = constraints.maxHeight;
          // Avatar shrinks with the tile so crowded grids stay legible and
          // never force the content to overflow.
          final double base = math.min(
            64,
            math.max(20, math.min(width * 0.66, height * 0.52)),
          );
          final double avatarSide = isSpeaking ? base * 1.16 : base;
          final double avatarGap = math.min(12, height * 0.1);
          final double nameFontSize = math.min(14, math.max(10, height * 0.13));
          final double badgeInset = math.min(10, width * 0.05);
          final double badgePadding = math.min(5, width * 0.035);
          final double badgeIcon = math.min(14, width * 0.15);

          return Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Avatar wrapped in a green glow when the participant is
                    // actively speaking.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: avatarSide,
                      height: avatarSide,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: isSpeaking
                            ? const [
                                BoxShadow(
                                  color: AppColors.speakingGlow,
                                  blurRadius: 24,
                                  spreadRadius: 3,
                                ),
                              ]
                            : const [
                                BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(avatarSide * 0.05),
                        child: Container(
                          width: avatarSide * 0.9,
                          height: avatarSide * 0.9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: isLocal
                                  ? [
                                      Colors.lightBlueAccent,
                                      AppColors.primaryDark,
                                    ]
                                  : [
                                      AppColors.callTileActive,
                                      AppColors.callCardBg,
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: isSpeaking
                                  ? AppColors.speakingBorder
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: avatarEmoji != null && avatarEmoji!.isNotEmpty
                                ? FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: CustomText(
                                      text: avatarEmoji!,
                                      fontSize: avatarSide * 0.47,
                                    ),
                                  )
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: CustomText(
                                      text: _getInitials(name),
                                      textColor: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: avatarSide * 0.37,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: avatarGap),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: math.min(8, width * 0.05),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: CustomText(
                              text: name,
                              textColor: Colors.white,
                              fontSize: nameFontSize,
                              fontWeight: FontWeight.w600,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (isSpeaking) ...[
                            SizedBox(width: math.min(4, width * 0.03)),
                            CustomText(
                              text: '🎙',
                              fontSize: math.min(12, nameFontSize * 0.86),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Speaking indicator badge (green mic)
              if (isSpeaking)
                Positioned(
                  top: badgeInset,
                  left: badgeInset,
                  child: _Badge(
                    color: AppColors.speakingGlow,
                    padding: badgePadding,
                    icon: Icons.mic_rounded,
                    iconSize: badgeIcon,
                  ),
                ),
              // Mute indicator badge
              if (isMuted)
                Positioned(
                  top: badgeInset,
                  right: badgeInset,
                  child: _Badge(
                    color: AppColors.callErrorRed.withValues(alpha: 0.85),
                    padding: badgePadding,
                    icon: Icons.mic_off_rounded,
                    iconSize: badgeIcon,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Small round status badge (mic / muted mic) shown in a tile corner.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.color,
    required this.padding,
    required this.icon,
    required this.iconSize,
  });

  final Color color;
  final double padding;
  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }
}