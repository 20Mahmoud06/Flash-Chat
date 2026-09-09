// Shared input validators for the auth and profile forms.
//
// Returns an error message when the value is invalid, or null when it is
// valid (the contract expected by Flutter's FormField validators).

/// Validates an email address: `local@domain.tld` with a 2+ letter TLD.
/// Rejects misshapen inputs such as `a@b`, `a@b.c` or `a@b@c.com`.
String? validateEmail(String? value) {
  final email = (value ?? '').trim();
  if (email.isEmpty) return 'Please enter your email';

  final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
  if (!regex.hasMatch(email)) return 'Please enter a valid email';
  return null;
}

/// Validates a phone number (E.164-style):
/// - optional single leading '+' (country code)
/// - 7 to 15 digits in total
/// - spaces, dashes and parentheses allowed as separators
/// Rejects anything else (letters, symbols, missing digits).
String? validatePhone(String? value) {
  final phone = (value ?? '').trim();
  if (phone.isEmpty) return 'Please enter your phone number';

  final plusCount = '+'.allMatches(phone).length;
  if (plusCount > 1 || (plusCount == 1 && !phone.startsWith('+'))) {
    return 'Please enter a valid phone number';
  }

  final invalidChars = phone.replaceAll(RegExp(r'[0-9+\-() ]'), '');
  if (invalidChars.isNotEmpty) return 'Please enter a valid phone number';

  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 7 || digits.length > 15) {
    return 'Please enter a valid phone number';
  }
  return null;
}
