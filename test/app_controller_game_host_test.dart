import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/game_host/game_host.dart';
import 'package:gardendless_loader/src/game_host/game_session_store.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:gardendless_loader/src/services/manifest_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test('prepares a durable session before launching the native game host',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_game_host_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final pathsService = AppPathsService(
      rootOverride: root,
      platformName: 'test',
    );
    final paths = await pathsService.ensureInitialized();
    await _writeValidResource(paths.slotADir);
    await ManifestStore(paths.manifestFile).write(
      ResourceManifest.initial().copyWith(
        generation: 42,
        activeSlot: ResourceSlot.slotA,
        transactionState: TransactionState.idle,
        resourceStatus: ResourceStatus.ready,
      ),
    );
    final host = _RecordingGameHost();
    final controller = AppController(
      pathsService: pathsService,
      gameHost: host,
      gameHostPlatform: GameHostPlatform.android,
      gameSessionIdFactory: () => 'session-42',
    );
    await controller.initialize();
    await controller.setAutoCollectSunEnabled(true);

    await controller.startGame();

    expect(host.session?.sessionId, 'session-42');
    expect(host.session?.resourceRoot, paths.slotADir.path);
    expect(host.session?.autoCollectSunEnabled, isTrue);
    expect(host.session?.entryUri.toString(),
        'https://appassets.androidplatform.net/index.html?generation=42');
    expect(
      await GameSessionStore(root).readPrepared(),
      host.session,
    );
    expect((await ManifestStore(paths.manifestFile).read()).activeSlot,
        ResourceSlot.slotA);
  });

  test('consuming a native exit result does not mutate active resources',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_game_exit_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final pathsService = AppPathsService(
      rootOverride: root,
      platformName: 'test',
    );
    final paths = await pathsService.ensureInitialized();
    await _writeValidResource(paths.slotBDir);
    final manifestStore = ManifestStore(paths.manifestFile);
    await manifestStore.write(
      ResourceManifest.initial().copyWith(
        generation: 7,
        activeSlot: ResourceSlot.slotB,
        transactionState: TransactionState.idle,
        resourceStatus: ResourceStatus.ready,
      ),
    );
    final sessionStore = GameSessionStore(root);
    await sessionStore.prepare(
      GameSession(
        sessionId: 'finished-session',
        resourceRoot: paths.slotBDir.path,
        platform: GameHostPlatform.android,
        entryPath: 'index.html',
        activationGeneration: 7,
        hasGpNext: false,
        gpNextCompatible: false,
        gpNextVersion: null,
        watermarkEnabled: true,
        allowedRemoteHosts: const [],
        gpNextRoot: paths.gpNextDir.path,
        exportTemporaryRoot: p.join(paths.gpNextDir.path, '.exports'),
      ),
    );
    await sessionStore.exitResultFile.writeAsString(
      '{"schemaVersion":1,"sessionId":"finished-session",'
      '"reason":"userReturned","finishedAt":"2026-07-20T12:00:00Z"}',
      flush: true,
    );
    final controller = AppController(
      pathsService: pathsService,
      gameHost: _RecordingGameHost(),
      gameHostPlatform: GameHostPlatform.android,
    );

    await controller.initialize();

    final recovered = await manifestStore.read();
    expect(recovered.activeSlot, ResourceSlot.slotB);
    expect(recovered.generation, 7);
    expect(controller.hasCurrentResource, isTrue);
    expect(
        await File(p.join(paths.slotBDir.path, 'index.html')).exists(), isTrue);
    expect(await sessionStore.preparedSessionFile.exists(), isFalse);
    expect(await sessionStore.exitResultFile.exists(), isFalse);
  });

  test('keeps Loader automatic collection enabled for a GP-Next session',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_gpnext_host_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final pathsService = AppPathsService(
      rootOverride: root,
      platformName: 'test',
    );
    final paths = await pathsService.ensureInitialized();
    await _writeGpNextResource(paths.slotADir);
    await ManifestStore(paths.manifestFile).write(
      ResourceManifest.initial().copyWith(
        activeSlot: ResourceSlot.slotA,
        autoCollectSunEnabled: true,
        resourceStatus: ResourceStatus.ready,
      ),
    );
    final host = _RecordingGameHost();
    final controller = AppController(
      pathsService: pathsService,
      gameHost: host,
      gameHostPlatform: GameHostPlatform.android,
    );
    await controller.initialize();

    expect(controller.hasGpNext, isTrue);
    await controller.startGame();

    expect(host.session?.hasGpNext, isTrue);
    expect(host.session?.autoCollectSunEnabled, isTrue);
  });
}

class _RecordingGameHost implements GameHost {
  GameSession? session;

  @override
  Future<void> launch(GameSession session) async {
    this.session = session;
  }
}

Future<void> _writeValidResource(Directory root) async {
  await Directory(p.join(root.path, 'assets')).create(recursive: true);
  await Directory(p.join(root.path, 'cocos-js')).create(recursive: true);
  await Directory(p.join(root.path, 'src')).create(recursive: true);
  await File(p.join(root.path, 'index.html')).writeAsString(
    '<html><head><title>PvZ2 Gardendless</title></head>'
    '<body>play.pvzge.com</body></html>',
  );
  await File(p.join(root.path, 'src', 'settings.json'))
      .writeAsString('{"platform":"web-mobile"}');
  await File(p.join(root.path, 'src', 'import-map.json')).writeAsString('{}');
  await File(p.join(root.path, 'cocos-js', 'cc.js')).writeAsString('');
}

Future<void> _writeGpNextResource(Directory root) async {
  await _writeValidResource(root);
  await File(p.join(root.path, 'index.html')).writeAsString('''
<html>
  <head><title>Cocos Creator | PvZ2_Gardendless</title></head>
  <body><script type="module" src="./assets/index-test.js"></script></body>
</html>
''');
  await File(p.join(root.path, 'assets', 'index-test.js')).writeAsString('''
console.info('GP-Next loading...');
window.gpNext = {};
function loadAllPatches() {}
import('./patcher-test.js');
import('./file-loader-test.js');
import('./js-mod-loader-test.js');
import('./config-test.js');
''');
}
