import 'package:flutter/material.dart';

class CallStatusDisplay extends StatelessWidget {
  final bool isEngineReady;
  final bool isJoined;
  final bool isGroup;
  final int remoteUsersCount;

  const CallStatusDisplay({
    super.key,
    required this.isEngineReady,
    required this.isJoined,
    required this.isGroup,
    required this.remoteUsersCount,
  });

  @override
  Widget build(BuildContext context) {
    String statusText;
    bool isConnecting = false;

    if (!isEngineReady) {
      statusText = "Connecting...";
      isConnecting = true;
    } else if (!isJoined) {
      statusText = "Joining channel...";
      isConnecting = true;
    } else if (remoteUsersCount == 0) {
      statusText = "Ringing...";
      isConnecting = true;
    } else if (isGroup) {
      statusText = "Connected ($remoteUsersCount participants)";
    } else {
      statusText = "Connected";
    }

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
          Text(
            statusText,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}