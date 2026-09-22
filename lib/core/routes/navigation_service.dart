import 'package:flutter/material.dart';

import 'route_names.dart';

/// Global key used to access the NavigatorState from anywhere in the app,
/// necessary for handling deep links from notifications.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Tracks how many call-page routes are currently on the navigator stack so
/// the global "call in progress" pill (which renders *above* the Navigator)
/// can never push a duplicate call page on top of an existing one.
class CallRouteObserver extends NavigatorObserver {
  static final CallRouteObserver instance = CallRouteObserver._();
  CallRouteObserver._();

  /// Number of voice/video call pages currently present on the stack.
  int _openCallPages = 0;
  int get openCallPages => _openCallPages;

  /// Notifier fired whenever [_openCallPages] changes, so the pill can
  /// rebuild and hide itself as soon as a call page opens on the stack.
  final ValueNotifier<int> openCallPagesNotifier = ValueNotifier<int>(0);

  void _increment() {
    _openCallPages++;
    openCallPagesNotifier.value = _openCallPages;
  }

  void _decrement() {
    if (_openCallPages > 0) _openCallPages--;
    openCallPagesNotifier.value = _openCallPages;
  }

  static bool _isCallRoute(Route<dynamic>? route) {
    final name = route?.settings.name;
    return name == RouteNames.voiceCallPage ||
        name == RouteNames.videoCallPage;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isCallRoute(route)) _increment();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isCallRoute(route)) _decrement();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isCallRoute(route)) _decrement();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_isCallRoute(oldRoute)) _decrement();
    if (_isCallRoute(newRoute)) _increment();
  }
}
