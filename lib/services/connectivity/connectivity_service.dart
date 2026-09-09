import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Singleton that tracks the device connectivity state and exposes it as a
/// [ValueNotifier] so any part of the app (Cubits, widgets, services) can
/// react instantly when the user goes online/offline.
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();

  /// `true` when the device has any active network connection.
  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(true);

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Future<void> initialize() async {
    try {
      final results = await _connectivity.checkConnectivity();
      isConnected.value = _hasConnection(results);
    } catch (e) {
      debugPrint('ConnectivityService initial check failed: $e');
    }

    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      isConnected.value = _hasConnection(results);
    });
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  void dispose() {
    _subscription?.cancel();
    isConnected.dispose();
  }
}