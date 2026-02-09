import 'package:flutter/material.dart';

class CallControls extends StatelessWidget {
  final bool isMuted;
  final bool isCameraOff;
  final bool isVideo;
  final VoidCallback onMuteToggle;
  final VoidCallback? onCameraToggle;
  final VoidCallback? onSwitchCamera;
  final VoidCallback onEndCall;

  const CallControls({
    super.key,
    required this.isMuted,
    required this.isCameraOff,
    required this.isVideo,
    required this.onMuteToggle,
    this.onCameraToggle,
    this.onSwitchCamera,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Mute button
        IconButton(
          icon: Icon(
            isMuted ? Icons.mic_off : Icons.mic,
            color: Colors.white,
            size: 32,
          ),
          onPressed: onMuteToggle,
        ),

        // Camera button (video only)
        if (isVideo && onCameraToggle != null) ...[
          IconButton(
            icon: Icon(
              isCameraOff ? Icons.videocam_off : Icons.videocam,
              color: Colors.white,
              size: 32,
            ),
            onPressed: onCameraToggle,
          ),
        ],

        const SizedBox(width: 30),

        // End call button
        IconButton(
          icon: const Icon(
            Icons.call_end,
            color: Colors.red,
            size: 40,
          ),
          onPressed: onEndCall,
        ),

        const SizedBox(width: 30),

        // Switch camera button (video only)
        if (isVideo && onSwitchCamera != null)
          IconButton(
            icon: const Icon(
              Icons.switch_camera,
              color: Colors.white,
              size: 32,
            ),
            onPressed: onSwitchCamera,
          ),
      ],
    );
  }
}