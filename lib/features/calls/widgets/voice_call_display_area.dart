import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/custom_text.dart';
import '../services/call_avatar_loader.dart';
import 'animated_call_grid.dart';
import 'call_status_display.dart';
import 'group_voice_grid_tile.dart';

/// Main display area of a voice call: the gradient backdrop plus either the
/// group tile grid or the centered 1-on-1 avatar with the call status.
class VoiceCallDisplayArea extends StatelessWidget {
  final bool isGroup;
  final String displayName;
  final String? avatarEmoji;
  final String? ownAvatar;
  final bool isEngineReady;
  final bool isJoined;
  final bool hadRemoteUser;
  final bool isMuted;
  final List<int> remoteUids;
  final Set<int> speakingUids;
  final Set<int> mutedRemoteAudioUids;
  final Map<int, CallParticipantInfo> participants;

  const VoiceCallDisplayArea({
    super.key,
    required this.isGroup,
    required this.displayName,
    required this.avatarEmoji,
    required this.ownAvatar,
    required this.isEngineReady,
    required this.isJoined,
    required this.isMuted,
    required this.remoteUids,
    required this.speakingUids,
    required this.mutedRemoteAudioUids,
    required this.participants,
    this.hadRemoteUser = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.callBackgroundTop,
            AppColors.callBackgroundMiddle,
            AppColors.callBackgroundBottom,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: isGroup && remoteUids.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: 80,
                  left: 16,
                  right: 16,
                  bottom: 110,
                ),
                child: AnimatedCallGrid(
                  uids: [0, ...remoteUids],
                  spacing: 12,
                  itemBuilder: (context, uid) {
                    if (uid == 0) {
                      return GroupVoiceGridTile(
                        name: "You",
                        avatarEmoji: ownAvatar ?? avatarEmoji,
                        isMuted: isMuted,
                        isLocal: true,
                        isSpeaking: speakingUids.contains(0),
                      );
                    }
                    final info = participants[uid];
                    return GroupVoiceGridTile(
                      name: info?.name ?? "Participant $uid",
                      avatarEmoji: info?.avatarEmoji,
                      isMuted: mutedRemoteAudioUids.contains(uid),
                      isLocal: false,
                      isSpeaking: speakingUids.contains(uid),
                    );
                  },
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PulsingAvatar(
                        displayName: displayName,
                        avatarEmoji: avatarEmoji,
                        pulse: remoteUids.isEmpty,
                      ),
                      const SizedBox(height: 28),
                      CustomText(
                        text: displayName,
                        textColor: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      const SizedBox(height: 14),
                      CallStatusDisplay(
                        isEngineReady: isEngineReady,
                        isJoined: isJoined,
                        isGroup: isGroup,
                        remoteUsersCount: remoteUids.length,
                        hadRemoteUser: hadRemoteUser,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// The pulsing gradient avatar shown while a 1-on-1 voice call is ringing.
/// The pulse animates continuously but only scales the avatar up while the
/// remote party is not yet connected.
class _PulsingAvatar extends StatefulWidget {
  final String displayName;
  final String? avatarEmoji;
  final bool pulse;

  const _PulsingAvatar({
    required this.displayName,
    required this.avatarEmoji,
    required this.pulse,
  });

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String get _initials {
    final name = widget.displayName.trim();
    if (name.isEmpty) return "?";
    final parts = name.split(' ');
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.pulse ? _pulseAnimation.value : 1.0,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color:
                      Colors.lightBlueAccent.withValues(alpha: 0.35),
                  blurRadius: 36,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [
              Colors.lightBlueAccent,
              AppColors.primaryDark,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.4),
            width: 2.5,
          ),
        ),
        child: Center(
          child: widget.avatarEmoji != null &&
                  widget.avatarEmoji!.isNotEmpty
              ? CustomText(text: widget.avatarEmoji!, fontSize: 56)
              : CustomText(
                  text: _initials,
                  textColor: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 44,
                ),
        ),
      ),
    );
  }
}