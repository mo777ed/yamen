import 'package:flutter/material.dart';

/// Brand tokens. Dark is the default theme.
class AppColors {
  static const bg = Color(0xFF080A12);
  static const surface = Color(0xFF111522);
  static const surfaceHigh = Color(0xFF1A1F32);
  static const border = Color(0x1FFFFFFF);
  static const primary = Color(0xFF7C5CFF);
  static const secondary = Color(0xFF3D8BFF);
  static const gold = Color(0xFFF5C451);
  static const goldDeep = Color(0xFFE59A2E);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFF9AA3B8);
  static const success = Color(0xFF34D399);
  static const danger = Color(0xFFFF5C7A);

  static const primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const goldGradient = LinearGradient(
    colors: [gold, goldDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const dangerGradient = LinearGradient(colors: [Color(0xFFFF5C7A), Color(0xFFD63B5A)]);
}

/// Colors that differ between light and dark. Read with `context.palette`.
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color text;
  final Color textMuted;

  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.text,
    required this.textMuted,
  });

  static const dark = AppPalette(
    bg: AppColors.bg,
    surface: AppColors.surface,
    surfaceHigh: AppColors.surfaceHigh,
    border: AppColors.border,
    text: AppColors.textPrimary,
    textMuted: AppColors.textMuted,
  );

  static const light = AppPalette(
    bg: Color(0xFFF4F5FA),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEDEFF7),
    border: Color(0x1F000000),
    text: Color(0xFF12141F),
    textMuted: Color(0xFF6B7488),
  );

  @override
  AppPalette copyWith({Color? bg, Color? surface, Color? surfaceHigh, Color? border, Color? text, Color? textMuted}) {
    return AppPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}

extension PaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}
