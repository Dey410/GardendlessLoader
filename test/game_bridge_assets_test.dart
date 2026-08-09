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

  test('large export streaming passes executable behavior checks', () async {
    final result = await Process.run(
      'node',
      const ['tool/check_export_download_patch.mjs'],
    );

    expect(
      result.exitCode,
      0,
      reason: '${result.stdout}\n${result.stderr}',
    );
    expect(result.stdout, contains('streams revoked Blob downloads'));
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

  test('iOS audio facade passes executable behavior checks', () async {
    final result = await Process.run(
      'node',
      const ['tool/check_audio_facade.mjs'],
    );

    expect(
      result.exitCode,
      0,
      reason: '${result.stdout}\n${result.stderr}',
    );
    expect(result.stdout, contains('audio facade contract passes'));
  });

  test('iOS native short sound proxy is injected before bootstrap', () {
    final proxy =
        File('assets/game_bridge/ios_audio_proxy.js').readAsStringSync();
    final facade =
        File('assets/game_bridge/ios_audio_facade.js').readAsStringSync();
    final controller =
        File('ios/Runner/GameHostController.swift').readAsStringSync();
    final bridge =
        File('ios/Runner/AudioScriptBridge.swift').readAsStringSync();
    final engine = File(
      'ios/GardendlessKit/Sources/GardendlessAudio/ShortSfxEngine.swift',
    ).readAsStringSync();
    final schemeHandler = File(
      'ios/GardendlessKit/Sources/GardendlessResource/'
      'ResourceSchemeHandler.swift',
    ).readAsStringSync();
    final configuration = File(
      'ios/GardendlessKit/Sources/GardendlessCore/GameConfiguration.swift',
    ).readAsStringSync();
    final limits = File(
      'ios/GardendlessKit/Sources/GardendlessAudio/AudioPlaybackLimits.swift',
    ).readAsStringSync();

    expect(proxy, contains('__pvzgeLazySrc'));
    expect(proxy, contains('gardendlessAudio'));
    expect(proxy, contains('window.__gardendlessNativeAudioInstalled'));
    expect(proxy, contains('diagnostics.record("webkitFallback"'));
    expect(facade, contains('window.__gardendlessNativeAudio'));
    expect(facade, contains('createNativeAudioHandle'));
    expect(facade, contains('command: "setVolume"'));
    expect(facade, contains('command: "setLoop"'));
    expect(facade, contains('command: "setRate"'));
    expect(facade, contains('command: "releaseMany"'));
    expect(facade, contains('window.__gardendlessAudioEvents'));
    expect(facade, contains('silentThrottled'));
    expect(facade, contains('__gardendlessNativeAudioFacadeInstalled'));
    expect(proxy, contains('__gardendlessNativeAudioSilent'));
    expect(proxy, isNot(contains('__gardendlessNativeAudioWebKit')));
    expect(proxy, isNot(contains('__gardendlessNativeAudioFallback')));
    expect(proxy, contains('element.dispatchEvent(new Event("ended"))'));
    expect(controller, contains('"nativeSfxEnabled": nativeSfxEnabled'));
    expect(
      controller,
      contains('"audioVoicePoolSize": AudioPlaybackLimits.voicePoolSize'),
    );
    expect(controller, contains('audioCompressedSfxByteLimit'));
    expect(controller, contains('audioPcmCacheByteLimit'));
    expect(controller, contains('audioLongMaxBytes'));
    expect(
      engine,
      contains(
          'maxConcurrentOperationCount = configuration.audioQueueConcurrency'),
    );
    expect(
      configuration,
      contains('pcmCacheByteLimit: Int = 96 * 1024 * 1024'),
    );
    expect(
      configuration,
      contains('compressedSfxByteLimit: Int64 = 512 * 1024'),
    );
    expect(
      configuration,
      contains('singleBufferByteLimit: Int = 4 * 1024 * 1024'),
    );
    expect(limits, contains('voicePoolSize = 48'));
    expect(limits, contains('rateVoiceCount = 6'));
    expect(limits, contains('longChannelCount = 8'));
    expect(bridge, contains('message.frameInfo.isMainFrame'));
    expect(bridge, contains('securityOrigin.protocol == GameOrigin.scheme'));
    expect(bridge, contains('securityOrigin.host == GameOrigin.host'));
    expect(schemeHandler, contains('private let sandbox: PathSandbox'));
    expect(
      controller.indexOf('"ios_audio_proxy.js"'),
      lessThan(controller.indexOf('"bootstrap.js"')),
    );
    expect(
      controller.indexOf('"ios_audio_facade.js"'),
      lessThan(controller.indexOf('"ios_audio_proxy.js"')),
    );
  });

  test('audio diagnostics probe is injected before the iOS audio proxy', () {
    final diagnostic =
        File('assets/game_bridge/audio_diagnostic.js').readAsStringSync();
    final proxy =
        File('assets/game_bridge/ios_audio_proxy.js').readAsStringSync();
    final controller =
        File('ios/Runner/GameHostController.swift').readAsStringSync();
    final bridge =
        File('ios/Runner/AudioScriptBridge.swift').readAsStringSync();

    expect(diagnostic, contains('window.__gardendlessAudioDiagnostics'));
    expect(diagnostic, contains('schemaVersion: 2'));
    expect(diagnostic, contains('facadeCreated'));
    expect(diagnostic, contains('playPosted'));
    expect(diagnostic, contains('silentThrottled'));
    expect(diagnostic, contains('stoppedReceived'));
    expect(diagnostic, contains('webkitFallback'));
    expect(
      diagnostic,
      contains('facadeInstalled: !!window.__gardendlessNativeAudioFacadeInstalled'),
    );
    expect(diagnostic, contains('AudioBufferSourceNode.prototype.start'));
    expect(diagnostic, contains('decodeAudioData'));
    expect(diagnostic, contains('requestAnimationFrame(frameLoop)'));
    expect(diagnostic, contains('GDL_AUDIO_DIAG'));
    expect(diagnostic, contains('command: "writeDiagnostics"'));
    expect(proxy, contains('diagnostics.record("nativePlayPosted"'));
    expect(
      proxy,
      contains('diagnostics.record("nativePostFailed"'),
    );
    expect(
      controller,
      contains('"audioDiagnosticsEnabled": audioDiagnosticsEnabled'),
    );
    expect(bridge, contains('case "writeDiagnostics"'));
    expect(bridge, contains('case "releaseMany"'));
    expect(bridge, contains('audio-diagnostics.json'));
    expect(
      controller.indexOf('"audio_diagnostic.js"'),
      lessThan(controller.indexOf('"ios_audio_proxy.js"')),
    );
  });

  test('iOS native sound graph is initialized lazily after audio session', () {
    final engine = File(
      'ios/GardendlessKit/Sources/GardendlessAudio/ShortSfxEngine.swift',
    ).readAsStringSync();
    final initializer = engine.substring(
      engine.indexOf('  public init('),
      engine.indexOf('  public func play('),
    );

    expect(initializer, isNot(contains('AVAudioEngine()')));
    expect(initializer, isNot(contains('configureNodes')));
    expect(initializer, isNot(contains('observeLifecycle')));
    expect(initializer, isNot(contains('ensureEngineRunning')));
    expect(engine, contains('private var engine: AVAudioEngine?'));
    final preparation = engine.substring(
      engine.indexOf('  private func ensureEngineRunning()'),
      engine.indexOf('  private func configureNodes('),
    );
    expect(
      preparation.indexOf('try session.setActive(true)'),
      lessThan(preparation.indexOf('configureNodes(newEngine)')),
    );
  });

  test('iOS pooled sound nodes follow each decoded buffer format', () {
    final engine = File(
      'ios/GardendlessKit/Sources/GardendlessAudio/ShortSfxEngine.swift',
    ).readAsStringSync();
    final configuration = engine.substring(
      engine.indexOf('  private func configureNodes('),
      engine.indexOf('  private func observeLifecycle('),
    );
    final scheduling = engine.substring(
      engine.indexOf('  private func schedule('),
      engine.indexOf('  private func completeVoice('),
    );

    expect(configuration, contains('engine.attach(varispeed)'));
    expect(
      configuration,
      isNot(contains('engine.connect(varispeed, to: engine.mainMixerNode')),
    );
    expect(
      scheduling,
      contains('engine.disconnectNodeOutput(selectedNode.player)'),
    );
    expect(scheduling, contains('to: engine.mainMixerNode,'));
    expect(scheduling, contains('to: varispeed,'));
    expect(scheduling, contains('format: cached.buffer.format'));
    expect(
      scheduling.indexOf('engine.disconnectNodeOutput(selectedNode.player)'),
      lessThan(scheduling.indexOf('format: cached.buffer.format')),
    );
    expect(
      scheduling.indexOf('format: cached.buffer.format'),
      lessThan(scheduling.indexOf('selectedNode.player.scheduleBuffer(')),
    );
  });

  test('legacy in-game menu is removed and native back paths return home', () {
    final android = File(
      'android/app/src/main/kotlin/io/github/dey410/'
      'gardendlessloader/game/GameActivity.kt',
    ).readAsStringSync();
    final ios = File('ios/Runner/GameHostController.swift').readAsStringSync();
    final iosProject =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
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
