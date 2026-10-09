import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/fcm/fcm_service.dart';

/// Drives the one-time "permissions" onboarding gate shown on first app use.
///
/// The gate is a pure UX helper: it never blocks the app and never decides
/// whether calls / notifications can run — it simply asks the user nicely for
/// the permissions that make incoming chat alerts and call rings reliable, and
/// remembers that it already asked so it only appears once (the user can still
/// change anything later in system Settings).
///
/// Platform notes (all SDK branching is done internally by the plugins, so
/// this service needs no extra device-info dependency):
///   * Notifications: `permission_handler` auto-grants on Android < 13 (no
///     dialog), shows the system dialog on Android 13+ and iOS.
///   * Full-screen calls: `flutter_callkit_incoming.canUseFullScreenIntent()`
///     returns true on Android < 14 (setting does not exist yet) and reflects
///     the real state on 14+; `requestFullIntentPermission()` opens the system
///     "full-screen notifications" settings screen on 14+ and is a no-op below.
class OnboardingPermissions {
  OnboardingPermissions._();

  static final OnboardingPermissions instance = OnboardingPermissions._();

  /// Persisted marker so the onboarding is shown exactly once per device.
  static const String _shownKey = 'onboarding_permissions_shown';

  /// Tracks whether the user explicitly denied a permission during onboarding.
  /// Once denied we never re-prompt automatically — the user must go to
  /// Settings / Profile to enable it.
  static const String _notifDeniedKey = 'onboarding_notifications_denied';

  bool? _cachedShown;

  /// Whether the onboarding should present itself.
  ///
  /// Shows on first run ever, and ALSO re-offers itself whenever the device
  /// still lacks the notification permission but the user never explicitly
  /// declined. The second branch guards against a stale "shown" marker that
  /// survives an app-data backup / restore (or any other cache hiccup): it
  /// used to leave Android 13+ devices with notifications and call rings
  /// permanently off and no prompt ever appearing again.
  Future<bool> shouldShow() async {
    if (_cachedShown != null) return _decide(_cachedShown!);
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedShown = prefs.getBool(_shownKey) ?? false;
    } catch (_) {
      _cachedShown = false;
    }
    return _decide(_cachedShown!);
  }

  Future<bool> _decide(bool markedShown) async {
    if (!markedShown) return true;
    // Never re-prompt after an explicit decline or skip.
    if (await wasNotificationsDenied()) return false;
    if (!_isAppPlatform) return false;
    if (await notificationsGranted()) return false;
    // Marked shown, never denied, but notifications are off on this device —
    // present the onboarding again so the user isn't silently missing alerts.
    return true;
  }

  /// Marks the onboarding as done; safe to call more than once.
  Future<void> markShown() async {
    _cachedShown = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_shownKey, true);
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  /// Marks that the user explicitly denied the notification permission
  /// during onboarding so the app knows not to re-prompt automatically.
  Future<void> markNotificationsDenied() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_notifDeniedKey, true);
    } catch (_) {}
  }

  /// Whether the user explicitly denied notifications during onboarding.
  Future<bool> wasNotificationsDenied() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_notifDeniedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Clears the "denied" flag — useful when the user manually enables
  /// notifications from the profile toggle or app settings.
  Future<void> clearNotificationsDenied() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_notifDeniedKey);
    } catch (_) {}
  }

  // ---------------- Platform permission state ----------------

  bool get _isAppPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Notifications permission on Android / iOS (auto-granted below Android 13).
  Future<bool> notificationsGranted() async {
    if (!_isAppPlatform) return true;
    try {
      final status = await ph.Permission.notification.status;
      return status.isGranted || status.isLimited;
    } catch (_) {
      return false;
    }
  }

  /// Full-screen call ring permission. Only meaningful on Android 14+; on all
  /// other platforms there is no such setting so this is treated as granted.
  Future<bool> fullScreenIntentGranted() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        return await FlutterCallkitIncoming.canUseFullScreenIntent() ?? false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Shows the system notification permission dialog (Android / iOS).
  Future<bool> requestNotifications() async {
    if (!_isAppPlatform) return true;
    try {
      final status = await ph.Permission.notification.request();
      return status.isGranted || status.isLimited;
    } catch (_) {
      return false;
    }
  }

  /// Opens the Android 14+ "full-screen notifications" settings screen.
  /// No-op on other platforms (returns current state).
  Future<bool> requestFullScreenIntent() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {
      // Swallow: some OEM launchers hide this setting; the ring still uses the
      // standard notification fallback then.
    }
    return fullScreenIntentGranted();
  }

  /// Opens the OS-level app settings so the user can manually toggle
  /// notification permission. Works on both Android and iOS.
  Future<bool> openAppSettings() async {
    try {
      return await ph.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  /// Convenience: request notification permission through FCM service
  /// (handles both FCM token save and local notification channel).
  Future<bool> requestFullNotificationPermission() async {
    return FcmService.requestNotificationPermission();
  }
}
