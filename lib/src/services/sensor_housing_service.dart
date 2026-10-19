import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

enum SensorHousingEdge { left, right }

/// Tracks which long edge holds the notch or Dynamic Island in landscape.
///
/// iOS reports the same safe-area inset on both long edges in landscape, so
/// the launcher asks the native host for the real side. Platforms without
/// the channel (Android, HarmonyOS) leave the value null, and the
/// system insets are used unchanged.
class SensorHousingService extends ValueNotifier<SensorHousingEdge?> {
  SensorHousingService() : super(null);

  static const MethodChannel _channel = MethodChannel(
    'io.github.dey410.gardendlessloader/display',
  );

  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sensorHousingEdgeChanged') {
        value = parse(call.arguments);
      }
    });
    try {
      value = parse(await _channel.invokeMethod<String>('sensorHousingEdge'));
    } on MissingPluginException {
      value = null;
    } on PlatformException {
      value = null;
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  static SensorHousingEdge? parse(Object? raw) => switch (raw) {
        'left' => SensorHousingEdge.left,
        'right' => SensorHousingEdge.right,
        _ => null,
      };
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
