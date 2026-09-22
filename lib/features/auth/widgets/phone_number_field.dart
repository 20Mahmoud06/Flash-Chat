import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/core/utils/country_codes.dart';
import 'package:flash_chat_app/features/auth/widgets/country_picker_sheet.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flash_chat_app/shared/widgets/custom_text_form_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Telegram-style phone number field.
///
/// Shows the selected country's flag + dialing code as a tappable prefix
/// that opens the [CountryPickerSheet]. The entered number is validated
/// against the digit count of the selected country (e.g. Egypt +20 must
/// have exactly 10 digits).
class PhoneNumberField extends StatefulWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    this.initialCountry,
    this.onChanged,
  });

  final TextEditingController controller;
  final CountryCode? initialCountry;
  final void Function(String)? onChanged;

  @override
  State<PhoneNumberField> createState() => PhoneNumberFieldState();
}

class PhoneNumberFieldState extends State<PhoneNumberField> {
  CountryCode _country =
      CountryCodes.getByCode('+20') ?? CountryCodes.countries.first;

  /// Strips the country-code prefix the user may have typed (e.g.
  /// "201012345678" → "1012345678") so the same number always stores,
  /// compares and sends to the SMS service identically, without doubling
  /// the country code in [e164PhoneNumber].  Only strips when the
  /// remaining digits fall inside the expected range for the selected
  /// country, so short codes like +7 or +1 are handled safely.
  String _digitsOnly() {
    var digits = widget.controller.text.replaceAll(RegExp(r'\D'), '');
    final countryCodeDigits = _country.code.substring(1); // "+20" → "20"
    if (digits.startsWith(countryCodeDigits) &&
        digits.length > countryCodeDigits.length) {
      final stripped = digits.substring(countryCodeDigits.length);
      final (min, max) = CountryCodes.phoneNumberLength(_country);
      if (stripped.length >= min && stripped.length <= max) {
        digits = stripped;
      }
    }
    return digits;
  }

  /// The full international number in canonical E.164 form, e.g.
  /// `+201012345678`.  Handles two common user-input styles:
  ///
  ///   1. `1012345678`  (clean national) → `+201012345678`
  ///   2. `201012345678` (with country code) → strips 20 → `+201012345678`
  String get e164PhoneNumber {
    return '${_country.code}${_digitsOnly()}';
  }

  /// The currently selected country.
  CountryCode get selectedCountry => _country;

  @override
  void initState() {
    super.initState();
    if (widget.initialCountry != null) {
      _country = widget.initialCountry!;
    }
  }

  Future<void> _pickCountry() async {
    final selected = await CountryPickerSheet.show(context);
    if (selected != null && mounted) {
      setState(() => _country = selected);
      widget.onChanged?.call(widget.controller.text);
    }
  }

  String? _validateNumber(String? value) {
    final number = (value ?? '').trim();
    if (number.isEmpty) return 'Please enter your phone number';

    final invalidChars = number.replaceAll(RegExp(r'[0-9\-() ]'), '');
    if (invalidChars.isNotEmpty) return 'Please enter a valid phone number';

    final digits = _digitsOnly();
    final (minDigits, maxDigits) = CountryCodes.phoneNumberLength(_country);
    if (digits.length < minDigits || digits.length > maxDigits) {
      if (minDigits == maxDigits) {
        return 'Enter a valid ${_country.name} number ($minDigits digits)';
      }
      return 'Enter a valid ${_country.name} number ($minDigits-$maxDigits digits)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);

    return CustomTextFormField(
      controller: widget.controller,
      text: 'Phone Number',
      keyboardType: TextInputType.phone,
      onChanged: widget.onChanged,
      validator: _validateNumber,
      prefixIcon: InkWell(
        onTap: _pickCountry,
        borderRadius: BorderRadius.circular(50.r),
        child: Container(
          padding: EdgeInsets.only(left: 14.w, right: 10.w),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: colors.divider, width: 1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomText(text: _country.flag, fontSize: 18.sp),
              SizedBox(width: 6.w),
              CustomText(
                text: _country.code,
                textColor: colors.textPrimary,
                fontSize: 16.sp,
              ),
              Icon(Icons.arrow_drop_down, color: colors.textWeak, size: 22.sp),
            ],
          ),
        ),
      ),
    );
  }
}
