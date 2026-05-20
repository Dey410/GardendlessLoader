import 'dart:io';

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
