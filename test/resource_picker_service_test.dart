import 'dart:io';

import 'package:archive/archive.dart' as archive;
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/resource_picker_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('uses Android streaming importer instead of reading the zip in Dart',
      () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final localImportDocs = Directory(p.join(temp.path, 'import', 'docs'));
    var importerCalled = false;

    final picker = ResourcePickerService(
      platformName: 'android',
      filePicker: ({
        required List<file_selector.XTypeGroup> acceptedTypeGroups,
        String? confirmButtonText,
        String? initialDirectory,
      }) async {
        fail('Android imports should not use file_selector.readAsBytes path');
      },
      androidZipImporter: ({required String targetDirectory}) async {
        importerCalled = true;
        expect(targetDirectory, localImportDocs.path);
        await localImportDocs.create(recursive: true);
        await File(p.join(localImportDocs.path, 'index.html'))
            .writeAsString('ok');
        return targetDirectory;
      },
    );

    final picked = await picker.pickAndExtractDocsZip(
      localImportDocsDir: localImportDocs,
    );

    expect(importerCalled, isTrue);
    expect(picked?.path, localImportDocs.path);
    expect(await File(p.join(localImportDocs.path, 'index.html')).exists(),
        isTrue);
  });

  test('returns null when Android streaming importer is cancelled', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final picker = ResourcePickerService(
      platformName: 'android',
      androidZipImporter: ({required String targetDirectory}) async => null,
    );

    expect(
      await picker.pickAndExtractDocsZip(
        localImportDocsDir: Directory(p.join(temp.path, 'import', 'docs')),
      ),
      isNull,
    );
  });

  test('maps Android streaming importer failures to picker failures', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final picker = ResourcePickerService(
      platformName: 'android',
      androidZipImporter: ({required String targetDirectory}) async {
        throw PlatformException(
          code: 'zip_import_failed',
          message: '无法导入选择的 ZIP：坏 ZIP',
        );
      },
    );

    await expectLater(
      picker.pickAndExtractDocsZip(
        localImportDocsDir: Directory(p.join(temp.path, 'import', 'docs')),
      ),
      throwsA(
        isA<ResourcePickerFailure>().having(
          (failure) => failure.message,
          'message',
          '无法导入选择的 ZIP：坏 ZIP',
        ),
      ),
    );
  });

  test('returns null when the zip picker is cancelled', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final picker = ResourcePickerService(
      filePicker: ({
        required List<file_selector.XTypeGroup> acceptedTypeGroups,
        String? confirmButtonText,
        String? initialDirectory,
      }) async {
        expect(acceptedTypeGroups.single.extensions, contains('zip'));
        return null;
      },
    );

    expect(
      await picker.pickAndExtractDocsZip(
        localImportDocsDir: Directory(p.join(temp.path, 'import', 'docs')),
      ),
      isNull,
    );
  });

  test('extracts a nested docs directory from the selected zip', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final selectedZip = File(p.join(temp.path, 'resource.zip'));
    await selectedZip.writeAsBytes(_buildResourceZip('release/docs'));
    final localImportDocs = Directory(p.join(temp.path, 'import', 'docs'));
    await localImportDocs.create(recursive: true);
    await File(p.join(localImportDocs.path, 'stale.txt')).writeAsString('old');

    final picker = ResourcePickerService(
      filePicker: ({
        required List<file_selector.XTypeGroup> acceptedTypeGroups,
        String? confirmButtonText,
        String? initialDirectory,
      }) async {
        expect(acceptedTypeGroups.single.extensions, contains('zip'));
        return file_selector.XFile(selectedZip.path);
      },
    );

    final picked = await picker.pickAndExtractDocsZip(
      initialDirectory: Directory(p.join(temp.path, 'downloads')),
      localImportDocsDir: localImportDocs,
    );

    expect(picked?.path, localImportDocs.path);
    expect(await File(p.join(localImportDocs.path, 'index.html')).exists(),
        isTrue);
    expect(
      await File(p.join(localImportDocs.path, 'src', 'settings.json')).exists(),
      isTrue,
    );
    expect(await File(p.join(localImportDocs.path, 'stale.txt')).exists(),
        isFalse);
  });

  test('extracts docs when the zip root is the resource directory', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final selectedZip = File(p.join(temp.path, 'resource.zip'));
    await selectedZip.writeAsBytes(_buildResourceZip(''));
    final localImportDocs = Directory(p.join(temp.path, 'import', 'docs'));

    final picker = ResourcePickerService(
      filePicker: ({
        required List<file_selector.XTypeGroup> acceptedTypeGroups,
        String? confirmButtonText,
        String? initialDirectory,
      }) async =>
          file_selector.XFile(selectedZip.path),
    );

    final picked = await picker.pickAndExtractDocsZip(
      localImportDocsDir: localImportDocs,
    );

    expect(picked?.path, localImportDocs.path);
    expect(await File(p.join(localImportDocs.path, 'index.html')).exists(),
        isTrue);
  });

  test('rejects zips without a docs resource root', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final selectedZip = File(p.join(temp.path, 'resource.zip'));
    final zip = archive.Archive()
      ..addFile(archive.ArchiveFile.string('readme.txt', 'not docs'));
    await selectedZip.writeAsBytes(archive.ZipEncoder().encode(zip)!);

    final picker = ResourcePickerService(
      filePicker: ({
        required List<file_selector.XTypeGroup> acceptedTypeGroups,
        String? confirmButtonText,
        String? initialDirectory,
      }) async =>
          file_selector.XFile(selectedZip.path),
    );

    await expectLater(
      picker.pickAndExtractDocsZip(
        localImportDocsDir: Directory(p.join(temp.path, 'import', 'docs')),
      ),
      throwsA(isA<ResourcePickerFailure>()),
    );
  });

  test('rejects unsafe zip paths', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final selectedZip = File(p.join(temp.path, 'resource.zip'));
    final zip = archive.Archive()
      ..addFile(archive.ArchiveFile.string('../docs/index.html', 'bad'));
    await selectedZip.writeAsBytes(archive.ZipEncoder().encode(zip)!);

    final picker = ResourcePickerService(
      filePicker: ({
        required List<file_selector.XTypeGroup> acceptedTypeGroups,
        String? confirmButtonText,
        String? initialDirectory,
      }) async =>
          file_selector.XFile(selectedZip.path),
    );

    await expectLater(
      picker.pickAndExtractDocsZip(
        localImportDocsDir: Directory(p.join(temp.path, 'import', 'docs')),
      ),
      throwsA(isA<ResourcePickerFailure>()),
    );
  });
}

List<int> _buildResourceZip(String docsPrefix) {
  final zip = archive.Archive();

  void addTextFile(String relativePath, String content) {
    final path = docsPrefix.isEmpty
        ? relativePath
        : p.posix.join(docsPrefix, relativePath);
    zip.addFile(archive.ArchiveFile.string(path, content));
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
