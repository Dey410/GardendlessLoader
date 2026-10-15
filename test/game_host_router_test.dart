import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/game_host/game_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('launches every maintained platform through one native contract',
      () async {
    const channel = MethodChannel('test/game-host');
    final launches = <Map<Object?, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'launch');
      launches.add(call.arguments as Map<Object?, Object?>);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    const host = MethodChannelGameHost(channel: channel);

    for (final platform in GameHostPlatform.values) {
      await host.launch(_session(platform));
    }

    expect(launches.map((session) => session['platform']),
        ['android', 'ios', 'ohos']);
    expect(launches.map((session) => session['activationGeneration']),
        everyElement(7));
  });
}

GameSession _session(GameHostPlatform platform) => GameSession(
      sessionId: 'router-test',
      resourceRoot: '/data/slot-a',
      platform: platform,
      entryPath: 'index.html',
      activationGeneration: 7,
      hasGpNext: false,
      gpNextCompatible: false,
      gpNextVersion: null,
      watermarkEnabled: true,
      allowedRemoteHosts: const [],
      gpNextRoot: '/data/gp-next',
      exportTemporaryRoot: '/data/gp-next/.exports',
    );
