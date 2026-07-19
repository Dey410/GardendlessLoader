import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/constants.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('android excludes resource files from media scanning', () async {
    final temp = await Directory.systemTemp.createTemp('gardendless_paths_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final documents = Directory(p.join(temp.path, 'documents'));
    final external = Directory(p.join(temp.path, 'external'));
    final existingRoot = Directory(p.join(external.path, resourceFolderName));
    await existingRoot.create(recursive: true);
    final existingResource = File(p.join(existingRoot.path, 'existing.png'));
    await existingResource.writeAsBytes(const [1, 2, 3]);

    final service = AppPathsService(
      platformName: 'android',
      documentsDirectoryProvider: () async => documents,
      externalStorageDirectoryProvider: () async => external,
    );
    final paths = await service.ensureInitialized();

    final mediaExclusionMarker = File(p.join(paths.root.path, '.nomedia'));
    expect(await mediaExclusionMarker.exists(), isTrue);
    expect(await mediaExclusionMarker.length(), 0);
    expect(await existingResource.readAsBytes(), const [1, 2, 3]);

    await service.ensureInitialized();
    expect(await mediaExclusionMarker.exists(), isTrue);
    expect(await existingResource.readAsBytes(), const [1, 2, 3]);
  });

  test('ios stores resources under app documents', () async {
    final temp = await Directory.systemTemp.createTemp('gardendless_paths_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final documents = Directory(p.join(temp.path, 'documents'));
    final external = Directory(p.join(temp.path, 'external'));
    final paths = await AppPathsService(
      platformName: 'ios',
      documentsDirectoryProvider: () async => documents,
      externalStorageDirectoryProvider: () async => external,
    ).ensureInitialized();

    expect(paths.root.path, p.join(documents.path, resourceFolderName));
    expect(paths.root.path, isNot(startsWith(external.path)));
  });

  test(
    'ohos stores resources under app documents instead of public Documents',
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
        await Directory(p.join(paths.root.path, 'current')).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(paths.root.path, 'previous')).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(paths.root.path, 'staging')).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(paths.root.path, 'import')).exists(),
        isFalse,
      );
      expect(paths.manifestFile.path, p.join(paths.root.path, 'manifest.json'));
      expect(paths.gpNextDir.path, p.join(paths.root.path, 'gp-next'));
      expect(await paths.gpNextPacksDir.exists(), isTrue);
      expect(await paths.gpNextPatchesDir.exists(), isTrue);
    },
  );

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

  test(
    'ohos stores resources under documents when external is unavailable',
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
    },
  );
}
