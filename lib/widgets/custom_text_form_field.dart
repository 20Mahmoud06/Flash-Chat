import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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

  @override
  State<CustomTextFormField> createState() => _CustomTextFormFieldState();
}

class _CustomTextFormFieldState extends State<CustomTextFormField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.isPassword;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintColor = Colors.grey.shade500;
    final enabledBorderColor = Colors.lightBlue.shade100;
    final focusedBorderColor = Colors.lightBlue.shade300;
    final errorColor = theme.colorScheme.error;

    final outlineInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(50.0.r),
      borderSide: BorderSide(color: enabledBorderColor, width: 1.5.w),
    );

    final focusedOutlineInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(50.0.r),
      borderSide: BorderSide(color: focusedBorderColor, width: 2.0.w),
    );

    return TextFormField(
      enabled: widget.enabled,
      keyboardType: widget.keyboardType ?? (widget.isEmail
          ? TextInputType.emailAddress
          : TextInputType.text),
      textAlign: (widget.prefixIcon == null && (widget.maxLines ?? 1) == 1) ? TextAlign.center : TextAlign.start,
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
        fillColor: Colors.white,
        contentPadding:
        EdgeInsets.symmetric(vertical: 15.0.h, horizontal: 20.0.w),
        prefixIcon: widget.prefixIcon,
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
      style: TextStyle(color: Colors.grey.shade900, fontSize: 18.sp),
      cursorColor: Colors.grey.shade900,
    );
  }
}