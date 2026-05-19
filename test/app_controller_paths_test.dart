import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:gardendless_loader/src/services/resource_picker_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('shows no selected docs path before the picker returns one', () async {
    final root = await Directory.systemTemp.createTemp('gl_controller_paths_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );

    await controller.initialize();

    expect(controller.userVisibleImportDocs, '尚未选择 docs');
  });

  test('imports the docs directory selected by the picker', () async {
    final root = await Directory.systemTemp.createTemp('gl_controller_paths_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final selectedDocs = Directory(p.join(root.path, 'downloads', 'docs'));
    await _writeValidResource(selectedDocs);

    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      resourcePickerService: ResourcePickerService(
        platformName: 'test',
        directoryPathPicker: ({
          bool? canCreateDirectories,
          String? confirmButtonText,
          String? initialDirectory,
        }) async =>
            selectedDocs.path,
      ),
    );

    await controller.initialize();
    await controller.importResources();

    expect(controller.userVisibleImportDocs, selectedDocs.path);
    expect(controller.hasCurrentResource, isTrue);
    expect(
      await File(p.join(root.path, 'current', 'index.html')).exists(),
      isTrue,
    );
  });
}

Future<void> _writeValidResource(Directory root) async {
  await Directory(p.join(root.path, 'assets')).create(recursive: true);
  await Directory(p.join(root.path, 'cocos-js')).create(recursive: true);
  await Directory(p.join(root.path, 'src')).create(recursive: true);
  await File(p.join(root.path, 'index.html')).writeAsString(
    '<html><head><title>PvZ2 Gardendless</title></head><body>play.pvzge.com</body></html>',
  );
  await File(p.join(root.path, 'src', 'settings.json'))
      .writeAsString('{"platform":"web-mobile"}');
  await File(p.join(root.path, 'src', 'import-map.json')).writeAsString('{}');
  await File(p.join(root.path, 'cocos-js', 'cc.js')).writeAsString('cc');
}
