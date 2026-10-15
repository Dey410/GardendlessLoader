import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/sensor_housing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.github.dey410.gardendlessloader/display');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('housingAwareInsets', () {
    const symmetric = EdgeInsets.fromLTRB(62, 0, 62, 21);

    test('keeps the full inset only on the housing side', () {
      expect(
        housingAwareInsets(symmetric, SensorHousingEdge.left),
        const EdgeInsets.fromLTRB(62, 0, 20, 21),
      );
      expect(
        housingAwareInsets(symmetric, SensorHousingEdge.right),
        const EdgeInsets.fromLTRB(20, 0, 62, 21),
      );
    });

    test('leaves insets alone when the side is unknown', () {
      expect(housingAwareInsets(symmetric, null), symmetric);
    });

    test('never grows an inset that is already small', () {
      expect(
        housingAwareInsets(
          const EdgeInsets.only(left: 8, right: 8),
          SensorHousingEdge.left,
        ),
        const EdgeInsets.only(left: 8, right: 8),
      );
    });
  });

  test('reads the initial edge and follows native changes', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'sensorHousingEdge');
      return 'left';
    });
    final service = SensorHousingService(channel: channel);
    addTearDown(service.dispose);

    await service.start();
    expect(service.value, SensorHousingEdge.left);

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('sensorHousingEdgeChanged', 'right'),
      ),
      (_) {},
    );
    expect(service.value, SensorHousingEdge.right);

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('sensorHousingEdgeChanged', null),
      ),
      (_) {},
    );
    expect(service.value, isNull);
  });

  test('stays unknown on platforms without the channel', () async {
    final service = SensorHousingService(channel: channel);
    addTearDown(service.dispose);

    await service.start();

    expect(service.value, isNull);
  });
}
