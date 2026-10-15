import 'package:flutter/material.dart';

/// Neutral surfaces, one accent (the green of the app icon) and two status
/// colours. Everything else is expressed through weight, size and spacing.
class GardenPalette extends ThemeExtension<GardenPalette> {
  const GardenPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.warning,
  });

  static const dark = GardenPalette(
    brightness: Brightness.dark,
    background: Color(0xff0e0f11),
    surface: Color(0xff16171a),
    surfaceMuted: Color(0xff1f2024),
    border: Color(0xff2a2b30),
    ink: Color(0xfff2f2f3),
    inkMuted: Color(0xff9a9ba1),
    inkFaint: Color(0xff606168),
    accent: Color(0xff4ade80),
    onAccent: Color(0xff07210f),
    danger: Color(0xfff87171),
    warning: Color(0xfffbbf24),
  );

  static const light = GardenPalette(
    brightness: Brightness.light,
    background: Color(0xfff5f5f6),
    surface: Color(0xffffffff),
    surfaceMuted: Color(0xfff0f0f2),
    border: Color(0xffe4e4e7),
    ink: Color(0xff111113),
    inkMuted: Color(0xff6b6b73),
    inkFaint: Color(0xffa1a1aa),
    accent: Color(0xff16a34a),
    onAccent: Colors.white,
    danger: Color(0xffdc2626),
    warning: Color(0xffd97706),
  );

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color accent;
  final Color onAccent;
  final Color danger;
  final Color warning;

  bool get isDark => brightness == Brightness.dark;

  @override
  GardenPalette copyWith() => this;

  @override
  GardenPalette lerp(GardenPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return GardenPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      border: c(border, other.border),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      inkFaint: c(inkFaint, other.inkFaint),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      danger: c(danger, other.danger),
      warning: c(warning, other.warning),
    );
  }
}

extension GardenContext on BuildContext {
  GardenPalette get garden =>
      Theme.of(this).extension<GardenPalette>() ?? GardenPalette.dark;
}

/// Strong ease-out curves and short durations: controls answer the touch
/// immediately and nothing in the launcher runs longer than 240ms.
class GardenMotion {
  const GardenMotion._();

  static const easeOut = Cubic(0.23, 1, 0.32, 1);

  static const press = Duration(milliseconds: 120);
  static const quick = Duration(milliseconds: 160);
  static const panel = Duration(milliseconds: 220);
}

/// Exposes the effective reduce-motion flag (system setting or the
/// launcher's own preference) to every widget below the shell.
class GardenMotionScope extends InheritedWidget {
  const GardenMotionScope({
    super.key,
    required this.reduceMotion,
    required super.child,
  });

  final bool reduceMotion;

  static bool reduced(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GardenMotionScope>();
    final system = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return system || (scope?.reduceMotion ?? false);
  }

  @override
  bool updateShouldNotify(GardenMotionScope oldWidget) =>
      oldWidget.reduceMotion != reduceMotion;
}

class GardenType {
  const GardenType._();

  static const monoFamily = 'JetBrainsMono';

  static TextStyle title(double size, {Color? color}) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.02 * size,
        height: 1.15,
        color: color,
      );

  static TextStyle mono(double size, {FontWeight? weight, Color? color}) =>
      TextStyle(
        fontFamily: monoFamily,
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        color: color,
        height: 1.45,
      );
}

ThemeData buildGardenTheme(Brightness brightness) {
  final palette =
      brightness == Brightness.dark ? GardenPalette.dark : GardenPalette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.accent,
    brightness: brightness,
  ).copyWith(
    primary: palette.accent,
    onPrimary: palette.onAccent,
    error: palette.danger,
    surface: palette.surface,
    onSurface: palette.ink,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    extensions: [palette],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: palette.ink,
      displayColor: palette.ink,
    ),
    dividerTheme: DividerThemeData(color: palette.border, space: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.onAccent
            : palette.inkMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.accent
            : palette.surfaceMuted,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : palette.border,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: palette.isDark ? const Color(0xff2a2b30) : palette.ink,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      width: 400,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.border),
      ),
      titleTextStyle: GardenType.title(18, color: palette.ink),
      contentTextStyle: TextStyle(
        color: palette.inkMuted,
        fontSize: 14,
        height: 1.5,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.isDark ? const Color(0xff2a2b30) : palette.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.border),
      ),
      textStyle: TextStyle(color: palette.ink, fontSize: 14),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(palette.inkFaint.withValues(
        alpha: 0.5,
      )),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(4),
    ),
  );
}
