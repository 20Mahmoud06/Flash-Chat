import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_state.dart';

export 'theme_state.dart';

/// Controls the app theme (light / dark / system) and persists the user's
/// choice so night mode survives app restarts.
class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit() : super(const ThemeState(ThemeMode.system)) {
    _loadSavedMode();
  }

  static const String _prefKey = 'theme_mode';

  Future<void> _loadSavedMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == null || isClosed) return;
      final mode = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.system,
      );
      if (state.mode != mode) emit(ThemeState(mode));
    } catch (_) {
      // Keep system default if prefs fail.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (isClosed) return;
    emit(ThemeState(mode));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  /// Convenience for a simple light/dark switch.
  Future<void> setDarkMode(bool dark) =>
      setMode(dark ? ThemeMode.dark : ThemeMode.light);

  bool get isDarkMode => state.mode == ThemeMode.dark;
}
