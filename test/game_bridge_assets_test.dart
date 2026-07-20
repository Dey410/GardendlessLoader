import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const scripts = [
    'transport.js',
    'bootstrap.js',
    'touch_patch.js',
    'export_download_patch.js',
    'gp_next_core.js',
    'gp_next_compat_bridge.js',
    'watermark.js',
    'game_menu.js',
  ];

  test('ships one platform-independent document-start script source', () {
    final combined = scripts.map((name) {
      final file = File('assets/game_bridge/$name');
      expect(file.existsSync(), isTrue, reason: name);
      return file.readAsStringSync();
    }).join('\n');

    expect(combined, contains('window.__gardendlessTransport'));
    expect(combined, contains('window.__gardendlessHost'));
    expect(combined, contains('window.__gardendlessMenu'));
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
}
