import 'package:flash_chat_app/core/utils/country_codes.dart';

/// Arguments passed to the phone verification (OTP) screen.
class PhoneVerificationArguments {
  final String firstName;
  final String lastName;

  /// The full international number in E.164 format, e.g. `+201001234567`.
  final String phoneNumber;

  /// Country selected in the phone field (for display).
  final CountryCode country;

  /// OTP session ID for verification.
  final String otpId;

  const PhoneVerificationArguments({
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.country,
    required this.otpId,
  });

  /// A masked display string like `+20 ••• ••• •567`.
  String get maskedPhone {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return phoneNumber;
    final last4 = digits.substring(digits.length - 4);
    final maskCount = (digits.length - 4).clamp(3, 10);
    return '${country.code} ${'•' * maskCount} $last4';
  }
}
