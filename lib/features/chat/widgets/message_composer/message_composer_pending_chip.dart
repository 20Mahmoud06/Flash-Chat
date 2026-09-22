import 'package:animate_do/animate_do.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Persistent "messages are queued" chip shown above the composer while the
/// connection is missing, so users always know their messages are saved and
/// will be sent automatically. Slides/fades in and out.
class MessageComposerPendingQueueChip extends StatelessWidget {
  final int count;

  const MessageComposerPendingQueueChip({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        axisAlignment: -1,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Container(
        key: ValueKey('queue_chip_$count'),
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Pulse(
              infinite: true,
              duration: const Duration(milliseconds: 1200),
              child: Icon(
                Icons.schedule_send_outlined,
                color: Colors.orange.shade700,
                size: 18,
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: CustomText(
                text: count == 1
                    ? "1 message queued — will send automatically when "
                        "you're back online"
                    : '$count messages queued — will send automatically '
                        'when you\'re back online',
                fontSize: 12.sp,
                textColor: Colors.orange.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}