import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';

/// Shown while the engine is still joining the channel (or has not been
/// created yet): a spinner above the callee's name.
class VideoCallConnectingView extends StatelessWidget {
  final String displayName;

  const VideoCallConnectingView({super.key, required this.displayName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.white70),
          const SizedBox(height: 16),
          CustomText(
            text: 'Connecting to $displayName...',
            textColor: Colors.white70,
            fontSize: 16,
          ),
        ],
      ),
    );
  }
}
