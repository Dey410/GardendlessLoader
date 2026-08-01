import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/game_host/game_host.dart';
import 'package:gardendless_loader/src/game_host/game_session_store.dart';

void main() {
  test('atomically persists launch handoff and consumes the native exit result',
      () async {
    final root = await Directory.systemTemp.createTemp('game_handoff_');
    addTearDown(() => root.delete(recursive: true));
    final store = GameSessionStore(root);
    final session = _session();

    await store.prepare(session);
    expect(await store.readPrepared(), session);

    await store.exitResultFile.writeAsString(
      '{"schemaVersion":1,"sessionId":"handoff",'
      '"reason":"rendererGone","finishedAt":"2026-07-20T12:00:00Z"}',
      flush: true,
    );
    final result = await store.consumeExitResult();

    expect(result?.sessionId, 'handoff');
    expect(result?.reason, GameExitReason.rendererGone);
    expect(await store.exitResultFile.exists(), isFalse);
    expect(await store.preparedSessionFile.exists(), isFalse);
  });

  test('ignores an exit result from a different session', () async {
    final root = await Directory.systemTemp.createTemp('game_handoff_stale_');
    addTearDown(() => root.delete(recursive: true));
    final store = GameSessionStore(root);
    await store.prepare(_session());
    await store.exitResultFile.writeAsString(
      '{"schemaVersion":1,"sessionId":"stale",'
      '"reason":"normal","finishedAt":"2026-07-20T12:00:00Z"}',
      flush: true,
    );

    expect(await store.consumeExitResult(), isNull);
    expect(await store.preparedSessionFile.exists(), isTrue);
  });
}

GameSession _session() => const GameSession(
      sessionId: 'handoff',
      resourceRoot: '/data/slot-a',
      platform: GameHostPlatform.android,
      entryPath: 'index.html',
      activationGeneration: 4,
      hasGpNext: false,
      gpNextCompatible: false,
      gpNextVersion: null,
      watermarkEnabled: true,
      allowedRemoteHosts: [],
      gpNextRoot: '/data/gp-next',
      exportTemporaryRoot: '/data/gp-next/.exports',
    );
