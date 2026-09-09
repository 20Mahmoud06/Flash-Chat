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
        color: const Color(0xFF1B263B),
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
                              color: Color(0xFF4CAF50),
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
                              ? [Colors.lightBlueAccent, const Color(0xFF0288D1)]
                              : [
                                  const Color(0xFF24324D),
                                  const Color(0xFF1B263B),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: isSpeaking
                              ? const Color(0xFF66BB6A)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: avatarEmoji != null && avatarEmoji!.isNotEmpty
                            ? Text(
                                avatarEmoji!,
                                style: const TextStyle(fontSize: 30),
                              )
                            : Text(
                                _getInitials(name),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 24,
                                ),
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
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (isSpeaking) ...[
                        const SizedBox(width: 4),
                        const Text(
                          '🎙',
                          style: TextStyle(fontSize: 12),
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
                  color: const Color(0xFFFF5252).withValues(alpha: 0.85),
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
