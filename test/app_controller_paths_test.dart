import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('exposes the full import docs path for users', () async {
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

    expect(
      controller.userVisibleImportDocs,
      p.join(root.path, 'import', 'docs'),
    );
  });
}
