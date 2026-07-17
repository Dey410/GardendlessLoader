import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:gardendless_loader/src/services/game_update_check_service.dart';
import 'package:gardendless_loader/src/services/manifest_store.dart';
import 'package:gardendless_loader/src/services/resource_picker_service.dart';
import 'package:gardendless_loader/src/services/update_check_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('startup refreshes the game version from current resource files',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_game_update_');
    addTearDown(() => root.delete(recursive: true));
    await _writeValidResource(
      Directory(p.join(root.path, 'current')),
      version: '0.11.0',
    );
    final store = ManifestStore(File(p.join(root.path, 'manifest.json')));
    await store.write(
      ResourceManifest.initial().copyWith(
        gameVersion: '0.10.0',
        resourceStatus: ResourceStatus.ready,
      ),
    );
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );

    await controller.initialize();

    expect(controller.currentGameVersion, '0.11.0');
    expect((await store.read()).gameVersion, '0.11.0');
  });

  test('refresh clears a stale game update when file version becomes unknown',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_game_update_');
    addTearDown(() => root.delete(recursive: true));
    final current = Directory(p.join(root.path, 'current'));
    await _writeValidResource(current, version: '0.10.0');
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        currentVersion: '0.4.8',
        installedVersionLoader: () async => '0.4.8',
        loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{"tag_name":"v0.4.8","html_url":"https://github.com/Dey410/GardendlessLoader/releases/tag/v0.4.8"}
''',
        ),
      ),
      gameUpdateCheckService: GameUpdateCheckService(
        loader: (uri, timeout, maxBytes) async =>
            const GameUpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '[{"name":"0.11.0"}]',
        ),
      ),
    );
    await controller.initialize();
    await controller.checkForUpdates();
    expect(controller.availableGameUpdate, isNotNull);
    await File(p.join(root.path, 'slot-a', 'index.html')).writeAsString(
      '<title>PvZ2 Gardendless Online</title>play.pvzge.com',
    );

    await controller.refresh();

    expect(controller.currentGameVersion, isNull);
    expect(controller.manifest.gameVersion, isNull);
    expect(controller.availableGameUpdate, isNull);
  });

  test('one check exposes a game update independently from app updates',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_game_update_');
    addTearDown(() => root.delete(recursive: true));
    await _writeValidResource(
      Directory(p.join(root.path, 'current')),
      version: '0.10.0',
    );
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        currentVersion: '0.4.8',
        installedVersionLoader: () async => '0.4.8',
        loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{"tag_name":"v0.4.8","html_url":"https://github.com/Dey410/GardendlessLoader/releases/tag/v0.4.8"}
''',
        ),
      ),
      gameUpdateCheckService: GameUpdateCheckService(
        loader: (uri, timeout, maxBytes) async =>
            const GameUpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '[{"name":"0.11.0"}]',
        ),
      ),
    );
    await controller.initialize();

    await controller.checkForUpdates();

    expect(controller.availableUpdate, isNull);
    expect(controller.availableGameUpdate?.currentVersion, '0.10.0');
    expect(controller.availableGameUpdate?.latestVersion, '0.11.0');
  });

  test('game check failure does not discard an available app update', () async {
    final root = await Directory.systemTemp.createTemp('gl_game_update_');
    addTearDown(() => root.delete(recursive: true));
    await _writeValidResource(
      Directory(p.join(root.path, 'current')),
      version: '0.10.0',
    );
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        currentVersion: '0.4.8',
        installedVersionLoader: () async => '0.4.8',
        loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{"tag_name":"v0.5.0","html_url":"https://github.com/Dey410/GardendlessLoader/releases/tag/v0.5.0"}
''',
        ),
      ),
      gameUpdateCheckService: GameUpdateCheckService(
        loader: (uri, timeout, maxBytes) async =>
            throw const SocketException('offline'),
      ),
    );
    await controller.initialize();

    await controller.checkForUpdates();

    expect(controller.availableUpdate?.latestVersion, '0.5.0');
    expect(controller.availableGameUpdate, isNull);
    expect(controller.message, '游戏更新检查失败，请稍后重试');
  });

  test('app check failure does not discard an available game update', () async {
    final root = await Directory.systemTemp.createTemp('gl_game_update_');
    addTearDown(() => root.delete(recursive: true));
    await _writeValidResource(
      Directory(p.join(root.path, 'current')),
      version: '0.10.0',
    );
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        installedVersionLoader: () async => '0.4.8',
        loader: (uri, timeout, maxBytes) async =>
            throw const SocketException('offline'),
      ),
      gameUpdateCheckService: GameUpdateCheckService(
        loader: (uri, timeout, maxBytes) async =>
            const GameUpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '[{"name":"0.11.0"}]',
        ),
      ),
    );
    await controller.initialize();

    await controller.checkForUpdates();

    expect(controller.availableUpdate, isNull);
    expect(controller.availableGameUpdate?.latestVersion, '0.11.0');
    expect(controller.message, '加载器更新检查失败，请稍后重试');
  });

  test('deferring a game update leaves an app update visible', () async {
    final root = await Directory.systemTemp.createTemp('gl_game_update_');
    addTearDown(() => root.delete(recursive: true));
    await _writeValidResource(
      Directory(p.join(root.path, 'current')),
      version: '0.10.0',
    );
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        currentVersion: '0.4.8',
        installedVersionLoader: () async => '0.4.8',
        loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{"tag_name":"v0.5.0","html_url":"https://github.com/Dey410/GardendlessLoader/releases/tag/v0.5.0"}
''',
        ),
      ),
      gameUpdateCheckService: GameUpdateCheckService(
        loader: (uri, timeout, maxBytes) async =>
            const GameUpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '[{"name":"0.11.0"}]',
        ),
      ),
    );
    await controller.initialize();
    await controller.checkForUpdates();

    controller.deferGameUpdate(controller.availableGameUpdate!);

    expect(controller.availableGameUpdate, isNull);
    expect(controller.availableUpdate?.latestVersion, '0.5.0');

    controller.deferUpdate(controller.availableUpdate!);
    await controller.checkForUpdates();

    expect(controller.message, isNull);
  });

  test('manual check reports the stable game version when none is imported',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_game_update_');
    addTearDown(() => root.delete(recursive: true));
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        currentVersion: '0.4.8',
        installedVersionLoader: () async => '0.4.8',
        loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{"tag_name":"v0.4.8","html_url":"https://github.com/Dey410/GardendlessLoader/releases/tag/v0.4.8"}
''',
        ),
      ),
      gameUpdateCheckService: GameUpdateCheckService(
        loader: (uri, timeout, maxBytes) async =>
            const GameUpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '[{"name":"0.11.0"}]',
        ),
      ),
    );
    await controller.initialize();

    await controller.checkForUpdates();

    expect(controller.availableGameUpdate, isNull);
    expect(
      controller.message,
      '加载器 v0.4.8 已是最新；游戏资源尚未导入，当前稳定版 0.11.0',
    );
  });

  test('manual check distinguishes an unknown imported game version', () async {
    final root = await Directory.systemTemp.createTemp('gl_game_update_');
    addTearDown(() => root.delete(recursive: true));
    final current = Directory(p.join(root.path, 'current'));
    await _writeValidResource(current, version: '0.10.0');
    await File(p.join(current.path, 'index.html')).writeAsString(
      '<title>PvZ2 Gardendless Online</title>play.pvzge.com',
    );
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        currentVersion: '0.4.8',
        installedVersionLoader: () async => '0.4.8',
        loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{"tag_name":"v0.4.8","html_url":"https://github.com/Dey410/GardendlessLoader/releases/tag/v0.4.8"}
''',
        ),
      ),
      gameUpdateCheckService: GameUpdateCheckService(
        loader: (uri, timeout, maxBytes) async =>
            const GameUpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '[{"name":"0.11.0"}]',
        ),
      ),
    );
    await controller.initialize();

    await controller.checkForUpdates();

    expect(controller.hasCurrentResource, isTrue);
    expect(controller.currentGameVersion, isNull);
    expect(
      controller.message,
      '加载器 v0.4.8 已是最新；游戏版本未知，当前稳定版 0.11.0',
    );
  });

  test('importing the latest game clears its available update immediately',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_game_update_');
    addTearDown(() => root.delete(recursive: true));
    await _writeValidResource(
      Directory(p.join(root.path, 'current')),
      version: '0.10.0',
    );
    final gameUpdateCheckService = GameUpdateCheckService(
      loader: (uri, timeout, maxBytes) async =>
          const GameUpdateCheckHttpResponse(
        statusCode: HttpStatus.ok,
        body: '[{"name":"0.11.0"}]',
      ),
    );
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        currentVersion: '0.4.8',
        installedVersionLoader: () async => '0.4.8',
        loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{"tag_name":"v0.4.8","html_url":"https://github.com/Dey410/GardendlessLoader/releases/tag/v0.4.8"}
''',
        ),
      ),
      gameUpdateCheckService: gameUpdateCheckService,
      resourcePickerService: ResourcePickerService(
        platformName: 'android',
        mobileZipImporter: ({required targetDirectory, onProgress}) async {
          await _writeValidResource(
            Directory(targetDirectory),
            version: '0.11.0',
          );
          return targetDirectory;
        },
      ),
    );
    await controller.initialize();
    await controller.checkForUpdates();
    expect(controller.availableGameUpdate, isNotNull);

    await controller.importResources();

    expect(controller.currentGameVersion, '0.11.0');
    expect(controller.availableGameUpdate, isNull);
  });

  test('manual check reports when the imported game is ahead of stable',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_game_update_');
    addTearDown(() => root.delete(recursive: true));
    await _writeValidResource(
      Directory(p.join(root.path, 'current')),
      version: '0.12.0-next',
    );
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        currentVersion: '0.4.8',
        installedVersionLoader: () async => '0.4.8',
        loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{"tag_name":"v0.4.8","html_url":"https://github.com/Dey410/GardendlessLoader/releases/tag/v0.4.8"}
''',
        ),
      ),
      gameUpdateCheckService: GameUpdateCheckService(
        loader: (uri, timeout, maxBytes) async =>
            const GameUpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '[{"name":"0.11.0"}]',
        ),
      ),
    );
    await controller.initialize();

    await controller.checkForUpdates();

    expect(controller.availableGameUpdate, isNull);
    expect(
      controller.message,
      '加载器 v0.4.8 已是最新；本地游戏 0.12.0-next 高于公开稳定版 0.11.0',
    );
  });
}

Future<void> _writeValidResource(
  Directory root, {
  required String version,
}) async {
  await Directory(p.join(root.path, 'assets')).create(recursive: true);
  await Directory(p.join(root.path, 'cocos-js')).create(recursive: true);
  await Directory(p.join(root.path, 'src')).create(recursive: true);
  await File(p.join(root.path, 'index.html')).writeAsString(
    '<title>PvZ2 Gardendless Online | $version</title>play.pvzge.com',
  );
  await File(p.join(root.path, 'src', 'settings.json'))
      .writeAsString('{"platform":"web-mobile"}');
  await File(p.join(root.path, 'src', 'import-map.json')).writeAsString('{}');
  await File(p.join(root.path, 'cocos-js', 'cc.js'))
      .writeAsString('console.log("cc");');
}
