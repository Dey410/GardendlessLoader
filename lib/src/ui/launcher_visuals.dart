import 'package:flutter/material.dart';

class LauncherVisuals {
  const LauncherVisuals._();

  static const Color accentBlue = Color(0xff0a84ff);
  static const Color success = Color(0xff34c759);
  static const Color warning = Color(0xffff9f0a);
  static const Color danger = Color(0xffff453a);
  static const Color service = Color(0xff7c5cff);

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color pageBackground(BuildContext context) =>
      _isDark(context) ? const Color(0xff101114) : const Color(0xffeef1f6);

  static Gradient pageGradient(BuildContext context) => _isDark(context)
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff121316), Color(0xff1b1c20)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xfff8fafc), Color(0xffeef2f7), Color(0xfff7f8fb)],
          stops: [0, 0.55, 1],
        );

  static Gradient workbenchGradient(BuildContext context) => _isDark(context)
      ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xff1c1d21).withValues(alpha: 0.94),
            const Color(0xff15161a).withValues(alpha: 0.90),
          ],
        )
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.76),
            Colors.white.withValues(alpha: 0.52),
            const Color(0xfff5f7fb).withValues(alpha: 0.68),
          ],
          stops: const [0, 0.52, 1],
        );

  static Color panelBackground(BuildContext context) => _isDark(context)
      ? const Color(0xff1c1c1e).withValues(alpha: 0.86)
      : Colors.white.withValues(alpha: 0.72);

  static Color innerPanelBackground(BuildContext context) => _isDark(context)
      ? const Color(0xff242529).withValues(alpha: 0.72)
      : Colors.white.withValues(alpha: 0.54);

  static Color navigationBackground(BuildContext context) => _isDark(context)
      ? const Color(0xff17181c).withValues(alpha: 0.76)
      : const Color(0xfff6f8fc).withValues(alpha: 0.56);

  static Color selectedNavigationBackground(BuildContext context) =>
      _isDark(context)
          ? accentBlue.withValues(alpha: 0.20)
          : accentBlue.withValues(alpha: 0.12);

  static Color sidebarBorder(BuildContext context) => _isDark(context)
      ? const Color(0xff34353a).withValues(alpha: 0.62)
      : const Color(0xffd7dce6).withValues(alpha: 0.72);

  static Color glassBorder(BuildContext context) => _isDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: 0.74);

  static Color primaryText(BuildContext context) =>
      _isDark(context) ? const Color(0xfff5f5f7) : const Color(0xff1d1d1f);

  static Color secondaryText(BuildContext context) =>
      _isDark(context) ? const Color(0xffa1a1aa) : const Color(0xff6b7280);

  static Color separator(BuildContext context) =>
      _isDark(context) ? const Color(0xff38383a) : const Color(0xffd8dfe8);
}
