import 'package:flutter/material.dart';

/// Semantic colors for Flash Chat — every hardcoded UI color in the app maps
/// to one of these so the whole app adapts to light / dark (night) mode.
class FcAppColors extends ThemeExtension<FcAppColors> {
  /// Chat / list screen background (was `Colors.grey.shade200`).
  final Color screen;

  /// Card / container / sheet surface (was `Colors.white`).
  final Color surface;

  /// Muted surfaces — subtle fills, header banners (was `Colors.grey.shade100`).
  final Color surfaceMuted;

  /// Slightly darker muted surface — dividers, soft shadows area (was `Colors.grey.shade300`).
  final Color surfaceDim;

  /// Text field fill (was `Colors.grey.shade200`).
  final Color inputFill;

  /// Top banners / chip backgrounds (was `Colors.grey.shade200`).
  final Color header;

  /// Primary text (was `Colors.black87` / `Colors.grey.shade900`).
  final Color textPrimary;

  /// Secondary text (was `Colors.grey.shade600` / `Colors.grey.shade700`).
  final Color textSecondary;

  /// Weak / hint text and muted icons (was `Colors.grey.shade500` / `grey.shade400`).
  final Color textWeak;

  /// Divider / border lines (was `Colors.grey.shade300` / `Colors.black54`).
  final Color divider;

  /// "My" chat bubble background (was `Colors.lightBlueAccent`).
  final Color bubbleMine;

  /// Other user's chat bubble background (was `Colors.white`).
  final Color bubbleOther;

  /// Text color inside "my" chat bubble.
  final Color bubbleMineText;

  /// Text color inside other user's chat bubble (was `Colors.black87`).
  final Color bubbleOtherText;

  /// Avatar / icon tint backgrounds (was `Colors.lightBlue.shade50`).
  final Color avatarBackground;

  /// Card / tile background (was `Colors.grey.shade200`).
  final Color tile;

  const FcAppColors({
    required this.screen,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceDim,
    required this.inputFill,
    required this.header,
    required this.textPrimary,
    required this.textSecondary,
    required this.textWeak,
    required this.divider,
    required this.bubbleMine,
    required this.bubbleOther,
    required this.bubbleMineText,
    required this.bubbleOtherText,
    required this.avatarBackground,
    required this.tile,
  });

  static const FcAppColors light = FcAppColors(
    screen: Color(0xFFF0F2F5),
    surface: Colors.white,
    surfaceMuted: Color(0xFFF3F4F6),
    surfaceDim: Color(0xFFE3E6EA),
    inputFill: Color(0xFFF1F3F5),
    header: Color(0xFFE4E7EB),
    textPrimary: Color(0xFF212121),
    textSecondary: Color(0xFF616161),
    textWeak: Color(0xFF9E9E9E),
    divider: Color(0xFFE0E0E0),
    bubbleMine: Colors.lightBlueAccent,
    bubbleOther: Colors.white,
    bubbleMineText: Colors.white,
    bubbleOtherText: Color(0xFF212121),
    avatarBackground: Color(0xFFE1F0FA),
    tile: Color(0xFFF1F3F5),
  );

  static const FcAppColors dark = FcAppColors(
    screen: Color(0xFF101418),
    surface: Color(0xFF171C22),
    surfaceMuted: Color(0xFF222833),
    surfaceDim: Color(0xFF2C333E),
    inputFill: Color(0xFF2A3039),
    header: Color(0xFF262C35),
    textPrimary: Color(0xFFE8EAED),
    textSecondary: Color(0xFFA6ADB6),
    textWeak: Color(0xFF7A828D),
    divider: Color(0xFF313944),
    bubbleMine: Color(0xFF2E7CB4),
    bubbleOther: Color(0xFF232932),
    bubbleMineText: Colors.white,
    bubbleOtherText: Color(0xFFE8EAED),
    avatarBackground: Color(0xFF24384A),
    tile: Color(0xFF222833),
  );

  static FcAppColors of(BuildContext context) =>
      Theme.of(context).extension<FcAppColors>() ?? FcAppColors.light;

  @override
  FcAppColors copyWith({
    Color? screen,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceDim,
    Color? inputFill,
    Color? header,
    Color? textPrimary,
    Color? textSecondary,
    Color? textWeak,
    Color? divider,
    Color? bubbleMine,
    Color? bubbleOther,
    Color? bubbleMineText,
    Color? bubbleOtherText,
    Color? avatarBackground,
    Color? tile,
  }) {
    return FcAppColors(
      screen: screen ?? this.screen,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceDim: surfaceDim ?? this.surfaceDim,
      inputFill: inputFill ?? this.inputFill,
      header: header ?? this.header,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textWeak: textWeak ?? this.textWeak,
      divider: divider ?? this.divider,
      bubbleMine: bubbleMine ?? this.bubbleMine,
      bubbleOther: bubbleOther ?? this.bubbleOther,
      bubbleMineText: bubbleMineText ?? this.bubbleMineText,
      bubbleOtherText: bubbleOtherText ?? this.bubbleOtherText,
      avatarBackground: avatarBackground ?? this.avatarBackground,
      tile: tile ?? this.tile,
    );
  }

  @override
  FcAppColors lerp(ThemeExtension<FcAppColors>? other, double t) {
    if (other is! FcAppColors) return this;
    return FcAppColors(
      screen: Color.lerp(screen, other.screen, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceDim: Color.lerp(surfaceDim, other.surfaceDim, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      header: Color.lerp(header, other.header, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textWeak: Color.lerp(textWeak, other.textWeak, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      bubbleMine: Color.lerp(bubbleMine, other.bubbleMine, t)!,
      bubbleOther: Color.lerp(bubbleOther, other.bubbleOther, t)!,
      bubbleMineText: Color.lerp(bubbleMineText, other.bubbleMineText, t)!,
      bubbleOtherText: Color.lerp(bubbleOtherText, other.bubbleOtherText, t)!,
      avatarBackground: Color.lerp(avatarBackground, other.avatarBackground, t)!,
      tile: Color.lerp(tile, other.tile, t)!,
    );
  }
}

class AppTheme {
  static final ThemeData light = _build(FcAppColors.light, Brightness.light);

  static final ThemeData dark = _build(FcAppColors.dark, Brightness.dark);

  static ThemeData _build(FcAppColors colors, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.lightBlueAccent,
      brightness: brightness,
      primary: Colors.lightBlueAccent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.screen,
      canvasColor: colors.surface,
      extensions: [colors],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.lightBlueAccent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        contentTextStyle: TextStyle(color: colors.textSecondary, fontSize: 14),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.inputFill,
        hintStyle: TextStyle(color: colors.textWeak),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.lightBlueAccent, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.fixed,
        backgroundColor: isDark ? const Color(0xFF333A45) : Colors.black87,
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? Colors.lightBlueAccent.shade100 : Colors.lightBlueAccent,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.lightBlueAccent,
          foregroundColor: Colors.white,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Colors.lightBlueAccent,
        foregroundColor: Colors.white,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        textColor: colors.textPrimary,
        subtitleTextStyle: TextStyle(color: colors.textSecondary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.lightBlueAccent
              : colors.surfaceDim,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Colors.lightBlueAccent,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: isDark ? Colors.lightBlueAccent.shade100 : Colors.lightBlueAccent,
        unselectedLabelColor: colors.textSecondary,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: Colors.lightBlueAccent,
        selectionColor: Colors.lightBlueAccent.withValues(alpha: 0.3),
        selectionHandleColor: Colors.lightBlueAccent,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}