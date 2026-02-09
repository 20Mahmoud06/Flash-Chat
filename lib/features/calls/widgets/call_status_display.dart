import 'package:flutter/material.dart';

class CallStatusDisplay extends StatelessWidget {
  final String displayName;
  final bool isEngineReady;
  final bool isJoined;
  final bool isGroup;
  final int remoteUsersCount;

  const CallStatusDisplay({
    super.key,
    required this.displayName,
    required this.isEngineReady,
    required this.isJoined,
    required this.isGroup,
    required this.remoteUsersCount,
  });

  @override
  Widget build(BuildContext context) {
    String statusText;

    if (!isEngineReady) {
      statusText = "Initializing...";
    } else if (!isJoined) {
      statusText = "Connecting...";
    } else if (isGroup) {
      statusText = "Connected to ${remoteUsersCount + 1} participants";
    } else {
      statusText = "Connected";
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!isEngineReady || !isJoined) ...[
          Text(
            "Calling $displayName...",
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 20),
        ],
        Text(
          statusText,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        if (!isEngineReady || !isJoined) ...[
          const SizedBox(height: 20),
          const CircularProgressIndicator(color: Colors.white),
        ],
      ],
    );
  }
}