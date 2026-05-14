import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/constants.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('ohos stores resources under the application documents directory',
      () async {
    final temp = await Directory.systemTemp.createTemp('gardendless_paths_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final documents = Directory(p.join(temp.path, 'documents'));
    final external = Directory(p.join(temp.path, 'external'));

    final paths = await AppPathsService(
      platformName: 'ohos',
      documentsDirectoryProvider: () async => documents,
      externalStorageDirectoryProvider: () async => external,
    ).ensureInitialized();

    expect(paths.root.path, p.join(documents.path, resourceFolderName));
    expect(await paths.importDir.exists(), isTrue);
    expect(await paths.importDocsDir.exists(), isFalse);
    expect(await paths.currentDir.exists(), isTrue);
    expect(await paths.previousDir.exists(), isTrue);
    expect(await paths.stagingDir.exists(), isTrue);
    expect(paths.manifestFile.path, p.join(paths.root.path, 'manifest.json'));
  });
}
