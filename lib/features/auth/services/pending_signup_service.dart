import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A sign-up that was started (auth account created) but not finished: the
/// user is on the "complete profile" or "verify phone number" (OTP) screen.
///
/// Persisted to secure local storage so a fully-killed app can offer to
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
///
/// The draft — especially the [PendingSignup.otpId] OTP session id and the
/// phone number — is sensitive local data, so it lives in the OS-backed secure
/// store (Android Keystore / iOS Keychain via [FlutterSecureStorage]) instead
/// of SharedPreferences.
///
/// Drafts written by older app versions (which used SharedPreferences) are
/// migrated to the secure store automatically on the first [load]; the legacy
/// key is then removed.
class PendingSignupService {
  PendingSignupService._();
  static final PendingSignupService instance = PendingSignupService._();

  static const String _key = 'pending_signup';
  static const String _legacyPrefsKey = 'pending_signup';

  static const FlutterSecureStorage _secureStore = FlutterSecureStorage();

  Future<void> save(PendingSignup signup) async {
    await _secureStore.write(key: _key, value: jsonEncode(signup.toJson()));
    await _deleteLegacyPrefs();
  }

  Future<PendingSignup?> load() async {
    final secureRaw = await _secureStore.read(key: _key);
    if (secureRaw != null && secureRaw.isNotEmpty) {
      return _parse(secureRaw);
    }

    // Migrate a draft persisted by an older build that stored it in
    // SharedPreferences. Promotion keeps the atomic single-source draft.
    final legacy = await _readLegacyPrefs();
    if (legacy != null) {
      await save(legacy);
    }
    return legacy;
  }

  Future<void> clear() async {
    await _secureStore.delete(key: _key);
    await _deleteLegacyPrefs();
  }

  PendingSignup? _parse(String raw) {
    if (raw.isEmpty) return null;
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

  Future<PendingSignup?> _readLegacyPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyPrefsKey);
      if (raw == null || raw.isEmpty) return null;
      return _parse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteLegacyPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyPrefsKey);
    } catch (_) {
      // Best-effort cleanup; a stale prefs draft must never break the flow.
    }
  }
}