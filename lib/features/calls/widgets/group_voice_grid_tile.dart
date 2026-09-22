import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';

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
      decoration: BoxDecoration(
        color: AppColors.callCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLocal
              ? Colors.lightBlueAccent.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.12),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Avatar wrapped in a green glow when the participant is
                // actively speaking.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: isSpeaking ? 74 : 64,
                  height: isSpeaking ? 74 : 64,
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
                    padding: const EdgeInsets.all(3),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isLocal
                              ? [Colors.lightBlueAccent, AppColors.primaryDark]
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
                            ? CustomText(
                                text: avatarEmoji!,
                                fontSize: 30,
                              )
                            : CustomText(
                                text: _getInitials(name),
                                textColor: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 24,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: CustomText(
                          text: name,
                          textColor: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (isSpeaking) ...[
                        const SizedBox(width: 4),
                        const CustomText(
                          text: '🎙',
                          fontSize: 12,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Mute indicator badge
          if (isMuted)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.callErrorRed.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.mic_off_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
