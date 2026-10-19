import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/garden_theme.dart';

/// Two scrolling columns side by side; below [breakpoint] they stack into
/// one column so narrow layouts (and the first portrait frame) still fit.
class TwoColumn extends StatelessWidget {
  const TwoColumn({
    super.key,
    required this.left,
    required this.right,
    this.leftFlex = 1,
    this.rightFlex = 1,
    this.gap = 16,
    this.breakpoint = 560,
  });

  final List<Widget> left;
  final List<Widget> right;
  final int leftFlex;
  final int rightFlex;
  final double gap;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return ListView(
            children: [...left, SizedBox(height: gap), ...right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: leftFlex, child: ListView(children: left)),
            SizedBox(width: gap),
            Expanded(flex: rightFlex, child: ListView(children: right)),
          ],
        );
      },
    );
  }
}

/// Flat card: one surface colour and a hairline border, no shadow.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: palette.inkMuted),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GardenType.title(15, color: palette.ink),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Scales down slightly on pointer-down so every control acknowledges the
/// touch immediately; keyboard activation skips the animation.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.scale = 0.97,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double scale;
  final String? tooltip;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _focused = false;

  void _setDown(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final reduced = GardenMotionScope.reduced(context);
    Widget result = AnimatedScale(
      scale: _down && !reduced ? widget.scale : 1,
      duration: GardenMotion.press,
      curve: GardenMotion.easeOut,
      child: widget.child,
    );
    if (_focused) {
      result = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.garden.accent, width: 2),
        ),
        child: result,
      );
    }
    result = FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setDown(true) : null,
        onTapUp: enabled ? (_) => _setDown(false) : null,
        onTapCancel: enabled ? () => _setDown(false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: result,
      ),
    );
    result = Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: result,
    );
    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }
    return result;
  }
}

enum GardenButtonTone { primary, secondary, ghost, danger }

