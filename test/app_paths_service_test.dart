import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/constants.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('ohos stores resources under app documents instead of public Documents',
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
    expect(await paths.slotADir.exists(), isTrue);
    expect(await paths.slotBDir.exists(), isTrue);
    expect(
        await Directory(p.join(paths.root.path, 'current')).exists(), isFalse);
    expect(
        await Directory(p.join(paths.root.path, 'previous')).exists(), isFalse);
    expect(
        await Directory(p.join(paths.root.path, 'staging')).exists(), isFalse);
    expect(
        await Directory(p.join(paths.root.path, 'import')).exists(), isFalse);
    expect(paths.manifestFile.path, p.join(paths.root.path, 'manifest.json'));
  });

  test('ohos ignores external storage for resource roots', () async {
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
    expect(await paths.slotADir.exists(), isTrue);
    expect(await paths.slotBDir.exists(), isTrue);
  });

  test('ohos stores resources under documents when external is unavailable',
      () async {
    final temp = await Directory.systemTemp.createTemp('gardendless_paths_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final documents = Directory(p.join(temp.path, 'documents'));
    final paths = await AppPathsService(
      platformName: 'ohos',
      documentsDirectoryProvider: () async => documents,
      externalStorageDirectoryProvider: () async => null,
    ).ensureInitialized();

    expect(paths.root.path, p.join(documents.path, resourceFolderName));
    expect(await paths.slotADir.exists(), isTrue);
    expect(await paths.slotBDir.exists(), isTrue);
  });
}
