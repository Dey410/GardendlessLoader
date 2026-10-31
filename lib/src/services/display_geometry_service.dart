import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the system reports about the launcher display.
///
/// Values describe the current display only: [occlusionRegions] are active
/// areas the hardware keeps for itself, in Flutter view points with the origin
/// at the top-left, margins included. Nothing here is inferred from a device
/// model or an orientation; a platform that does not publish reserved regions
/// reports none.
@immutable
class DisplayGeometry {
  const DisplayGeometry({
    required this.supportsReservedRegions,
    required this.verticalBarEdge,
    required this.viewWidth,
    required this.viewHeight,
    required this.occlusionRegions,
  });

  /// The answer used whenever the platform cannot report reserved regions.
  static const DisplayGeometry unsupported = DisplayGeometry(
    supportsReservedRegions: false,
    verticalBarEdge: null,
    viewWidth: 0,
    viewHeight: 0,
    occlusionRegions: <Rect>[],
  );

  /// Parses a native answer; null means the answer could not be read, so the
  /// caller keeps the geometry it already had.
  static DisplayGeometry? fromMap(Object? source) {
    if (source is! Map) return null;
    final Object? rawEdge = source['edge'];
    final edge =
        rawEdge is String && (rawEdge == 'leading' || rawEdge == 'trailing')
            ? rawEdge
            : null;
    final regions = <Rect>[];
    final Object? rawRegions = source['regions'];
    if (rawRegions is List) {
      for (final rawRegion in rawRegions) {
        if (rawRegion is! Map) continue;
        final region = _readRegion(rawRegion);
        if (region != null) regions.add(region);
      }
    }
    return DisplayGeometry(
      supportsReservedRegions: source['supportsReservedRegions'] == true,
      verticalBarEdge: edge,
      viewWidth: _readDouble(source['viewWidth']) ?? 0,
      viewHeight: _readDouble(source['viewHeight']) ?? 0,
      occlusionRegions: List<Rect>.unmodifiable(regions),
    );
  }

  /// Whether the platform publishes reserved regions at all.
  final bool supportsReservedRegions;

  /// The edge the system prefers for a vertical bar, or null when it has none
  /// or the platform does not say.
  final String? verticalBarEdge;

  /// Size of the Flutter view the regions are measured in.
  final double viewWidth;
  final double viewHeight;

  /// Active occlusion regions as the system reports them.
  final List<Rect> occlusionRegions;

  static Rect? _readRegion(Map<Object?, Object?> region) {
    if (region['active'] == false) return null;
    final left = _readDouble(region['x']);
    final top = _readDouble(region['y']);
    final width = _readDouble(region['width']);
    final height = _readDouble(region['height']);
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    if (width <= 0 || height <= 0) return null;
    return Rect.fromLTWH(left, top, width, height);
  }

  static double? _readDouble(Object? value) {
    if (value is! num) return null;
    final number = value.toDouble();
    return number.isFinite ? number : null;
  }

  @override
  bool operator ==(Object other) =>
      other is DisplayGeometry &&
      other.supportsReservedRegions == supportsReservedRegions &&
      other.verticalBarEdge == verticalBarEdge &&
      other.viewWidth == viewWidth &&
      other.viewHeight == viewHeight &&
      listEquals(other.occlusionRegions, occlusionRegions);

  @override
  int get hashCode => Object.hash(
        supportsReservedRegions,
        verticalBarEdge,
        viewWidth,
        viewHeight,
        Object.hashAll(occlusionRegions),
      );

  @override
  String toString() =>
      'DisplayGeometry(supportsReservedRegions: $supportsReservedRegions, '
      'verticalBarEdge: $verticalBarEdge, '
      'view: $viewWidth x $viewHeight, regions: $occlusionRegions)';
}

/// Reads the display geometry of the launcher and keeps it current.
///
/// Reserved regions are an iOS 27.1+ concept. Android, HarmonyOS, older iOS
/// versions, a missing native channel and an unreadable answer all settle on
/// [DisplayGeometry.unsupported]; nothing here fails, retries in a loop, or
/// draws a guess.
class DisplayGeometryService extends ChangeNotifier {
  DisplayGeometryService() {
    _services.add(this);
    // The handler is shared by every live service, so pages and engines that
    // come and go never stack handlers on the channel.
    _channel.setMethodCallHandler(_receiveNativeCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'io.github.dey410.gardendlessloader/display_geometry',
  );

  static final Set<DisplayGeometryService> _services =
      <DisplayGeometryService>{};

  DisplayGeometry? _value;
  Future<void>? _started;
  bool _disposed = false;
  bool _updatedByNativePush = false;

  /// The latest geometry; null until the first answer arrives.
  DisplayGeometry? get value => _value;

  /// The same value as [value], named for the geometry it carries.
  DisplayGeometry? get geometry => _value;

  /// Reads the current geometry and keeps listening for system changes.
  /// Repeated calls share the first request.
  Future<void> start() {
    if (_disposed) return Future<void>.value();
    final started = _started;
    if (started != null) return started;
    if (!_isIOS) {
      // No channel call is worth making off iOS; the first build already reads
      // this value, so no listener is notified from here.
      _value = DisplayGeometry.unsupported;
      return _started = Future<void>.value();
    }
    return _started = _load();
  }

  static bool get _isIOS => !kIsWeb && Platform.isIOS;

  Future<void> _load() async {
    // The channel handler is installed right after the engine starts, so the
    // first query can arrive before it exists. Retry briefly instead of
    // settling on "unsupported" for the rest of the session.
    for (var attempt = 0; attempt < 6; attempt += 1) {
      if (_disposed || _updatedByNativePush) return;
      try {
        final answer = await _channel.invokeMethod<Object?>('geometry');
        _applyLoaded(
          DisplayGeometry.fromMap(answer) ?? DisplayGeometry.unsupported,
        );
        return;
      } catch (error) {
        if (attempt == 5) {
          debugPrint('Display geometry unavailable: $error');
          _applyLoaded(DisplayGeometry.unsupported);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  }

  void _applyLoaded(DisplayGeometry geometry) {
    if (_disposed || _updatedByNativePush) return;
    if (geometry == _value) return;
    _value = geometry;
    notifyListeners();
  }

  static Future<Object?> _receiveNativeCall(MethodCall call) async {
    if (call.method != 'geometryChanged') return null;
    final geometry = DisplayGeometry.fromMap(call.arguments);
    if (geometry == null) return null;
    for (final service in List<DisplayGeometryService>.of(_services)) {
      service._apply(geometry);
    }
    return null;
  }

  void _apply(DisplayGeometry geometry) {
    if (_disposed) return;
    // A pushed state is newer than the answer of a query still in flight.
    _updatedByNativePush = true;
    if (geometry == _value) return;
    _value = geometry;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _services.remove(this);
    if (_services.isEmpty) {
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}
