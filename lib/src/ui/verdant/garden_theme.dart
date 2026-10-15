import 'package:flutter/material.dart';

/// Shared tokens for the original Verdant Observatory interface.
abstract final class GardenTheme {
  static const background = Color(0xff0b110f);
  static const panel = Color(0xff141d18);
  static const elevated = Color(0xff1c2820);
  static const line = Color(0xff2b3b30);
  static const ink = Color(0xffedf1df);
  static const muted = Color(0xffa1afa1);
  static const acid = Color(0xffd6f77b);
  static const mint = Color(0xff71b89a);
  static const coral = Color(0xffffab86);

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      fontFamily: 'Noto Sans',
      fontFamilyFallback: const ['Noto Sans CJK SC', 'PingFang SC'],
      colorScheme: const ColorScheme.dark(
        primary: acid,
        onPrimary: background,
        secondary: mint,
        onSecondary: background,
        surface: panel,
        onSurface: ink,
        error: coral,
        onError: background,
        outline: line,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      dividerTheme: const DividerThemeData(color: line, space: 1),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 350)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: ink,
          side: const BorderSide(color: line),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: elevated,
        contentTextStyle: TextStyle(color: ink),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: acid)),
      ),
    );
  }
}
