import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/constants.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('ohos stores resources under public Documents when available', () async {
    final temp = await Directory.systemTemp.createTemp('gardendless_paths_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final documents = Directory(p.join(temp.path, 'documents'));
    final external = Directory(p.join(temp.path, 'external'));
    final publicDocuments = Directory(p.join(temp.path, 'public_documents'));

    final paths = await AppPathsService(
      platformName: 'ohos',
      documentsDirectoryProvider: () async => documents,
      externalStorageDirectoryProvider: () async => external,
      ohosPublicDocumentsDirectoryProvider: () async => publicDocuments,
    ).ensureInitialized();

    expect(paths.root.path, p.join(publicDocuments.path, resourceFolderName));
    expect(await paths.importDir.exists(), isTrue);
    expect(await paths.importDocsDir.exists(), isTrue);
    expect(await paths.currentDir.exists(), isTrue);
    expect(await paths.previousDir.exists(), isTrue);
    expect(await paths.stagingDir.exists(), isTrue);
    expect(paths.manifestFile.path, p.join(paths.root.path, 'manifest.json'));
  });

  test('ohos falls back to external storage when public Documents is unusable',
      () async {
    final temp = await Directory.systemTemp.createTemp('gardendless_paths_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final documents = Directory(p.join(temp.path, 'documents'));
    final external = Directory(p.join(temp.path, 'external'));
    final blockedPublicDocuments =
        File(p.join(temp.path, 'public_documents_file'));
    await blockedPublicDocuments.create();

    final paths = await AppPathsService(
      platformName: 'ohos',
      documentsDirectoryProvider: () async => documents,
      externalStorageDirectoryProvider: () async => external,
      ohosPublicDocumentsDirectoryProvider: () async =>
          Directory(blockedPublicDocuments.path),
    ).ensureInitialized();

    expect(paths.root.path, p.join(external.path, resourceFolderName));
    expect(await paths.importDocsDir.exists(), isTrue);
  });

  test('ohos falls back to documents when public and external are unavailable',
      () async {
    final temp = await Directory.systemTemp.createTemp('gardendless_paths_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final documents = Directory(p.join(temp.path, 'documents'));
    final blockedPublicDocuments =
        File(p.join(temp.path, 'public_documents_file'));
    await blockedPublicDocuments.create();

    final paths = await AppPathsService(
      platformName: 'ohos',
      documentsDirectoryProvider: () async => documents,
      externalStorageDirectoryProvider: () async => null,
      ohosPublicDocumentsDirectoryProvider: () async =>
          Directory(blockedPublicDocuments.path),
    ).ensureInitialized();

    expect(paths.root.path, p.join(documents.path, resourceFolderName));
    expect(await paths.importDocsDir.exists(), isTrue);
  });

  test('windows creates the final import docs directory next to the exe',
      () async {
    final temp = await Directory.systemTemp.createTemp('gardendless_paths_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final documents = Directory(p.join(temp.path, 'documents'));
    final executableDirectory = Directory(p.join(temp.path, 'release'));

    final paths = await AppPathsService(
      platformName: 'windows',
      documentsDirectoryProvider: () async => documents,
      externalStorageDirectoryProvider: () async => null,
      executableDirectoryProvider: () => executableDirectory,
    ).ensureInitialized();

    expect(
        paths.root.path, p.join(executableDirectory.path, resourceFolderName));
    expect(await paths.importDocsDir.exists(), isTrue);
    expect(paths.importDocsDir.path,
        p.join(executableDirectory.path, resourceFolderName, 'import', 'docs'));
  });
}
