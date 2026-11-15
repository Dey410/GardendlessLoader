import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum SensorHousingEdge { left, right }

/// Tracks which long edge holds the notch or Dynamic Island in landscape.
///
/// iOS reports the same safe-area inset on both long edges in landscape, so
/// the launcher asks the native host for the real side. Platforms without
/// the channel (Android, HarmonyOS) leave the value null, and the
/// system insets are used unchanged.
///
/// On iOS 27.1 and later it also reports the display areas the system
/// reserves for cameras ([reservedRegions]), so a corner camera such as the
/// iPhone Duo outer screen's can be avoided on its own instead of through
/// the whole safe-area inset.
class SensorHousingService extends ValueNotifier<SensorHousingEdge?>
    with WidgetsBindingObserver {
  SensorHousingService() : super(null);

  static const MethodChannel _channel = MethodChannel(
    'io.github.dey410.gardendlessloader/display',
  );

  List<Rect> _reservedRegions = const [];
  bool _regionsSupported = true;
  bool _observing = false;

  /// Active camera regions in launcher points, origin top-left; empty where
  /// the platform reports none.
  List<Rect> get reservedRegions => _reservedRegions;

  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'sensorHousingEdgeChanged':
          value = parse(call.arguments);
        case 'reservedRegionsChanged':
          _setRegions(parseRegions(call.arguments));
      }
    });
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    try {
      value = parse(await _channel.invokeMethod<String>('sensorHousingEdge'));
    } on MissingPluginException {
      value = null;
    } on PlatformException {
      value = null;
    }
    await _loadRegions();
  }

  // The regions follow the view's layout, which settles after start and
  // changes with the window.
  @override
  void didChangeMetrics() => unawaited(_loadRegions());

  Future<void> _loadRegions() async {
    if (!_regionsSupported) return;
    try {
      _setRegions(
        parseRegions(await _channel.invokeMethod<Object?>('reservedRegions')),
      );
    } on MissingPluginException {
      _regionsSupported = false;
    } on PlatformException {
      _regionsSupported = false;
    }
  }

  void _setRegions(List<Rect> regions) {
    if (listEquals(regions, _reservedRegions)) return;
    _reservedRegions = regions;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  static SensorHousingEdge? parse(Object? raw) => switch (raw) {
        'left' => SensorHousingEdge.left,
        'right' => SensorHousingEdge.right,
        _ => null,
      };

  static List<Rect> parseRegions(Object? raw) {
    if (raw is! List) return const [];
    final regions = <Rect>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final values = [item['x'], item['y'], item['width'], item['height']];
      if (values.any((v) => v is! num || !v.toDouble().isFinite)) continue;
      final [x, y, width, height] = [
        for (final v in values) (v as num).toDouble(),
      ];
      if (width <= 0 || height <= 0) continue;
      regions.add(Rect.fromLTWH(x, y, width, height));
    }
    return List.unmodifiable(regions);
  }
}

/// Keeps the full inset only on the edge with the sensor housing; the
/// opposite edge needs no more than [cornerClearance] to clear the rounded
/// display corner.
EdgeInsets housingAwareInsets(
  EdgeInsets padding,
  SensorHousingEdge? edge, {
  double cornerClearance = 20,
}) {
  double trim(double inset) =>
      inset < cornerClearance ? inset : cornerClearance;
  return switch (edge) {
    SensorHousingEdge.left => padding.copyWith(right: trim(padding.right)),
    SensorHousingEdge.right => padding.copyWith(left: trim(padding.left)),
    null => padding,
  };
}
