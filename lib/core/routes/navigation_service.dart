import 'package:flutter/material.dart';

/// Global key used to access the NavigatorState from anywhere in the app,
/// necessary for handling deep links from notifications.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
