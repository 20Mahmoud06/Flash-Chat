import 'dart:math' as math;

import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Telegram/WhatsApp-style typing indicator: a chat bubble with three
/// animated dots. In group chats it also shows the avatar of the member
/// who is typing and their name above the bubble.
class TypingIndicator extends StatefulWidget {
  /// Uids of the users currently typing (excluding the current user).
  final List<String> typingUids;

  final bool isGroup;

  /// Group members keyed by uid (for avatar + name resolution).
  final Map<String, UserModel> members;

  /// Avatar emoji of the other user in a 1:1 chat.
  final String? contactAvatar;

  const TypingIndicator({
    super.key,
    required this.typingUids,
    this.isGroup = false,
    this.members = const {},
    this.contactAvatar,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _entranceController;
  late final Animation<Offset> _entranceOffset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _entranceOffset = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  String? get _typingUser {
    if (widget.typingUids.isEmpty) return null;
    final uid = widget.typingUids.first;
    return widget.members[uid]?.firstName;
  }

  String get _statusText {
    if (widget.typingUids.length > 2) {
      return 'Several people are typing';
    }
    if (widget.typingUids.length == 2) {
      final first = widget.members[widget.typingUids[0]]?.firstName ?? 'Someone';
      final second = widget.members[widget.typingUids[1]]?.firstName ?? 'Someone';
      return '$first and $second are typing';
    }
    final name = _typingUser;
    return name == null ? 'Someone is typing' : '$name is typing';
  }

  String get _avatar {
    if (widget.typingUids.isEmpty) return '👤';
    if (widget.isGroup) {
      return widget.members[widget.typingUids.first]?.avatarEmoji ?? '👤';
    }
    return widget.contactAvatar ?? '👤';
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);

    final bubble = Container(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 14.w),
      decoration: BoxDecoration(
        color: colors.bubbleOther,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18.r),
          topRight: Radius.circular(18.r),
          bottomLeft: Radius.circular(4.r),
          bottomRight: Radius.circular(18.r),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2.5.w),
                  child: _TypingDot(
                    color: colors.bubbleOtherText.withValues(alpha: 0.45),
                    opacity: _dotOpacity(i),
                  ),
                ),
            ],
          );
        },
      ),
    );

    return FadeTransition(
      opacity: _entranceController,
      child: SlideTransition(
        position: _entranceOffset,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 8.w),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: CircleAvatar(
                  radius: 18.r,
                  backgroundColor: Colors.transparent,
                  child: CustomText(text: _avatar, fontSize: 18.sp),
                ),
              ),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isGroup)
                      Padding(
                        padding: EdgeInsets.only(bottom: 4.h),
                        child: CustomText(
                          text: _statusText,
                          fontSize: 12.sp,
                          textColor: colors.textWeak,
                        ),
                      ),
                    bubble,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _dotOpacity(int index) {
    final t = _controller.value * 2 * math.pi;
    return 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t - index * 0.7));
  }
}

class _TypingDot extends StatelessWidget {
  final Color color;
  final double opacity;

  const _TypingDot({required this.color, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Container(
        width: 8.w,
        height: 8.w,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