class GardenButton extends StatelessWidget {
  const GardenButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.tone = GardenButtonTone.secondary,
    this.busy = false,
    this.compact = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Custom leading glyph (e.g. a brand icon) when [icon] does not fit.
  final Widget? leading;
  final GardenButtonTone tone;
  final bool busy;
  final bool compact;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final enabled = onPressed != null && !busy;
    final (Color fill, Color fg, Color border) = switch (tone) {
      GardenButtonTone.primary => (
          palette.accent,
          palette.onAccent,
          Colors.transparent,
        ),
      GardenButtonTone.secondary => (
          palette.surfaceMuted,
          palette.ink,
          palette.border,
        ),
      GardenButtonTone.ghost => (
          Colors.transparent,
          palette.inkMuted,
          Colors.transparent,
        ),
      GardenButtonTone.danger => (
          Colors.transparent,
          palette.danger,
          palette.border,
        ),
    };
    final height = compact ? 36.0 : 44.0;
    final fontSize = compact ? 13.0 : 14.0;
    return Pressable(
      onTap: enabled ? onPressed : null,
      semanticLabel: label,
      tooltip: tooltip,
      child: AnimatedOpacity(
        duration: GardenMotion.quick,
        opacity: enabled || busy ? 1 : 0.4,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              else if (icon != null)
                Icon(icon, size: fontSize + 3, color: fg)
              else if (leading != null)
                IconTheme.merge(
                  data: IconThemeData(size: fontSize + 2, color: fg),
                  child: leading!,
                ),
              if (busy || icon != null || leading != null)
                const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GardenIconButton extends StatelessWidget {
  const GardenIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 36,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return Pressable(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      scale: 0.92,
      child: AnimatedOpacity(
        duration: GardenMotion.quick,
        opacity: onPressed == null ? 0.4 : 1,
        child: SizedBox.square(
          dimension: math.max(size, 36),
          child: Icon(icon, size: 18, color: palette.inkMuted),
        ),
      ),
    );
  }
}

/// A coloured dot followed by plain text. Colour carries status only.
class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color ?? palette.inkFaint,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.inkMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Number over caption, used for resource and import statistics.
class Metric extends StatelessWidget {
  const Metric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: GardenType.title(18, color: palette.ink).copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: palette.inkMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class MetricRow extends StatelessWidget {
  const MetricRow({super.key, required this.metrics});

  final List<Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(child: metrics[i]),
        ],
      ],
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.trailing,
    this.mono = false,
    this.maxLines = 2,
    this.hint,
  });

  final String label;
  final String value;
  final Color? color;
  final Widget? trailing;
  final bool mono;
  final int maxLines;

  /// Fix hint shown below an error [value].
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final text = Text(
      value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: mono
          ? GardenType.mono(12, color: color ?? palette.ink)
          : TextStyle(
              color: color ?? palette.ink,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 88),
              child: Text(
                label,
                style: TextStyle(color: palette.inkMuted, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: hint == null
                ? text
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      text,
                      const SizedBox(height: 2),
                      Text(
                        hint!,
                        style:
                            TextStyle(color: palette.inkMuted, fontSize: 12.5),
                      ),
                    ],
                  ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    this.switchKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key? switchKey;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return MergeSemantics(
      child: Pressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        scale: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.inkMuted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Switch(key: switchKey, value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-choice control with a sliding thumb.
class GardenSegmented<T> extends StatelessWidget {
  const GardenSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.keyOf,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;
  final Key Function(T value)? keyOf;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final index = values.indexOf(selected).clamp(0, values.length - 1);
    final reduced = GardenMotionScope.reduced(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segment = constraints.maxWidth / values.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: reduced ? Duration.zero : GardenMotion.quick,
                curve: GardenMotion.easeOut,
                left: segment * index,
                top: 0,
                bottom: 0,
                width: segment,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.isDark
                        ? const Color(0xff34353b)
                        : palette.surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: palette.isDark
                        ? null
                        : const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final value in values)
                    Expanded(
                      child: Pressable(
                        key: keyOf?.call(value),
                        onTap: () => onChanged(value),
                        semanticLabel: labelOf(value),
                        scale: 1,
                        child: Center(
                          child: Text(
                            labelOf(value),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: TextStyle(
                              color: value == selected
                                  ? palette.ink
                                  : palette.inkMuted,
                              fontSize: 12.5,
                              fontWeight: value == selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Collapsible group with a rotating chevron.
class Disclosure extends StatefulWidget {
  const Disclosure({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<Disclosure> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final reduced = GardenMotionScope.reduced(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          onTap: () => setState(() => _expanded = !_expanded),
          semanticLabel: widget.title,
          scale: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: palette.inkMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: reduced ? Duration.zero : GardenMotion.quick,
                  curve: GardenMotion.easeOut,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: palette.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: reduced ? Duration.zero : GardenMotion.panel,
          curve: GardenMotion.easeOut,
          alignment: Alignment.topCenter,
          child:
              _expanded ? widget.child : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Monospace key/value block used for technical details.
class CodeBlock extends StatelessWidget {
  const CodeBlock({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

/// Thin determinate ring; a null [value] spins an indeterminate arc.
class ProgressRing extends StatefulWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.size,
    this.stroke = 4,
    this.color,
    this.child,
  });

  final double? value;
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.value == null && !GardenMotionScope.reduced(context)) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.value ?? 0.25),
      duration: GardenMotion.panel,
      curve: GardenMotion.easeOut,
      builder: (context, value, child) => SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _RingPainter(
            value: value,
            spin: _spin,
            indeterminate: widget.value == null,
            stroke: widget.stroke,
            track: palette.border,
            color: widget.color ?? palette.accent,
          ),
          child: Center(child: child),
        ),
      ),
      child: widget.child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.spin,
    required this.indeterminate,
    required this.stroke,
    required this.track,
    required this.color,
  }) : super(repaint: spin);

  final double value;
  final Animation<double> spin;
  final bool indeterminate;
  final double stroke;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    final sweep = 2 * math.pi * value.clamp(0.0, 1.0);
    if (sweep <= 0) return;
    final start = -math.pi / 2 + (indeterminate ? spin.value * 2 * math.pi : 0);
    canvas.drawArc(rect, start, sweep, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.indeterminate != indeterminate ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}
