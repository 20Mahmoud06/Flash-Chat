import 'package:flutter/services.dart';

/// Formats an Egyptian phone number as "010 1234 5678".
/// Non-digit characters (spaces, dashes, etc.) are stripped first, so already
/// formatted or mixed input is handled gracefully.
String formatEgyptianPhone(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length <= 3) return digits;
  if (digits.length <= 7) {
    return '${digits.substring(0, 3)} ${digits.substring(3)}';
  }
  return '${digits.substring(0, 3)} ${digits.substring(3, 7)} ${digits.substring(7)}';
}

/// Formats a stored contact number for display, keeping the country code as a
/// "+20" prefix when present so it's obvious whether the number is
/// international or local. "+20" is the same as the leading "0", so it is
/// shown only once.
///
///   "+01012345678"   → "+20 10 1234 5678"
///   "+201012345678"  → "+20 10 1234 5678"
///   "01012345678"    → "010 1234 5678"
String formatPhoneForDisplay(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  final hasPlus = trimmed.startsWith('+');
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

  // "01012345678" — local Egyptian number, no country code.
  if (!hasPlus && digits.length == 11 && digits.startsWith('0')) {
    return formatEgyptianPhone(digits);
  }

  // "+201012345678" (or "201012345678") — E.164 with the "20" prefix.
  if (digits.length >= 12 && digits.startsWith('20')) {
    return '+20 ${_formatLocalWithoutZero(digits.substring(2))}';
  }

  // "+01012345678" — Egyptian mobile with a stray '+' instead of the real
  // country code; the leading "0" counts as the "+20".
  if (hasPlus && digits.length == 11 && digits.startsWith('0')) {
    return '+20 ${_formatLocalWithoutZero(digits.substring(1))}';
  }

  if (!hasPlus) return formatEgyptianPhone(digits);

  // Any other international number: keep "+" and the digits verbatim as a safe
  // fallback so nothing gets mangled.
  return '+$digits';
}

/// Groups the 10-digit local part (leading 0 already removed) as
/// "10 1234 5678".
String _formatLocalWithoutZero(String value) {
  final local = value.startsWith('0') ? value.substring(1) : value;
  if (local.length >= 7) {
    return '${local.substring(0, 2)} ${local.substring(2, 6)} '
        '${local.substring(6)}';
  }
  return local;
}

class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    // Remove all non-digit characters
    String text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // Limit to 11 digits
    if (text.length > 11) {
      text = text.substring(0, 11);
    }

    // Format as: 010 1234 5678
    String formatted = text;
    if (text.length > 3) {
      formatted = '${text.substring(0, 3)} ${text.substring(3)}';
    }
    if (text.length > 7) {
      formatted = '${text.substring(0, 3)} ${text.substring(3, 7)} ${text.substring(7)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}