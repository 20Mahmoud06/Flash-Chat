import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import '../bloc/call_bloc.dart';

/// Compact live time-counter pill shown at the top-center of the voice/video
/// call screens while the call is running. Reads the app-wide elapsed time
/// from [CallBloc.elapsedNotifier] (started at the call-doc creation) so it
/// never drifts from the one-hour cap. Turns amber during the last 10 minutes.
class CallCenterTimer extends StatelessWidget {
  final bool visible;

  const CallCenterTimer({super.key, this.visible = true});

  /// Minutes:seconds that can run past 59 — the pill shows 60:00 the moment
  /// the auto-end fires, so the user always sees the exact cap reached.
  static String format(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return ValueListenableBuilder<Duration>(
      valueListenable: CallBloc.instance.elapsedNotifier,
      builder: (context, elapsed, _) {
        final warning = elapsed >=
            CallBloc.maxCallDuration - CallBloc.maxCallWarningLead;
        final accent =
            warning ? AppColors.callStatusAmber : Colors.white70;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.callHeaderBg.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: (warning ? AppColors.callStatusAmber : Colors.white)
                  .withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer_outlined, size: 15, color: accent),
              const SizedBox(width: 6),
              CustomText(
                text: format(elapsed),
                textColor:
                    warning ? AppColors.callStatusAmber : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ],
          ),
        );
      },
    );
  }
}