import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const scripts = [
    'transport.js',
    'bootstrap.js',
    'logging.js',
    'touch_state_machine.js',
    'touch_input_adapter.js',
    'export_download_patch.js',
    'gp_next_core.js',
    'gp_next_compat_bridge.js',
    'watermark.js',
    'auto_sun.js',
    'js_modding.js',
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

  test('JS Modding launch setting passes executable behavior checks',
      () async {
    final result = await Process.run(
      'node',
      const ['tool/check_js_modding.mjs'],
    );

    expect(
      result.exitCode,
      0,
      reason: '${result.stdout}\n${result.stderr}',
    );
    expect(result.stdout, contains('JS Modding settings contract passes'));
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

  test('shared touch adapter passes executable behavior checks', () async {
    final result = await Process.run(
      'node',
      const ['tool/check_touch_patch.mjs'],
    );

    expect(
      result.exitCode,
      0,
      reason: '${result.stdout}\n${result.stderr}',
    );
    expect(result.stdout, contains('touch input adapter contract passes'));
  });

  test(
    'reference touch state machine passes executable behavior checks',
    () async {
      final result = await Process.run(
        'node',
        const ['tool/check_touch_state_machine.mjs'],
      );

      expect(
        result.exitCode,
        0,
        reason: '${result.stdout}\n${result.stderr}',
      );
      expect(
        result.stdout,
        contains('reference touch state machine contract passes'),
      );
    },
  );

  test('passive audio diagnostics preserve browser audio behavior', () async {
    final result = await Process.run(
      'node',
      const ['tool/check_audio_diagnostic.mjs'],
    );

    expect(
      result.exitCode,
      0,
      reason: '${result.stdout}\n${result.stderr}',
    );
    expect(
        result.stdout, contains('passive audio diagnostics contract passes'));
  });

  test('iOS delegates audio loading and playback to Cocos browser backends',
      () {
    final controller =
        File('ios/Runner/GameHostController.swift').readAsStringSync();
    final diagnostic =
        File('assets/game_bridge/audio_diagnostic.js').readAsStringSync();
    final package = File('ios/GardendlessKit/Package.swift').readAsStringSync();
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final constants = File(
      'ios/GardendlessKit/Sources/GardendlessBridge/BridgeConstants.swift',
    ).readAsStringSync();

    expect(
      controller,
      contains('configuration.mediaTypesRequiringUserActionForPlayback = []'),
    );
    expect(controller, contains('"audio_diagnostic.js"'));
    expect(
      controller,
      matches(
        RegExp(
          r'"detailedAudioDiagnosticsEnabled":\s*'
          r'session\.detailedAudioDiagnosticsEnabled',
        ),
      ),
    );
    expect(controller, isNot(contains('ios_audio_facade.js')));
    expect(controller, isNot(contains('ios_audio_proxy.js')));
    expect(controller, isNot(contains('AudioScriptBridge')));
    expect(controller, isNot(contains('AudioPipelineEngine')));
    expect(package, isNot(contains('GardendlessAudio')));
    expect(package, isNot(contains('SfxExceptionGuard')));
    expect(project, isNot(contains('GardendlessAudio')));
    expect(project, isNot(contains('AudioScriptBridge.swift')));
    expect(constants, isNot(contains('gardendlessAudio')));

    expect(diagnostic, contains('decodeAudioData'));
    expect(diagnostic, contains('HTMLMediaElement'));
    expect(diagnostic, contains('host:log'));
    expect(diagnostic, contains('detailedAudioDiagnosticsEnabled'));
    expect(diagnostic, isNot(contains('gardendlessAudio')));
    expect(diagnostic, isNot(contains('writeDiagnostics')));
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
