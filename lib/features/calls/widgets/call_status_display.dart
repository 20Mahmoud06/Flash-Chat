import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';

/// Single source of truth for the live call status label, shared by the
/// voice/video display areas AND the top bars so they never disagree.
String callStatusText({
  required bool isEngineReady,
  required bool isJoined,
  required bool isGroup,
  required int remoteUsersCount,
  required bool hadRemoteUser,
}) {
  if (!isEngineReady) return "Connecting...";
  if (!isJoined) return "Joining channel...";
  if (remoteUsersCount == 0) {
    // Someone was in the call and all of them left: never fall back to a
    // pulsing "Ringing..." (there is nobody to ring) and never pretend the
    // call is still connecting.
    if (hadRemoteUser) {
      return isGroup
          ? "Waiting for others…"
          : "The other person left the call";
    }
    return "Ringing...";
  }
  if (isGroup) return "Connected ($remoteUsersCount participants)";
  return "Connected";
}

class CallStatusDisplay extends StatelessWidget {
  final bool isEngineReady;
  final bool isJoined;
  final bool isGroup;
  final int remoteUsersCount;
  final bool hadRemoteUser;

  const CallStatusDisplay({
    super.key,
    required this.isEngineReady,
    required this.isJoined,
    required this.isGroup,
    required this.remoteUsersCount,
    this.hadRemoteUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = callStatusText(
      isEngineReady: isEngineReady,
      isJoined: isJoined,
      isGroup: isGroup,
      remoteUsersCount: remoteUsersCount,
      hadRemoteUser: hadRemoteUser,
    );
    final isConnecting = statusText == "Connecting..." ||
        statusText == "Joining channel..." ||
        statusText == "Ringing...";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isConnecting) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 8),
          ] else ...[
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.lightBlueAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          CustomText(
            text: statusText,
            textColor: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ],
      ),
    );
  }
}
