import 'package:flutter/services.dart';

/// PiP lifecycle events reported by the native bridge in MainActivity.kt.
///
/// Unlike the old `pip` plugin (which reported only started/stopped), the
/// native side knows exactly why the PiP window closed:
/// - [NativePipEvent.started]: the activity entered PiP.
/// - [NativePipEvent.expanded]: the user expanded the window back to full
///   screen (the call must keep running).
/// - [NativePipEvent.dismissed]: the user closed the PiP window (the call
///   must be ended).
enum NativePipEvent { started, expanded, dismissed }

/// Thin wrapper over the native Channel: `flash_chat/pip` (MainActivity.kt).
///
/// Setup/start/stop are plain method calls; lifecycle events arrive on the
/// same channel and are fanned out through [onEvent].
class NativePip {
  NativePip._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final NativePip instance = NativePip._();

  static const MethodChannel _channel = MethodChannel('flash_chat/pip');

  /// Single PiP consumer (the active call page). Set to null in dispose().
  void Function(NativePipEvent event)? onEvent;

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'pipStarted':
        onEvent?.call(NativePipEvent.started);
        break;
      case 'pipExpanded':
        onEvent?.call(NativePipEvent.expanded);
        break;
      case 'pipDismissed':
        onEvent?.call(NativePipEvent.dismissed);
        break;
    }
  }

  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setup({
    double aspectRatioX = 9,
    double aspectRatioY = 16,
    bool autoEnterEnabled = true,
    bool seamlessResizeEnabled = true,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('setup', {
            'aspectRatioX': aspectRatioX,
            'aspectRatioY': aspectRatioY,
            'autoEnterEnabled': autoEnterEnabled,
            'seamlessResizeEnabled': seamlessResizeEnabled,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Enters PiP. Returns whether the system started the PiP transition.
  Future<bool> start() async {
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Clears the auto-enter flag so the app never pops into PiP from any
  /// other screen after the call page is disposed.
  Future<void> disableAutoEnter() async {
    try {
      await _channel.invokeMethod<void>('disableAutoEnter');
    } catch (_) {}
  }

  /// Flips the Android activity into "in-call" mode ([inCall] true) so it can
  /// show above the keyguard when the phone is locked — the only reason the
  /// user can accept and join a call without unlocking. Call pages enable it
  /// in initState and disable it in dispose; the app is never visible over the
  /// lock screen outside an actual call.
  Future<void> setCallMode(bool inCall) async {
    try {
      await _channel.invokeMethod<void>('setCallMode', inCall);
    } catch (_) {}
  }
}