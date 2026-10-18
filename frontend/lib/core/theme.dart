import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palet Savely: hijau emerald (uang, pertumbuhan) + emas (tabungan, impian).
class AppColors {
  AppColors._();

  static const emerald = Color(0xFF10B981);
  static const emeraldDeep = Color(0xFF059669);
  static const forest = Color(0xFF064E3B);
  static const mint = Color(0xFF6EE7B7);
  static const gold = Color(0xFFF59E0B);
  static const goldSoft = Color(0xFFFCD34D);

  static const income = Color(0xFF10B981);
  static const expense = Color(0xFFF43F5E);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF065F46), Color(0xFF059669), Color(0xFF10B981)],
  );

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB45309), Color(0xFFF59E0B), Color(0xFFFCD34D)],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(seedColor: AppColors.emerald, brightness: brightness).copyWith(
      primary: isDark ? AppColors.emerald : AppColors.emeraldDeep,
      onPrimary: Colors.white,
      primaryContainer: isDark ? const Color(0xFF0D3B2E) : const Color(0xFFD1FAE5),
      onPrimaryContainer: isDark ? AppColors.mint : AppColors.forest,
      secondary: AppColors.gold,
      onSecondary: Colors.white,
      error: AppColors.expense,
      surface: isDark ? const Color(0xFF0B1210) : const Color(0xFFF4F7F5),
      onSurface: isDark ? const Color(0xFFE8F0EC) : const Color(0xFF0F1A16),
      onSurfaceVariant: isDark ? const Color(0xFF93A39D) : const Color(0xFF5B6B65),
      surfaceContainerLowest: isDark ? const Color(0xFF080D0B) : Colors.white,
      surfaceContainerLow: isDark ? const Color(0xFF131C19) : Colors.white,
      surfaceContainer: isDark ? const Color(0xFF18231F) : const Color(0xFFEEF2F0),
      surfaceContainerHigh: isDark ? const Color(0xFF1F2C27) : const Color(0xFFE6ECE9),
      surfaceContainerHighest: isDark ? const Color(0xFF26352F) : const Color(0xFFDDE5E1),
      outlineVariant: isDark ? const Color(0xFF25332E) : const Color(0xFFE2E8E5),
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      base.textTheme,
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    final radius = BorderRadius.circular(16);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        extendedTextStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        height: 70,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
