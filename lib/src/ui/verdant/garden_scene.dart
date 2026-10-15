import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'garden_theme.dart';

/// Resolution-independent artwork. No game assets, network images or shaders.
/// Only the entrance animates; idle screens do not continuously repaint.
class GardenScene extends StatefulWidget {
  const GardenScene({super.key, this.motion = true});
  final bool motion;

  @override
  State<GardenScene> createState() => _GardenSceneState();
}

class _GardenSceneState extends State<GardenScene> with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1200),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant GardenScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion != widget.motion) _syncMotion();
  }

  void _syncMotion() {
    if (!widget.motion || MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _entrance,
        builder: (context, child) => Opacity(
          opacity: Curves.easeOut.transform(_entrance.value),
          child: Transform.translate(
            offset: Offset(0, 22 * (1 - Curves.easeOutCubic.transform(_entrance.value))),
            child: child,
          ),
        ),
        child: const CustomPaint(painter: _GardenPainter(), size: Size(600, 500)),
      ),
    ),
  );
}

class _GardenPainter extends CustomPainter {
  const _GardenPainter();
  static const _green = Color(0xff377d59);

  Paint _fill(Color color) => Paint()..color = color;
  Paint _stroke(Color color, [double width = 1]) => Paint()
    ..color = color..style = PaintingStyle.stroke..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 600, size.height / 500);
    canvas.save();
    canvas.translate((size.width - 600 * scale) / 2, (size.height - 500 * scale) / 2);
    canvas.scale(scale);
    final glow = const RadialGradient(colors: [Color(0x394e8550), Color(0x004e8550)]);
    canvas.drawCircle(const Offset(326, 249), 243,
      Paint()..shader = glow.createShader(const Rect.fromLTWH(83, 6, 486, 486)));
    // Observatory coordinates and suspended orbit.
    for (var x = 68; x < 565; x += 25) {
      for (var y = 52; y < 440; y += 25) {
        canvas.drawCircle(Offset(x.toDouble(), y.toDouble()), .7, _fill(const Color(0x306d8f6c)));
      }
    }
    canvas.save();
    canvas.translate(326, 255);
    canvas.rotate(-.42);
    canvas.drawOval(const Rect.fromLTWH(-230, -143, 460, 286), _stroke(const Color(0x50718d61)));
    canvas.drawOval(const Rect.fromLTWH(-237, -149, 474, 298), _stroke(const Color(0x186f8f6d)));
    canvas.restore();
    canvas.drawLine(const Offset(326, 28), const Offset(326, 456), _stroke(const Color(0x164f7458)));
    // Layered, softly lit floating island.
    canvas.drawOval(const Rect.fromLTWH(126, 409, 391, 37),
      Paint()..shader = const RadialGradient(colors: [Color(0x99325835), Color(0x00325835)])
        .createShader(const Rect.fromLTWH(126, 382, 391, 100)));
    final base = Path()..moveTo(126, 356)..cubicTo(149, 464, 478, 482, 505, 356)
      ..close();
    canvas.drawPath(base, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xff315c40), Color(0xff0c2017)],
    ).createShader(const Rect.fromLTWH(126, 350, 379, 106)));
    for (var i = 0; i < 5; i++) {
      canvas.drawArc(Rect.fromLTWH(135.0 + i * 3, 345.0 + i * 12, 361.0 - i * 6, 67),
        0, math.pi, false, _stroke(const Color(0x204f8d50)));
    }
    canvas.drawOval(const Rect.fromLTWH(126, 309, 379, 108),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xff789953), Color(0xff264c35), Color(0xff153321)],
      ).createShader(const Rect.fromLTWH(126, 309, 379, 108)));
    canvas.drawOval(const Rect.fromLTWH(126, 309, 379, 108), _stroke(const Color(0x8bb3d785), 1.2));
    // Tall leaves: each is a curved, shaded blade with a central vein.
    _leaf(canvas, const Offset(330, 358), -1.1, 172, 48, const Color(0xff4b9b68));
    _leaf(canvas, const Offset(333, 357), -.67, 169, 57, const Color(0xff29674a));
    _leaf(canvas, const Offset(331, 357), -.21, 126, 47, const Color(0xff72aa63));
    _leaf(canvas, const Offset(293, 359), 1.05, 150, 42, const Color(0xff6da85c));
    _leaf(canvas, const Offset(293, 355), .53, 171, 48, const Color(0xff317754));
    // Sculptural sunflower, an optimistic focal point rather than a game asset.
    final stem = Path()..moveTo(350, 354)..cubicTo(337, 284, 398, 214, 389, 152);
    canvas.drawPath(stem, _stroke(const Color(0xff367c51), 12));
    canvas.drawPath(stem, _stroke(const Color(0xff86b776), 2));
    _leaf(canvas, const Offset(356, 270), 1.15, 88, 30, const Color(0xff96bf6d));
    _leaf(canvas, const Offset(374, 237), -1.22, 86, 32, const Color(0xff528f5b));
    canvas.save();
    canvas.translate(389, 153);
    for (var i = 0; i < 12; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 6);
      canvas.drawOval(const Rect.fromLTWH(-17, -78, 34, 66),
        Paint()..shader = const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xffe4f997), Color(0xffa4c75d)],
        ).createShader(const Rect.fromLTWH(-17, -78, 34, 66)));
      canvas.drawLine(const Offset(0, -65), const Offset(0, -32), _stroke(const Color(0x50709238)));
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, 34, _fill(const Color(0xff172b1c)));
    canvas.drawCircle(Offset.zero, 29, Paint()..shader = const RadialGradient(
      center: Alignment(-.4, -.5), colors: [Color(0xfff9c884), Color(0xffbd713f)],
    ).createShader(const Rect.fromLTWH(-29, -29, 58, 58)));
    for (var i = 0; i < 42; i++) {
      final angle = i * 2.39996;
      final r = 3.6 * math.sqrt(i);
      canvas.drawCircle(Offset(math.cos(angle) * r, math.sin(angle) * r), 1.5,
        _fill(const Color(0x885d481f)));
    }
    canvas.restore();
    // Curling fern on the left.
    canvas.drawPath(Path()..moveTo(247, 356)..cubicTo(260, 300, 212, 270, 220, 218),
      _stroke(const Color(0xff8ebb81), 7));
    for (var i = 0; i < 5; i++) {
      final origin = Offset(229 + i * 4.0, 245 + i * 19.0);
      _leaf(canvas, origin, 1.05, 60.0 - i * 4, 20, const Color(0xff65a881));
      _leaf(canvas, origin, -1.1, 67.0 - i * 4, 21, const Color(0xff448263));
    }
    _leaf(canvas, const Offset(267, 367), 1.42, 103, 38, const Color(0xffb8d07b));
    _leaf(canvas, const Offset(294, 372), -.95, 80, 36, const Color(0xff76af6d));
    // Foreground orbit and fireflies.
    canvas.save();
    canvas.translate(326, 255);
    canvas.rotate(-.42);
    canvas.drawArc(const Rect.fromLTWH(-230, -143, 460, 286), .1, 2.55, false,
      _stroke(const Color(0xffa4bb78), 1.3));
    canvas.restore();
    for (final point in const [Offset(122, 186), Offset(477, 110), Offset(520, 292), Offset(176, 405)]) {
      canvas.drawCircle(point, 5, _fill(GardenTheme.acid));
      canvas.drawCircle(point, 10, _stroke(const Color(0x55d6f77b)));
    }
    // Small celestial sun.
    canvas.drawCircle(const Offset(182, 124), 28, Paint()..shader = const RadialGradient(
      center: Alignment(-.4, -.5), colors: [Color(0xfff4ffb6), Color(0xffb3d865)],
    ).createShader(const Rect.fromLTWH(154, 96, 56, 56)));
    canvas.drawCircle(const Offset(182, 124), 37, _stroke(const Color(0x40d6f77b)));
    _cross(canvas, const Offset(106, 292));
    _cross(canvas, const Offset(489, 207));
    canvas.restore();
  }

  void _cross(Canvas canvas, Offset o) {
    canvas.drawLine(o.translate(-5, 0), o.translate(5, 0), _stroke(GardenTheme.muted));
    canvas.drawLine(o.translate(0, -5), o.translate(0, 5), _stroke(GardenTheme.muted));
  }

  void _leaf(Canvas canvas, Offset base, double angle, double length, double width, Color color) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    final path = Path()..moveTo(0, 0)
      ..cubicTo(-width, -length * .32, -width * .6, -length * .8, 0, -length)
      ..cubicTo(width * .9, -length * .7, width, -length * .25, 0, 0);
    canvas.drawPath(path, Paint()..shader = LinearGradient(
      colors: [_green, color, color.withValues(alpha: .85)],
    ).createShader(Rect.fromLTWH(-width, -length, width * 2, length)));
    canvas.drawPath(Path()..moveTo(0, 0)..quadraticBezierTo(8, -length * .5, 0, -length * .94),
      _stroke(const Color(0x70d9eda7)));
    for (var i = 1; i < 5; i++) {
      final y = -length * i / 6;
      canvas.drawLine(Offset(3, y), Offset(width * .48, y - length * .12),
        _stroke(const Color(0x287bce84)));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GardenPainter oldDelegate) => false;
}
