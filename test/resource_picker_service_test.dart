import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/resource_picker_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('decodes progress method calls from the native importer channel',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(
      'io.github.dey410.gardendlessloader/resource_zip_importer',
    );
    const codec = StandardMethodCodec();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final temp = await Directory.systemTemp.createTemp('gl_native_progress_');
    final target = Directory(p.join(temp.path, 'slot-a'));
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(const MethodCall('progress', {
          'phase': 'extracting',
          'processedBytes': 384,
          'totalBytes': 1024,
          'processedFiles': 3,
          'totalFiles': 8,
          'message': '正在解压资源',
        })),
        null,
      );
      return target.path;
    });
    final received = <ImportProgress>[];

    await ResourcePickerService(platformName: 'android').pickAndExtractDocsZip(
      targetDirectory: target,
      onProgress: received.add,
    );

    expect(received, hasLength(1));
    expect(received.single.phase, ImportPhase.extracting);
    expect(received.single.copiedBytes, 384);
    expect(received.single.totalBytes, 1024);
    expect(received.single.copiedFiles, 3);
    expect(received.single.totalFiles, 8);
  });

  test('forwards streaming progress from the platform importer', () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_progress_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final received = <ImportProgress>[];
    final picker = ResourcePickerService(
      platformName: 'android',
      mobileZipImporter: ({
        required String targetDirectory,
        ImportProgressCallback? onProgress,
      }) async {
        onProgress?.call(const ImportProgress(
          phase: ImportPhase.extracting,
          copiedBytes: 512,
          totalBytes: 1024,
          message: '正在解压资源',
        ));
        return targetDirectory;
      },
    );

    await picker.pickAndExtractDocsZip(
      targetDirectory: Directory(p.join(temp.path, 'slot-a')),
      onProgress: received.add,
    );

    expect(received, hasLength(1));
    expect(received.single.phase, ImportPhase.extracting);
    expect(received.single.copiedBytes, 512);
    expect(received.single.totalBytes, 1024);
  });

  test('uses mobile streaming importer instead of reading the zip in Dart',
      () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final localImportDocs = Directory(p.join(temp.path, 'slot-a'));
    var importerCalled = false;

    final picker = ResourcePickerService(
      platformName: 'android',
      mobileZipImporter: ({
        required String targetDirectory,
        ImportProgressCallback? onProgress,
      }) async {
        importerCalled = true;
        expect(targetDirectory, localImportDocs.path);
        await localImportDocs.create(recursive: true);
        await File(p.join(localImportDocs.path, 'index.html'))
            .writeAsString('ok');
        return targetDirectory;
      },
    );

    final picked = await picker.pickAndExtractDocsZip(
      targetDirectory: localImportDocs,
    );

    expect(importerCalled, isTrue);
    expect(picked?.path, localImportDocs.path);
    expect(await File(p.join(localImportDocs.path, 'index.html')).exists(),
        isTrue);
  });

  test('uses iOS streaming importer instead of reading the zip in Dart',
      () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final localImportDocs = Directory(p.join(temp.path, 'slot-a'));
    var importerCalled = false;

    final picker = ResourcePickerService(
      platformName: 'ios',
      mobileZipImporter: ({
        required String targetDirectory,
        ImportProgressCallback? onProgress,
      }) async {
        importerCalled = true;
        expect(targetDirectory, localImportDocs.path);
        await localImportDocs.create(recursive: true);
        await File(p.join(localImportDocs.path, 'index.html'))
            .writeAsString('ok');
        return targetDirectory;
      },
    );

    final picked = await picker.pickAndExtractDocsZip(
      targetDirectory: localImportDocs,
    );

    expect(importerCalled, isTrue);
    expect(picked?.path, localImportDocs.path);
    expect(await File(p.join(localImportDocs.path, 'index.html')).exists(),
        isTrue);
  });

  test('uses OHOS streaming importer instead of reading the zip in Dart',
      () async {
    final temp = await Directory.systemTemp.createTemp('gl_picker_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final localImportDocs = Directory(p.join(temp.path, 'slot-a'));
    var importerCalled = false;

    final picker = ResourcePickerService(
      platformName: 'ohos',
      mobileZipImporter: ({
        required String targetDirectory,
        ImportProgressCallback? onProgress,
      }) async {
        importerCalled = true;
        expect(targetDirectory, localImportDocs.path);
        await localImportDocs.create(recursive: true);
        await File(p.join(localImportDocs.path, 'index.html'))
            .writeAsString('ok');
        return targetDirectory;
      },
    );

    final picked = await picker.pickAndExtractDocsZip(
      targetDirectory: localImportDocs,
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
      mobileZipImporter: ({
        required String targetDirectory,
        ImportProgressCallback? onProgress,
      }) async =>
          null,
    );

    expect(
      await picker.pickAndExtractDocsZip(
        targetDirectory: Directory(p.join(temp.path, 'slot-a')),
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
      mobileZipImporter: ({
        required String targetDirectory,
        ImportProgressCallback? onProgress,
      }) async {
        throw PlatformException(
          code: 'zip_import_failed',
          message: '无法导入选择的 ZIP：坏 ZIP',
        );
      },
    );

    await expectLater(
      picker.pickAndExtractDocsZip(
        targetDirectory: Directory(p.join(temp.path, 'slot-a')),
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
}
