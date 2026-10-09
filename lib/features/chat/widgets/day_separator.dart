import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';

/// WhatsApp-style centered chip that separates messages by day.
/// Labels: "Today", "Yesterday", weekday ("Wednesday") for the past week,
/// or a full date ("8 August 2026") for older messages.
class DaySeparator extends StatelessWidget {
  final DateTime date;

  const DaySeparator({super.key, required this.date});

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _label(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(date);
    return DateFormat('d MMMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: CustomText(
            text: _label(DateTime.now()),
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            textColor: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// WhatsApp-style timestamp label for the chat list tile:
/// - today: time ("3:45 PM")
/// - yesterday: "Yesterday"
/// - same week (Monday-based): weekday ("Monday")
/// - another week: date ("2/10/2026")
String lastMessageTimeLabel(DateTime date, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return DateFormat('h:mm a').format(date);
  if (diff == 1) return 'Yesterday';
  final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
  final msgWeekStart = day.subtract(Duration(days: day.weekday - 1));
  if (thisWeekStart.difference(msgWeekStart).inDays == 0) {
    return DateFormat('EEEE').format(date);
  }
  return DateFormat('d/M/yyyy').format(date);
}
