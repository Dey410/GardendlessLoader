import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/game_host/game_host.dart';

void main() {
  test('routes a session only to its maintained native platform host',
      () async {
    final launched = <GameHostPlatform>[];
    final hosts = {
      for (final platform in GameHostPlatform.values)
        platform: _RecordingHost(platform, launched),
    };
    final router = GameHostRouter(hosts: hosts);
    final session = _session(GameHostPlatform.ios);

    await router.launch(session);

    expect(launched, [GameHostPlatform.ios]);
  });

  test('rejects a session when no native host is registered', () async {
    final router = GameHostRouter(hosts: const {});

    await expectLater(
      router.launch(_session(GameHostPlatform.ohos)),
      throwsA(isA<UnsupportedError>()),
    );
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

class _RecordingHost implements GameHost {
  const _RecordingHost(this.platform, this.launched);

  final GameHostPlatform platform;
  final List<GameHostPlatform> launched;

  @override
  Future<void> launch(GameSession session) async {
    launched.add(platform);
  }
}
