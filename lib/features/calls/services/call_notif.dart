import 'package:flutter/services.dart';

/// Actions the sticky voice-call notification can send back from native
/// (CallControlReceiver in CallNotification.kt).
enum CallNotifAction { mute, end, open }

/// Thin wrapper over the native channel `flash_chat/call_notification`
/// (MainActivity.kt + CallNotification.kt).
///
/// Voice calls show a sticky ongoing notification (live elapsed time + mute /
/// end actions) when the call page is left; video calls use the PiP window
/// instead and never touch this.
class CallNotifBridge {
  CallNotifBridge._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final CallNotifBridge instance = CallNotifBridge._();

  static const MethodChannel _channel =
      MethodChannel('flash_chat/call_notification');

  /// Single consumer of the native notification actions (registered in
  /// main.dart so it works even after the call page was popped).
  void Function(CallNotifAction action, String callId)? onAction;

  bool _active = false;
  bool get isActive => _active;

  Future<void> _handleNativeCall(MethodCall call) async {
    final action = switch (call.method) {
      'mute' => CallNotifAction.mute,
      'end' => CallNotifAction.end,
      'open' => CallNotifAction.open,
      _ => null,
    };
    if (action == null) return;
    final callId = (call.arguments as Map<dynamic, dynamic>?)?['callId'] as String?;
    onAction?.call(action, callId ?? '');
  }

  /// Shows the sticky ongoing call notification with a live 1s time ticker
  /// (ticked natively). [startTimeMs] is the moment the call connected.
  Future<void> show({
    required String callId,
    required String title,
    required int startTimeMs,
  }) async {
    _active = true;
    try {
      await _channel.invokeMethod<void>('show', {
        'callId': callId,
        'title': title,
        'startTimeMs': startTimeMs,
      });
    } catch (_) {}
  }

  /// Updates the mute/unmute action label on the notification.
  Future<void> updateMute(bool muted) async {
    if (!_active) return;
    try {
      await _channel.invokeMethod<void>('setMuted', muted);
    } catch (_) {}
  }

  /// Removes the notification (call ended / page restored).
  ///
  /// Always forwards to native, even when this Dart instance never showed it:
  /// the notification survives a process restart (it is `ongoing`, so it
  /// cannot be swiped away), and a call cannot outlive the process that hosted
  /// its engine, so a leftover here is always stale and must be cancelled.
  Future<void> hide() async {
    _active = false;
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (_) {}
  }

  /// Called once at app startup to clear any sticky ongoing-call notification
  /// left behind by a previous process (e.g. the OS killed the app while a
  /// voice call was minimized). See [hide].
  Future<void> reconcileOnStartup() => hide();
}