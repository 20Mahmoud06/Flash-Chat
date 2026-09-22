import 'package:flutter/material.dart';

/// Single source of truth for every raw color used across the app.
///
/// All hex colors live in this file or in [FcAppColors] (`app_theme.dart`) —
/// UI files reference these constants instead of writing `Color(0x…)`
/// inline. Theme-semantic colors (light/dark pairs) belong in `FcAppColors`;
/// fixed brand, call, and feedback colors belong here.
class AppColors {
  // ---- Brand ----
  static const Color primary = Colors.lightBlueAccent;
  static const Color primaryDark = Color(0xFF0288D1);
  static const Color primaryLight = Color(0xFFE0F7FA);
  static const Color sky = Color(0xFF4FC3F7);
  static const Color skySoft = Color(0xFF4FB3E0);
  static const Color skyTint = Color(0xFFE1F0FA);
  static const Color blueDeep = Color(0xFF2E7CB4);
  static const Color teal = Color(0xFF00BFA5);
  static const Color tealLight = Color(0xFF64FFDA);
  static const Color tealDeep = Color(0xFF00897B);
  static const Color tealTint = Color(0xFFE0F2F1);
  static const Color mint = Color(0xFFE8F5E9);

  // ---- Call / video UI (fixed look in both themes) ----
  static const Color callBackgroundTop = Color(0xFF0B101D);
  static const Color callBackgroundMiddle = Color(0xFF131B2E);
  static const Color callBackgroundBottom = Color(0xFF0B101D);
  static const Color callCardBg = Color(0xFF1B263B);
  static const Color callHeaderBg = Color(0xFF182236);
  static const Color callPageBackground = Color(0xFF0F0F18);
  static const Color callTileActive = Color(0xFF24324D);
  static const Color callOverlay = Color(0xFF1E1E2E);
  static const Color callAvatarBg = Color(0xFF2D2D44);
  static const Color callEndRed = Color(0xFFFF3B30);
  static const Color callErrorRed = Color(0xFFFF5252);
  static const Color callStatusSalmon = Color(0xFFFF7675);
  static const Color callStatusAmber = Color(0xFFFDCB6E);
  static const Color speakingBorder = Color(0xFF66BB6A);
  static const Color speakingGlow = Color(0xFF4CAF50);
  static const Color iosGreen = Color(0xFF34C759);
  static const Color callGlow = Colors.lightBlueAccent;
  static const Color callAccentGreen = Color(0xFF00E676);

  // ---- Feedback / misc ----
  static const Color amber = Color(0xFFFFC107);
  static const Color amberGlow = Color(0x33FFC107);
  static const Color adminGold = Color(0xFFB8860B);
  static const Color errorRed = Color(0xFFEF5350);
  static const Color errorRedDark = Color(0xFFB71C1C);
  static const Color warningOrange = Color(0xFFE65100);

  // ---- Voice recorder ----
  static const Color voiceGradientStart = Color(0xFF141D29);
  static const Color voiceGradientEnd = Color(0xFF1C2B3D);
  static const Color voiceGradientStartLight = Color(0xFFE1F5FE);
  static const Color voiceGradientEndLight = Color(0xFFF3F9FF);
  static const Color voiceActiveBlue = Color(0xFF29B6F6);
}
