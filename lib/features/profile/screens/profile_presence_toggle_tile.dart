import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';
import '../cubit/profile_cubit.dart';

class ProfilePresenceToggleTile extends StatefulWidget {
  final bool initialValue;

  const ProfilePresenceToggleTile({super.key, required this.initialValue});

  @override
  State<ProfilePresenceToggleTile> createState() =>
      _ProfilePresenceToggleTileState();
}

class _ProfilePresenceToggleTileState extends State<ProfilePresenceToggleTile> {
  late bool _value = widget.initialValue;

  void _toggle(bool value) {
    setState(() => _value = value);
    context.read<ProfileCubit>().updatePresenceEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
        side: BorderSide(color: colors.divider),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
        leading: CircleAvatar(
          backgroundColor: Colors.lightBlueAccent.withValues(alpha: 0.15),
          child: const Icon(Icons.visibility_outlined,
              color: Colors.lightBlueAccent),
        ),
        title: CustomText(
          text: 'Show Online Status',
          fontSize: 16.sp,
          fontWeight: FontWeight.w600,
          textColor: colors.textPrimary,
        ),
        subtitle: CustomText(
          text: 'Let others see when you are online and your last seen',
          fontSize: 13.sp,
          textColor: colors.textSecondary,
        ),
        trailing: Switch(value: _value, onChanged: _toggle),
        onTap: () => _toggle(!_value),
      ),
    );
  }
}
