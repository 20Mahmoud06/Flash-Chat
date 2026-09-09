import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A sign-up that was started (auth account created) but not finished: the
/// user is on the "complete profile" or "verify phone number" (OTP) screen.
///
/// Persisted with SharedPreferences so a fully-killed app can offer to
/// resume exactly where the user left off (see WelcomeScreen).
class PendingSignup {
  final String firstName;
  final String lastName;

  /// The full international number in E.164 format, e.g. `+201001234567`.
  final String phoneNumber;

  /// Selected country dialing code, e.g. `+20`.
  final String countryCode;

  /// OTP session id (may expire; the verify screen can resend).
  final String otpId;

  const PendingSignup({
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.countryCode,
    required this.otpId,
  });

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'lastName': lastName,
        'phoneNumber': phoneNumber,
        'countryCode': countryCode,
        'otpId': otpId,
      };

  factory PendingSignup.fromJson(Map<String, dynamic> json) => PendingSignup(
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        phoneNumber: json['phoneNumber'] as String? ?? '',
        countryCode: json['countryCode'] as String? ?? '',
        otpId: json['otpId'] as String? ?? '',
      );
}

/// Stores/loads the single in-progress sign-up on this device.
class PendingSignupService {
  PendingSignupService._();
  static final PendingSignupService instance = PendingSignupService._();

  static const String _key = 'pending_signup';

  Future<void> save(PendingSignup signup) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(signup.toJson()));
  }

  Future<PendingSignup?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final signup = PendingSignup.fromJson(decoded);
      if (signup.phoneNumber.isEmpty || signup.otpId.isEmpty) return null;
      return signup;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}