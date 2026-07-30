import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/game_host/game_host.dart';

void main() {
  const session = GameSession(
    sessionId: 'session-42',
    resourceRoot: '/data/slot-b',
    platform: GameHostPlatform.android,
    entryPath: 'index.html',
    activationGeneration: 42,
    hasGpNext: true,
    gpNextCompatible: true,
    gpNextVersion: '1.4.2',
    watermarkEnabled: false,
    autoCollectSunEnabled: true,
    allowedRemoteHosts: ['api.github.com'],
    gpNextRoot: '/data/gp-next',
    exportTemporaryRoot: '/data/gp-next/.exports',
  );

  test('serializes a complete native game session without losing fields', () {
    final decoded = GameSession.fromJson(
      jsonDecode(jsonEncode(session.toJson())) as Map<String, Object?>,
    );

    expect(decoded, session);
    expect(decoded.autoCollectSunEnabled, isTrue);
    expect(decoded.origin, 'https://appassets.androidplatform.net');
    expect(
      decoded.entryUri.toString(),
      'https://appassets.androidplatform.net/index.html?generation=42',
    );
  });

  test('uses a stable platform origin while generation changes the entry URL',
      () {
    final next = session.copyWith(activationGeneration: 43);

    expect(next.origin, session.origin);
    expect(next.entryUri.queryParameters['generation'], '43');
  });

  test('defines the serverless origin used by every maintained platform', () {
    expect(
      GameHostPlatform.android.origin,
      'https://appassets.androidplatform.net',
    );
    expect(
      GameHostPlatform.ios.origin,
      'gardendless-game://localhost',
    );
    expect(
      GameHostPlatform.ohos.origin,
      'https://gardendless.invalid',
    );
  });

  test('rejects traversal entry paths at the public session seam', () {
    expect(
      () => GameSession.fromJson({
        ...session.toJson(),
        'entryPath': '../index.html',
      }),
      throwsFormatException,
    );
  });

  test('normalizes and validates remote host allowlist entries', () {
    final decoded = GameSession.fromJson({
      ...session.toJson(),
      'allowedRemoteHosts': ['API.GitHub.com'],
    });

    expect(decoded.allowedRemoteHosts, ['api.github.com']);
    expect(
      () => GameSession.fromJson({
        ...session.toJson(),
        'allowedRemoteHosts': ['.github.com'],
      }),
      throwsFormatException,
    );
    expect(
      () => GameSession.fromJson({
        ...session.toJson(),
        'allowedRemoteHosts': ['github.com.'],
      }),
      throwsFormatException,
    );
  });
}
