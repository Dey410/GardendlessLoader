import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/key_art_locator.dart';
import '../theme/garden_theme.dart';
import 'ambient_backdrop.dart';

/// Home backdrop built from the key art inside the user's own imported
/// resource. Nothing is bundled: without a resource, or when the art is
/// missing or cannot be decoded, the quiet [AmbientBackdrop] stays visible.
class KeyArtBackdrop extends StatefulWidget {
  const KeyArtBackdrop({
    super.key,
    required this.resourceRoot,
    required this.generation,
    this.contentLeft = 0,
    this.locator = const KeyArtLocator(),
  });

  final String? resourceRoot;

  /// Width of the frosted sidebar on the left. The art is framed for the
  /// area to its right and continued underneath it.
  final double contentLeft;

  /// Manifest generation, so a re-import into the same slot reloads the art.
  final int generation;
  final KeyArtLocator locator;

  @override
  State<KeyArtBackdrop> createState() => _KeyArtBackdropState();
}

class _KeyArtBackdropState extends State<KeyArtBackdrop> {
  // Wide enough for a landscape iPad behind a scrim, about 10 MB decoded
  // instead of 25 MB for the full texture.
  static const _decodeWidth = 1600;

  ImageInfo? _info;
  KeyArtCrop? _crop;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  int _request = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void didUpdateWidget(KeyArtBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resourceRoot != widget.resourceRoot ||
        oldWidget.generation != widget.generation) {
      _load();
    }
  }

  @override
  void dispose() {
    _request++;
    _detach();
    _info?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    _detach();
    if (_info != null) {
      setState(() {
        _info?.dispose();
        _info = null;
      });
    }
    final root = widget.resourceRoot;
    if (root == null) return;
    final source = await widget.locator.locate(Directory(root));
    if (!mounted || request != _request || source == null) return;

    final provider = ResizeImage(
      FileImage(source.file),
      width: _decodeWidth,
      allowUpscaling: false,
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted || request != _request) {
          info.dispose();
          return;
        }
        setState(() {
          _info?.dispose();
          _info = info;
          _crop = source.crop;
        });
      },
      // An undecodable texture (e.g. AVIF on an engine without support)
      // simply leaves the ambient backdrop in place.
      onError: (_, __) {},
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _detach() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final crop = _crop;
    final reduced = GardenMotionScope.reduced(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const AmbientBackdrop(),
        AnimatedOpacity(
          opacity: info == null ? 0 : 1,
          duration: reduced ? Duration.zero : const Duration(milliseconds: 360),
          curve: GardenMotion.easeOut,
          child: info == null || crop == null
              ? const SizedBox.expand()
              : IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('key-art'),
                      painter: _KeyArtPainter(
                        image: info.image,
                        crop: crop,
                        palette: context.garden,
                        contentLeft: widget.contentLeft,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _KeyArtPainter extends CustomPainter {
  const _KeyArtPainter({
    required this.image,
    required this.crop,
    required this.palette,
    required this.contentLeft,
  });

  final ui.Image image;
  final KeyArtCrop crop;
  final GardenPalette palette;
  final double contentLeft;

  static const _saturation = 0.9;

  /// Beyond this zoom over a height fit, the art is anchored right instead.
  /// Phones in landscape need about 1.4× to cover the area beside the
  /// sidebar; only unusually wide screens fall back.
  static const _maxCoverZoom = 1.6;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final src = Rect.fromLTRB(
      crop.left * iw,
      crop.top * ih,
      crop.right * iw,
      crop.bottom * ih,
    );
    final artPaint = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = const ColorFilter.matrix(_saturationMatrix);
    final content = Rect.fromLTRB(
      contentLeft.clamp(0.0, size.width),
      0,
      size.width,
      size.height,
    );
    if (content.isEmpty) return;
    final coverScale =
        math.max(content.width / src.width, content.height / src.height);
    final fitHeightScale = content.height / src.height;
    if (coverScale <= fitHeightScale * _maxCoverZoom) {
      // Tablets and phones: cover the content area from the centre.
      final visible =
          Size(content.width / coverScale, content.height / coverScale);
      final from = Rect.fromLTWH(
        src.left + (src.width - visible.width) * 0.5,
        src.top + (src.height - visible.height) * 0.5,
        visible.width,
        visible.height,
      );
      canvas.drawImageRect(image, from, content, artPaint);
      if (content.left > 0) {
        // Continue the art under the frosted sidebar with a mirrored strip
        // of its own left edge: the seam stays continuous and the glass
        // blurs the copy into a soft extension.
        final strip = Rect.fromLTWH(
          from.left,
          from.top,
          math.min(from.width, content.left / coverScale),
          from.height,
        );
        canvas.save();
        canvas.translate(content.left, 0);
        canvas.scale(-1, 1);
        canvas.drawImageRect(
          image,
          strip,
          Rect.fromLTWH(0, 0, strip.width * coverScale, size.height),
          artPaint,
        );
        canvas.restore();
      }
    } else {
      // Much wider than the art: covering would zoom the logo into the top
      // bar and title row, so fit the height, anchor right and feather the
      // left edge into the ambient backdrop beneath.
      final width = src.width * fitHeightScale;
      final dst = Rect.fromLTWH(size.width - width, 0, width, size.height);
      canvas.saveLayer(dst, Paint());
      canvas.drawImageRect(image, src, dst, artPaint);
      canvas.drawRect(
        dst,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            colors: const [Color(0x00000000), Color(0xff000000)],
            stops: const [0, 0.3],
          ).createShader(dst),
      );
      canvas.restore();
    }

    final bg = palette.background;
    final rect = Offset.zero & size;
    final dark = palette.isDark;
    // A light overall dim keeps the art legible; the heavy fades sit only
    // where text lives: under the top bar and behind the bottom title row.
    canvas.drawRect(
      rect,
      Paint()..color = bg.withValues(alpha: dark ? 0.22 : 0.18),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            bg.withValues(alpha: dark ? 0.7 : 0.88),
            bg.withValues(alpha: 0),
            bg.withValues(alpha: 0),
            bg.withValues(alpha: dark ? 0.82 : 0.86),
            bg.withValues(alpha: 0.97),
          ],
          stops: const [0, 0.2, 0.5, 0.82, 1],
        ).createShader(rect),
    );
    // Only over the content area: the frosted sidebar already tints what
    // lies beneath it.
    canvas.drawRect(
      content,
      Paint()
        ..shader = LinearGradient(
          colors: [
            bg.withValues(alpha: 0.55),
            bg.withValues(alpha: 0),
          ],
          stops: const [0, 0.4],
        ).createShader(content),
    );
  }

  static const List<double> _saturationMatrix = [
    0.2126 + 0.7874 * _saturation, 0.7152 - 0.7152 * _saturation, //
    0.0722 - 0.0722 * _saturation, 0, 0,
    0.2126 - 0.2126 * _saturation, 0.7152 + 0.2848 * _saturation, //
    0.0722 - 0.0722 * _saturation, 0, 0,
    0.2126 - 0.2126 * _saturation, 0.7152 - 0.7152 * _saturation, //
    0.0722 + 0.9278 * _saturation, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  bool shouldRepaint(_KeyArtPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.crop != crop ||
      oldDelegate.palette != palette ||
      oldDelegate.contentLeft != contentLeft;
}
