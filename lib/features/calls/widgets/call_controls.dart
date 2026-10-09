import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

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

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required bool isActive,
    bool isDestructive = false,
    String? tooltip,
  }) {
    final backgroundColor = isDestructive
        ? AppColors.callEndRed
        : (isActive
            ? Colors.redAccent.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.15));

    const iconColor = Colors.white;

    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: isDestructive ? 60 : 50,
            height: isDestructive ? 60 : 50,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDestructive
                    ? Colors.red.shade400
                    : (isActive
                        ? Colors.red.shade300
                        : Colors.white.withValues(alpha: 0.2)),
                width: 1.5,
              ),
              boxShadow: isDestructive
                  ? [
                      BoxShadow(
                        color: AppColors.callEndRed.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      )
                    ]
                  : (isActive
                      ? [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.3),
                            blurRadius: 10,
                            spreadRadius: 1,
                          )
                        ]
                      : []),
            ),
            child: Center(
              child: Icon(
                icon,
                color: iconColor,
                size: isDestructive ? 28 : 24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.callOverlay.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mute microphone button
                  _buildControlButton(
                    icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    onPressed: onMuteToggle,
                    isActive: isMuted,
                    tooltip: isMuted ? 'Unmute' : 'Mute',
                  ),

                  if (isVideo && onCameraToggle != null) ...[
                    const SizedBox(width: 16),
                    // Camera toggle button
                    _buildControlButton(
                      icon: isCameraOff
                          ? Icons.videocam_off_rounded
                          : Icons.videocam_rounded,
                      onPressed: onCameraToggle,
                      isActive: isCameraOff,
                      tooltip:
                          isCameraOff ? 'Turn Camera On' : 'Turn Camera Off',
                    ),
                  ],

                  if (isVideo && onSwitchCamera != null) ...[
                    const SizedBox(width: 16),
                    // Switch camera button
                    _buildControlButton(
                      icon: Icons.flip_camera_ios_rounded,
                      onPressed: onSwitchCamera,
                      isActive: false,
                      tooltip: 'Switch Camera',
                    ),
                  ],

                  const SizedBox(width: 20),

                  // End call button
                  _buildControlButton(
                    icon: Icons.call_end_rounded,
                    onPressed: onEndCall,
                    isActive: false,
                    isDestructive: true,
                    tooltip: 'End Call',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
