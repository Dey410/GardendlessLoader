import 'dart:io';

import 'package:archive/archive.dart' as archive;
import 'package:file_selector/file_selector.dart' as file_selector;
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

    expect(controller.userVisibleImportDocs, '尚未选择 ZIP');
  });

  test('imports the docs directory extracted from the selected zip', () async {
    final root = await Directory.systemTemp.createTemp('gl_controller_paths_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final selectedZip = File(p.join(root.path, 'downloads', 'resource.zip'));
    await selectedZip.parent.create(recursive: true);
    await selectedZip.writeAsBytes(_buildResourceZip('release/docs'));

    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      resourcePickerService: ResourcePickerService(
        filePicker: ({
          required List<file_selector.XTypeGroup> acceptedTypeGroups,
          String? confirmButtonText,
          String? initialDirectory,
        }) async =>
            file_selector.XFile(selectedZip.path),
      ),
    );

    await controller.initialize();
    await controller.importResources();

    expect(
        controller.userVisibleImportDocs, p.join(root.path, 'import', 'docs'));
    expect(controller.hasCurrentResource, isTrue);
    expect(
      await File(p.join(root.path, 'current', 'index.html')).exists(),
      isTrue,
    );
  });
}

List<int> _buildResourceZip(String docsPrefix) {
  final zip = archive.Archive();

  void addTextFile(String relativePath, String content) {
    zip.addFile(
      archive.ArchiveFile.string(
          p.posix.join(docsPrefix, relativePath), content),
    );
  }

  addTextFile(
    'index.html',
    '<html><head><title>PvZ2 Gardendless</title></head><body>play.pvzge.com</body></html>',
  );
  addTextFile('src/settings.json', '{"platform":"web-mobile"}');
  addTextFile('src/import-map.json', '{}');
  addTextFile('assets/asset.txt', 'asset');
  addTextFile('cocos-js/cc.js', 'cc');

  return archive.ZipEncoder().encode(zip)!;
}
