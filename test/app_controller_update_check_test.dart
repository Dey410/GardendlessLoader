import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:gardendless_loader/src/services/update_check_service.dart';

void main() {
  test('manual update check exposes newer GitHub release', () async {
    final root = await Directory.systemTemp.createTemp('gl_update_');
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        currentVersion: '0.1.0',
        loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{
  "tag_name": "v0.2.0",
  "name": "GardendlessLoader 0.2.0",
  "html_url": "https://github.com/Dey410/GardendlessLoader/releases/tag/v0.2.0"
}
''',
        ),
      ),
    );

    await controller.initialize();
    await controller.checkForUpdates();

    expect(controller.availableUpdate?.latestVersion, '0.2.0');
    expect(controller.availableUpdate?.currentVersion, '0.1.0');
    expect(controller.message, isNull);
  });

  test('manual update check reports when current version is already latest',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_update_');
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        currentVersion: '0.2.0',
        loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{
  "tag_name": "v0.2.0",
  "html_url": "https://github.com/Dey410/GardendlessLoader/releases/tag/v0.2.0"
}
''',
        ),
      ),
    );

    await controller.initialize();
    await controller.checkForUpdates();

    expect(controller.availableUpdate, isNull);
    expect(controller.message, 'v0.2.0');
  });

  test('silent update check failure does not set user message', () async {
    final root = await Directory.systemTemp.createTemp('gl_update_');
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        loader: (uri, timeout, maxBytes) async =>
            throw const SocketException('offline'),
      ),
    );

    await controller.initialize();
    await controller.checkForUpdates(silent: true);

    expect(controller.availableUpdate, isNull);
    expect(controller.message, isNull);
  });

  test('manual update check failure sets retry message', () async {
    final root = await Directory.systemTemp.createTemp('gl_update_');
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        loader: (uri, timeout, maxBytes) async =>
            throw const SocketException('offline'),
      ),
    );

    await controller.initialize();
    await controller.checkForUpdates();

    expect(controller.availableUpdate, isNull);
    expect(controller.message, '检查更新失败，请稍后重试');
  });

  test('defer update hides current release for this run', () async {
    final root = await Directory.systemTemp.createTemp('gl_update_');
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: UpdateCheckService(
        currentVersion: '0.1.0',
        loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{
  "tag_name": "v0.2.0",
  "html_url": "https://github.com/Dey410/GardendlessLoader/releases/tag/v0.2.0"
}
''',
        ),
      ),
    );

    await controller.initialize();
    await controller.checkForUpdates();
    controller.deferUpdate(controller.availableUpdate!);
    await controller.checkForUpdates(silent: true);

    expect(controller.availableUpdate, isNull);
  });
}
