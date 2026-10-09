import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';

class CustomTextFormField extends StatefulWidget {
  const CustomTextFormField({
    super.key,
    required this.controller,
    required this.validator,
    this.onChanged,
    required this.text,
    this.hintText,
    this.textInputAction,
    this.isPassword = false,
    this.isEmail = false,
    this.keyboardType,
    this.prefixIcon,
    this.enabled = true,
    this.minLines,
    this.maxLines,
    this.maxLetters,
  });

  final TextEditingController controller;
  final String? Function(String?) validator;
  final void Function(String)? onChanged;
  final String text;
  final String? hintText;
  final TextInputAction? textInputAction;
  final bool isPassword;
  final bool isEmail;
  final TextInputType? keyboardType;
  final Widget? prefixIcon;
  final bool enabled;
  final int? minLines;
  final int? maxLines;

  /// Optional character limit shown as a WhatsApp-style "letters left"
  /// counter under the field. Typing beyond the limit is allowed; the
  /// counter turns red while over it.
  final int? maxLetters;

  @override
  State<CustomTextFormField> createState() => _CustomTextFormFieldState();
}

class _CustomTextFormFieldState extends State<CustomTextFormField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.isPassword;
    if (widget.maxLetters != null) {
      widget.controller.addListener(_onCounterChanged);
    }
  }

  void _onCounterChanged() => setState(() {});

  @override
  void dispose() {
    if (widget.maxLetters != null) {
      widget.controller.removeListener(_onCounterChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FcAppColors.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hintColor = colors.textWeak;
    final enabledBorderColor =
        isDark ? Colors.lightBlue.shade300 : Colors.lightBlue.shade200;
    final focusedBorderColor =
        isDark ? Colors.lightBlueAccent : Colors.lightBlue.shade300;
    final errorColor = theme.colorScheme.error;

    final outlineInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(50.0.r),
      borderSide: BorderSide(color: enabledBorderColor, width: 1.5.w),
    );

    final focusedOutlineInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(50.0.r),
      borderSide: BorderSide(color: focusedBorderColor, width: 2.0.w),
    );

    final disabledBorderColor =
        isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final disabledOutlineInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(50.0.r),
      borderSide: BorderSide(color: disabledBorderColor, width: 1.0.w),
    );

    final maxLetters = widget.maxLetters;
    final remaining =
        maxLetters == null ? null : maxLetters - widget.controller.text.length;

    return TextFormField(
      enabled: widget.enabled,
      keyboardType: widget.keyboardType ??
          (widget.isEmail ? TextInputType.emailAddress : TextInputType.text),
      textAlign: (widget.prefixIcon == null && (widget.maxLines ?? 1) == 1)
          ? TextAlign.center
          : TextAlign.start,
      onChanged: widget.onChanged,
      controller: widget.controller,
      textInputAction: widget.textInputAction,
      validator: widget.validator,
      obscureText: _obscureText,
      minLines: widget.minLines ?? 1,
      maxLines: widget.maxLines ?? 1,
      decoration: InputDecoration(
        border: outlineInputBorder,
        enabledBorder: outlineInputBorder,
        focusedBorder: focusedOutlineInputBorder,
        disabledBorder: disabledOutlineInputBorder,
        errorBorder: outlineInputBorder.copyWith(
          borderSide: BorderSide(color: errorColor, width: 1.5.w),
        ),
        focusedErrorBorder: outlineInputBorder.copyWith(
          borderSide: BorderSide(color: errorColor, width: 2.0.w),
        ),
        isDense: true,
        hintText: widget.hintText ?? widget.text,
        hintStyle: TextStyle(color: hintColor),
        filled: true,
        fillColor: colors.surface,
        contentPadding:
            EdgeInsets.symmetric(vertical: 15.0.h, horizontal: 20.0.w),
        prefixIcon: widget.prefixIcon,
        counterText: remaining == null ? null : '$remaining',
        counterStyle: remaining == null
            ? null
            : TextStyle(
                color: remaining < 0 ? Colors.red : colors.textWeak,
                fontSize: 12.sp,
              ),
        suffixIcon: widget.isPassword
            ? IconButton(
                icon: Icon(
                  _obscureText
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: hintColor,
                ),
                onPressed: () {
                  setState(() {
                    _obscureText = !_obscureText;
                  });
                },
              )
            : null,
      ),
      style: TextStyle(color: colors.textPrimary, fontSize: 18.sp),
      cursorColor: colors.textPrimary,
    );
  }
}
