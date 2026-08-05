import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const scripts = [
    'transport.js',
    'bootstrap.js',
    'logging.js',
    'touch_patch.js',
    'export_download_patch.js',
    'gp_next_core.js',
    'gp_next_compat_bridge.js',
    'watermark.js',
    'auto_sun.js',
  ];

  test('ships one platform-independent document-start script source', () {
    final combined = scripts.map((name) {
      final file = File('assets/game_bridge/$name');
      expect(file.existsSync(), isTrue, reason: name);
      return file.readAsStringSync();
    }).join('\n');

    expect(combined, contains('window.__gardendlessTransport'));
    expect(combined, contains('window.__gardendlessHost'));
    expect(combined, isNot(contains('window.__gardendlessMenu')));
    expect(combined, isNot(contains('flutter_inappwebview')));
    expect(
        combined,
        isNot(
            contains('setInterval(function () {\n        if (bridgeReady())')));
  });

  test('watermark never captures game input', () {
    final source = File('assets/game_bridge/watermark.js').readAsStringSync();

    expect(source, contains('pointerEvents: "none"'));
  });

  test('large exports are streamed through bounded bridge chunks', () {
    final source =
        File('assets/game_bridge/export_download_patch.js').readAsStringSync();

    expect(source, contains('const chunkSize = 192 * 1024'));
    expect(source, contains('host:exportBegin'));
    expect(source, contains('host:exportChunk'));
    expect(source, contains('host:exportCommit'));
    expect(source, isNot(contains('readAsDataURL')));
  });

  test('native bridge waits are bounded without timing out normal pickers', () {
    final source = File('assets/game_bridge/transport.js').readAsStringSync();

    expect(source, contains('const defaultTimeoutMs = 15000'));
    expect(source, contains('const userInteractionTimeoutMs = 5 * 60 * 1000'));
    expect(source, contains('command === "host:exportCommit"'));
    expect(source, contains('command === "plugin:opener|open_path"'));
    expect(source, isNot(contains('setInterval(')));
  });

  test('shared bridge protocol passes executable behavior checks', () async {
    final result = await Process.run(
      'node',
      const ['tool/check_game_bridge.mjs'],
    );

    expect(
      result.exitCode,
      0,
      reason: '${result.stdout}\n${result.stderr}',
    );
    expect(result.stdout, contains('game bridge concurrency'));
  });

  test('shared touch patch passes executable behavior checks', () async {
    final result = await Process.run(
      'node',
      const ['tool/check_touch_patch.mjs'],
    );

    expect(
      result.exitCode,
      0,
      reason: '${result.stdout}\n${result.stderr}',
    );
    expect(result.stdout, contains('touch patch input contract passes'));
  });

  test('iOS native short sound proxy is injected before bootstrap', () {
    final proxy =
        File('assets/game_bridge/ios_audio_proxy.js').readAsStringSync();
    final controller =
        File('ios/Runner/GameViewController.swift').readAsStringSync();
    final engine = File('ios/Runner/NativeSfxEngine.swift').readAsStringSync();
    final bridge = File('ios/Runner/GameAudioBridge.swift').readAsStringSync();
    final schemeHandler =
        File('ios/Runner/GameResourceSchemeHandler.swift').readAsStringSync();

    expect(proxy, contains('__pvzgeLazySrc'));
    expect(proxy, contains('gardendlessAudio'));
    expect(proxy, contains('__gardendlessNativeAudioFallback'));
    expect(proxy, contains('element.dispatchEvent(new Event("ended"))'));
    expect(controller, contains('"nativeSfxEnabled": nativeSfxEnabled'));
    expect(engine, contains('maxConcurrentOperationCount = 1'));
    expect(engine, contains('pcmCacheByteLimit = 64 * 1024 * 1024'));
    expect(engine, contains('singleBufferByteLimit = 4 * 1024 * 1024'));
    expect(engine, contains('nodeCount = 16'));
    expect(bridge, contains('message.frameInfo.isMainFrame'));
    expect(bridge, contains('securityOrigin.protocol == "gardendless-game"'));
    expect(bridge, contains('securityOrigin.host == "localhost"'));
    expect(schemeHandler, contains('private let locator: GameResourceLocator'));
    expect(
      controller.indexOf('"ios_audio_proxy.js"'),
      lessThan(controller.indexOf('"bootstrap.js"')),
    );
  });

  test('iOS native sound graph is initialized lazily after audio session', () {
    final engine = File('ios/Runner/NativeSfxEngine.swift').readAsStringSync();
    final initializer = engine.substring(
      engine.indexOf('  init('),
      engine.indexOf('  func register('),
    );

    expect(initializer, isNot(contains('AVAudioEngine()')));
    expect(initializer, isNot(contains('configureNodes')));
    expect(initializer, isNot(contains('observeLifecycle')));
    expect(initializer, isNot(contains('ensureEngineRunning')));
    expect(engine, contains('private var engine: AVAudioEngine?'));
    final preparation = engine.substring(
      engine.indexOf('  private func ensureEngineRunning()'),
      engine.indexOf('  private func enqueue('),
    );
    expect(
      preparation.indexOf('try session.setActive(true)'),
      lessThan(preparation.indexOf('configureNodes(preparedEngine)')),
    );
  });

  test('iOS pooled sound nodes follow each decoded buffer format', () {
    final engine = File('ios/Runner/NativeSfxEngine.swift').readAsStringSync();
    final configuration = engine.substring(
      engine.indexOf('  private func configureNodes('),
      engine.indexOf('  private func observeLifecycle('),
    );
    final scheduling = engine.substring(
      engine.indexOf('  private func schedule('),
      engine.indexOf('  private func completeVoice('),
    );
    const connect = 'engine.connect(node, to: engine.mainMixerNode, '
        'format: cached.buffer.format)';

    expect(configuration, isNot(contains('engine.connect(')));
    expect(scheduling, contains('engine.disconnectNodeOutput(node)'));
    expect(scheduling, contains(connect));
    expect(
      scheduling.indexOf('engine.disconnectNodeOutput(node)'),
      lessThan(scheduling.indexOf(connect)),
    );
    expect(
      scheduling.indexOf(connect),
      lessThan(scheduling.indexOf('node.scheduleBuffer(cached.buffer')),
    );
  });

  test('legacy in-game menu is removed and native back paths return home', () {
    final android = File(
      'android/app/src/main/kotlin/io/github/dey410/'
      'gardendlessloader/game/GameActivity.kt',
    ).readAsStringSync();
    final ios = File('ios/Runner/GameViewController.swift').readAsStringSync();
    final iosProject =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final iosPackage = File('ios/Package.swift').readAsStringSync();
    final ohos =
        File('ohos/entry/src/main/ets/pages/GamePage.ets').readAsStringSync();

    expect(File('assets/game_bridge/game_menu.js').existsSync(), isFalse);
    expect(
      File(
        'android/app/src/main/kotlin/io/github/dey410/'
        'gardendlessloader/game/GameMenuController.kt',
      ).existsSync(),
      isFalse,
    );
    expect(File('ios/Runner/GameMenuController.swift').existsSync(), isFalse);
    expect(
      File('ohos/entry/src/main/ets/game/GameMenu.ets').existsSync(),
      isFalse,
    );
    expect(android, isNot(contains('GameMenuController')));
    expect(android, isNot(contains('game_menu.js')));
    expect(
      android,
      contains('returnToLauncher(GameExitReason.USER_RETURNED, null)'),
    );
    expect(ios, isNot(contains('GameMenuController')));
    expect(ios, isNot(contains('game_menu.js')));
    expect(iosProject, isNot(contains('GameMenuController.swift')));
    expect(iosPackage, isNot(contains('GameMenuController.swift')));
    expect(ios, contains('#selector(returnToLauncher)'));
    expect(ohos, isNot(contains('GameMenu')));
    expect(ohos, isNot(contains('game_menu.js')));
    expect(ohos, contains("returnToLauncher('userReturned', null);"));
  });

  test('automatic sun collection passes executable behavior checks', () async {
    final result = await Process.run(
      'node',
      const ['tool/check_auto_sun.mjs'],
    );

    expect(
      result.exitCode,
      0,
      reason: '${result.stdout}\n${result.stderr}',
    );
    expect(result.stdout, contains('automatic sun collection contract passes'));
  });
}
