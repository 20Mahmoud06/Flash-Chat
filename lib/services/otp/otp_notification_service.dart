import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Delivers the locally-generated OTP via a local (on-device) notification.
///
/// The OTP itself is generated and verified by [OtpService]; this service is
/// only responsible for showing it as a local notification so the user can
/// read the code.
///
/// It lazily initializes a dedicated notification channel on first use. It is
/// safe to call repeatedly — initialization is idempotent.
class OtpNotificationService {
  OtpNotificationService._();
  static final OtpNotificationService instance = OtpNotificationService._();

  static const String _channelId = 'otp_verification';
  static const String _channelName = 'Phone Verification';
  static const String _channelDescription =
      'Local notifications for phone verification codes';

  /// A fixed id so a resent code replaces the previous OTP notification.
  static const int _notificationId = 900001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Creates the OTP notification channel without calling [initialize].
  ///
  /// The native plugin is already initialized by [FcmService] at app startup.
  /// Calling `initialize` a second time would overwrite the notification-tap
  /// handler that FcmService registered on the shared native method channel,
  /// so we only create our dedicated channel here.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Requests the notification permission when needed (Android 13+).
  Future<bool> ensurePermission() async {
    await _ensureInitialized();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final granted =
        await androidPlugin?.requestNotificationsPermission() ?? true;
    return granted;
  }

  /// Shows a local notification containing [code]. Returns `true` when the
  /// notification was actually displayed.
  Future<bool> showOtp({required String code}) async {
    await _ensureInitialized();

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    var canShow = await androidPlugin?.areNotificationsEnabled() ?? true;

    if (!canShow) {
      // Try to obtain the permission once; if the user still refuses, we
      // gracefully skip showing (the code remains in Firestore for manual
      // entry through resend).
      canShow =
          await androidPlugin?.requestNotificationsPermission() ?? true;
    }

    if (!canShow) {
      debugPrint('[OTP] Notification permission not granted — cannot show code.');
      return false;
    }

    const details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    await _plugin.show(
      _notificationId,
      'Phone Verification',
      'Your verification code is $code',
      const NotificationDetails(android: details),
    );
    return true;
  }
}
