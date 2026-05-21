import 'dart:io';

import 'package:archive/archive.dart' as archive;
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/resource_picker_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('returns null when the directory picker is cancelled', () async {
    final picker = ResourcePickerService(
      platformName: 'test',
      directoryPathPicker: ({
        bool? canCreateDirectories,
        String? confirmButtonText,
        String? initialDirectory,
      }) async =>
          null,
    );

    expect(await picker.pickDocsDirectory(), isNull);
  });

  test('accepts a selected docs directory', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    await File(p.join(temp.path, 'index.html')).writeAsString('ok');

    final picker = ResourcePickerService(
      platformName: 'test',
      directoryPathPicker: ({
        bool? canCreateDirectories,
        String? confirmButtonText,
        String? initialDirectory,
      }) async =>
          temp.path,
    );

    expect((await picker.pickDocsDirectory())?.path, temp.path);
  });

  test('uses nested docs when the selected directory contains docs', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final docs = Directory(p.join(temp.path, 'docs'));
    await docs.create(recursive: true);
    await File(p.join(docs.path, 'index.html')).writeAsString('ok');

    final picker = ResourcePickerService(
      platformName: 'test',
      directoryPathPicker: ({
        bool? canCreateDirectories,
        String? confirmButtonText,
        String? initialDirectory,
      }) async =>
          temp.path,
    );

    expect((await picker.pickDocsDirectory())?.path, docs.path);
  });

  test('android returns the local imported docs directory', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final localImportDocs = Directory(p.join(temp.path, 'import', 'docs'));

    final picker = ResourcePickerService(
      platformName: 'android',
      directoryPathPicker: ({
        bool? canCreateDirectories,
        String? confirmButtonText,
        String? initialDirectory,
      }) async {
        throw StateError('Android must not return a public filesystem path');
      },
      androidDirectoryImporter: ({required Directory targetDirectory}) async {
        expect(targetDirectory.path, localImportDocs.path);
        await targetDirectory.create(recursive: true);
        await File(p.join(targetDirectory.path, 'index.html'))
            .writeAsString('ok');
        return targetDirectory.path;
      },
    );

    final picked = await picker.pickDocsDirectory(
      localImportDocsDir: localImportDocs,
    );

    expect(picked?.path, localImportDocs.path);
    expect(await File(p.join(localImportDocs.path, 'index.html')).exists(),
        isTrue);
  });

  test('ios extracts the selected zip into the local imported docs directory',
      () async {
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

    var zipPickerWasCalled = false;
    final picker = ResourcePickerService(
      platformName: 'ios',
      directoryPathPicker: ({
        bool? canCreateDirectories,
        String? confirmButtonText,
        String? initialDirectory,
      }) async {
        throw StateError('iOS must not call getDirectoryPath');
      },
      filePicker: ({
        required List<file_selector.XTypeGroup> acceptedTypeGroups,
        String? confirmButtonText,
        String? initialDirectory,
      }) async {
        zipPickerWasCalled = true;
        expect(acceptedTypeGroups.single.extensions, contains('zip'));
        return file_selector.XFile(selectedZip.path);
      },
    );

    final picked = await picker.pickDocsDirectory(
      initialDirectory: Directory(p.join(temp.path, 'downloads')),
      localImportDocsDir: localImportDocs,
    );

    expect(zipPickerWasCalled, isTrue);
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

  test('ios returns null when the zip picker is cancelled', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final picker = ResourcePickerService(
      platformName: 'ios',
      directoryPathPicker: ({
        bool? canCreateDirectories,
        String? confirmButtonText,
        String? initialDirectory,
      }) async {
        throw StateError('iOS must not call getDirectoryPath');
      },
      filePicker: ({
        required List<file_selector.XTypeGroup> acceptedTypeGroups,
        String? confirmButtonText,
        String? initialDirectory,
      }) async =>
          null,
    );

    expect(
      await picker.pickDocsDirectory(
        localImportDocsDir: Directory(p.join(temp.path, 'import', 'docs')),
      ),
      isNull,
    );
  });

  test('ios rejects zips without a docs resource root', () async {
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
      platformName: 'ios',
      filePicker: ({
        required List<file_selector.XTypeGroup> acceptedTypeGroups,
        String? confirmButtonText,
        String? initialDirectory,
      }) async =>
          file_selector.XFile(selectedZip.path),
    );

    await expectLater(
      picker.pickDocsDirectory(
        localImportDocsDir: Directory(p.join(temp.path, 'import', 'docs')),
      ),
      throwsA(isA<ResourcePickerFailure>()),
    );
  });

  test('ohos uses the document picker channel callback', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    await File(p.join(temp.path, 'index.html')).writeAsString('ok');

    final picker = ResourcePickerService(
      platformName: 'ohos',
      ohosDirectoryPathPicker: () async => temp.path,
    );

    expect((await picker.pickDocsDirectory())?.path, temp.path);
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
