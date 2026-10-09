import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How far a sign-up got before the user walked away.
enum PendingSignupStep {
  /// The auth account exists but the user has not submitted their profile yet
  /// (name + phone), so no OTP was ever requested.
  profile,

  /// The profile was submitted and an OTP was emailed; the code still has to
  /// be entered (or re-requested if it expired).
  otp,
}

/// A sign-up that was started (auth account created) but not finished.
///
/// Written the moment the account is created and updated as the user
/// progresses, so a fully-killed app can offer to resume exactly where the
/// user left off. The [uid] ties the draft to one specific auth account: it is
/// the only reliable way to tell a *new, half-finished* sign-up apart from a
/// legacy account that has a name-less push-token shell document and must
/// still be allowed straight into the app.
class PendingSignup {
  /// The auth account this draft belongs to. Empty for drafts written by older
  /// app versions, which are then assumed to belong to the signed-in user.
  final String uid;

  /// How far the user got before the app was closed.
  final PendingSignupStep step;

  final String firstName;
  final String lastName;

  /// The full international number in E.164 format, e.g. `+201001234567`.
  final String phoneNumber;

  /// Selected country dialing code, e.g. `+20`.
  final String countryCode;

  /// OTP session id. Empty while [step] is [PendingSignupStep.profile].
  final String otpId;

  const PendingSignup({
    required this.uid,
    required this.step,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.countryCode,
    required this.otpId,
  });

  /// A draft for a brand-new account that has not submitted a profile yet.
  const PendingSignup.atProfile({
    required this.uid,
    this.firstName = '',
    this.lastName = '',
  })  : step = PendingSignupStep.profile,
        phoneNumber = '',
        countryCode = '',
        otpId = '';

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'step': step.name,
        'firstName': firstName,
        'lastName': lastName,
        'phoneNumber': phoneNumber,
        'countryCode': countryCode,
        'otpId': otpId,
      };

  factory PendingSignup.fromJson(Map<String, dynamic> json) {
    // Drafts written before [PendingSignupStep] existed always carried a
    // phone number AND an otpId, so they belong to the OTP step.
    final step = switch (json['step'] as String?) {
      'profile' => PendingSignupStep.profile,
      'otp' => PendingSignupStep.otp,
      _ => PendingSignupStep.otp,
    };
    return PendingSignup(
      uid: json['uid'] as String? ?? '',
      step: step,
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      countryCode: json['countryCode'] as String? ?? '',
      otpId: json['otpId'] as String? ?? '',
    );
  }

  /// The same draft advanced to the OTP step once a code has been requested.
  ///
  /// [phoneNumber] is required rather than inherited: an OTP draft without a
  /// phone number is unusable (there is nothing to re-request a code for), and
  /// a profile-step draft carries none, so inheriting it would silently
  /// produce a draft that fails [isUsable].
  PendingSignup withOtp({
    required String otpId,
    required String phoneNumber,
    String countryCode = '',
  }) =>
      PendingSignup(
        uid: uid,
        step: PendingSignupStep.otp,
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        countryCode: countryCode,
        otpId: otpId,
      );

  /// The stored draft is only usable if it has enough data for its step: a
  /// profile draft needs nothing, an OTP draft needs the phone number (to
  /// re-request a code) and a session id.
  bool get isUsable => switch (step) {
        PendingSignupStep.profile => true,
        PendingSignupStep.otp => phoneNumber.isNotEmpty && otpId.isNotEmpty,
      };
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
      if (!signup.isUsable) return null;
      return signup;
    } catch (_) {
      return null;
    }
  }

  /// The draft that belongs to [uid], or null when this device is not holding
  /// an unfinished sign-up for that account.
  ///
  /// A draft whose [PendingSignup.uid] is empty was written by an older build
  /// that did not record it; it is only honoured for the currently signed-in
  /// account, and only while that account has no completed profile — so a
  /// stale draft can never re-open onboarding for a finished user.
  Future<PendingSignup?> loadFor(String uid) async {
    final draft = await load();
    if (draft == null) return null;
    if (draft.uid.isEmpty) return draft;
    return draft.uid == uid ? draft : null;
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
