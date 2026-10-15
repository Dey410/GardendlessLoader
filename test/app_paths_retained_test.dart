import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/constants.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:path/path.dart' as p;

void main() {
  for (final platform in ['android', 'ios', 'ohos']) {
    test('uses one $platform root and preserves existing files', () async {
      final fixture =
          await Directory.systemTemp.createTemp('gl_paths_retained_');
      final documents = Directory(p.join(fixture.path, 'documents'));
      final external = Directory(p.join(fixture.path, 'external'));
      final service = AppPathsService(
        platformName: platform,
        documentsDirectoryProvider: () async => documents,
        externalStorageDirectoryProvider: () async => external,
      );
      final paths = await service.ensureInitialized();
      final sentinel = File(p.join(paths.root.path, 'retained.txt'));
      await sentinel.writeAsString('existing');

      final repeated = await service.ensureInitialized();

      expect(
          paths.root.path,
          p.join(platform == 'android' ? external.path : documents.path,
              resourceFolderName));
      expect(repeated.root.path, paths.root.path);
      expect(await sentinel.readAsString(), 'existing');
      expect(await paths.slotADir.exists(), isTrue);
      expect(await paths.slotBDir.exists(), isTrue);
      expect(await File(p.join(paths.root.path, '.nomedia')).exists(),
          platform == 'android');
    });
  }
}
