import 'package:flutter/material.dart';

class CustomText extends StatelessWidget {
  const CustomText({
    super.key,
    this.textColor,
    required this.text,
    this.fontSize,
    this.fontStyle,
    this.fontWeight,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.textDirection,
  });

  final Color? textColor;
  final String text;
  final double? fontSize;
  final FontStyle? fontStyle;
  final FontWeight? fontWeight;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    return Text(
      textDirection: textDirection,
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
      ),
    );
  }
}