import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/garden_theme.dart';

/// Quiet, static backdrop for the home page: two soft glows in the icon's
/// green and blue and a faint dot grid that fades out toward the edges.
/// It never animates, so it costs one paint per size or theme change.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _AmbientPainter(context.garden),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter(this.palette);

  final GardenPalette palette;

  // The blue of the app icon's lightning, tuned per theme.
  Color get _blue =>
      palette.isDark ? const Color(0xff3aa8ff) : const Color(0xff2563eb);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final strength = palette.isDark ? 1.0 : 1.4;

    _glow(
      canvas,
      Offset(w * 0.22, h * 0.78),
      math.max(w, h) * 0.55,
      palette.accent.withValues(alpha: 0.11 * strength),
    );
    _glow(
      canvas,
      Offset(w * 0.92, h * 0.08),
      math.max(w, h) * 0.5,
      _blue.withValues(alpha: 0.09 * strength),
    );

    const spacing = 24.0;
    final focus = Offset(w * 0.3, h * 0.62);
    final reach = math.max(w, h) * 0.75;
    final dot = Paint();
    final baseAlpha = palette.isDark ? 0.09 : 0.1;
    for (var y = spacing / 2; y < h; y += spacing) {
      for (var x = spacing / 2; x < w; x += spacing) {
        final distance = (Offset(x, y) - focus).distance / reach;
        if (distance >= 1) continue;
        final fade = 1 - distance * distance;
        dot.color = palette.ink.withValues(alpha: baseAlpha * fade);
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }
  }

  void _glow(Canvas canvas, Offset center, double radius, Color color) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
