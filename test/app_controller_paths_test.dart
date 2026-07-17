import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:gardendless_loader/src/services/import_service.dart';
import 'package:gardendless_loader/src/services/local_game_server.dart';
import 'package:gardendless_loader/src/services/manifest_store.dart';
import 'package:gardendless_loader/src/services/resource_picker_service.dart';
import 'package:gardendless_loader/src/services/resource_validator.dart';
import 'package:path/path.dart' as p;

void main() {
  test('cleans an interrupted import on startup without replacing current',
      () async {
    final root =
        await Directory.systemTemp.createTemp('gl_controller_recover_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final paths = await AppPathsService(
      rootOverride: root,
      platformName: 'test',
    ).ensureInitialized();
    await _writeValidResource(paths.slotADir);
    await File(p.join(paths.slotBDir.path, 'partial.bin'))
        .writeAsString('incomplete');
    await ManifestStore(paths.manifestFile).write(
      ResourceManifest.initial().copyWith(
        activeSlot: ResourceSlot.slotA,
        transactionSlot: ResourceSlot.slotB,
        resourceStatus: ResourceStatus.ready,
        transactionState: TransactionState.extracting,
      ),
    );

    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );
    await controller.initialize();

    expect(controller.message, '上次导入意外中断，已清理未完成文件');
    expect(controller.hasCurrentResource, isTrue);
    expect(
      await File(p.join(paths.slotADir.path, 'index.html')).exists(),
      isTrue,
    );
    expect(await paths.slotBDir.list().isEmpty, isTrue);
    expect(controller.manifest.transactionState, TransactionState.idle);
  });

  test('starts with the active slot when old-slot cleanup must retry',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_cleanup_retry_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final paths = await AppPathsService(
      rootOverride: root,
      platformName: 'test',
    ).ensureInitialized();
    await _writeValidResource(paths.slotADir);
    await _writeValidResource(paths.slotBDir);
    await ManifestStore(paths.manifestFile).write(
      ResourceManifest.initial().copyWith(
        activeSlot: ResourceSlot.slotB,
        transactionSlot: ResourceSlot.slotA,
        transactionState: TransactionState.cleaningOldSlot,
        resourceStatus: ResourceStatus.ready,
      ),
    );
    final importServer = LocalGameServer();
    addTearDown(importServer.stop);
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      importService: ImportService(
        validator: ResourceValidator(),
        server: importServer,
        oldSlotCleaner: (_) async {
          throw const FileSystemException('slot is busy');
        },
      ),
    );

    await controller.initialize();

    expect(controller.initialized, isTrue);
    expect(controller.hasCurrentResource, isTrue);
    expect(controller.manifest.activeSlot, ResourceSlot.slotB);
    expect(
        controller.manifest.transactionState, TransactionState.cleaningOldSlot);
    expect(controller.message, '游戏资源可用，旧槽清理将在下次启动重试');
  });

  test('publishes platform extraction progress before the picker completes',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_controller_flow_');
    final releaseImporter = Completer<void>();
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      importProgressTickInterval: const Duration(milliseconds: 10),
      resourcePickerService: ResourcePickerService(
        platformName: 'android',
        mobileZipImporter: ({
          required targetDirectory,
          onProgress,
        }) async {
          onProgress?.call(const ImportProgress(
            phase: ImportPhase.extracting,
            copiedBytes: 256,
            totalBytes: 1024,
            message: '正在解压资源',
          ));
          await releaseImporter.future;
          await _writeValidResource(Directory(targetDirectory));
          return targetDirectory;
        },
      ),
    );
    await controller.initialize();

    final importFuture = controller.importResources();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.importProgress.phase, ImportPhase.extracting);
      expect(controller.importProgress.value, 0.25);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(
        controller.importProgress.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 20)),
      );
    } finally {
      releaseImporter.complete();
      await importFuture;
    }
  });

  test('keeps the screen awake only while an import is active', () async {
    final root = await Directory.systemTemp.createTemp('gl_controller_awake_');
    final awakeStates = <bool>[];
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      importAwakeModeGetter: () async => false,
      importAwakeModeSetter: (enabled) async => awakeStates.add(enabled),
      resourcePickerService: ResourcePickerService(
        platformName: 'android',
        mobileZipImporter: ({
          required targetDirectory,
          onProgress,
        }) async {
          await _writeValidResource(Directory(targetDirectory));
          return targetDirectory;
        },
      ),
    );
    await controller.initialize();

    await controller.importResources();

    expect(awakeStates, [true, false]);
  });

  test('preserves an already enabled screen awake setting', () async {
    final root = await Directory.systemTemp.createTemp('gl_controller_awake_');
    final awakeStates = <bool>[];
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      importAwakeModeGetter: () async => true,
      importAwakeModeSetter: (enabled) async => awakeStates.add(enabled),
      resourcePickerService: ResourcePickerService(
        platformName: 'android',
        mobileZipImporter: ({
          required targetDirectory,
          onProgress,
        }) async {
          await _writeValidResource(Directory(targetDirectory));
          return targetDirectory;
        },
      ),
    );
    await controller.initialize();

    await controller.importResources();

    expect(awakeStates, isEmpty);
  });

  test('keeps completed progress visible briefly before returning to idle',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_controller_done_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      importCompletionVisibilityDuration: const Duration(seconds: 2),
      importAwakeModeSetter: (_) async {},
      resourcePickerService: ResourcePickerService(
        platformName: 'android',
        mobileZipImporter: ({
          required targetDirectory,
          onProgress,
        }) async {
          await _writeValidResource(Directory(targetDirectory));
          return targetDirectory;
        },
      ),
    );
    await controller.initialize();

    await controller.importResources();
    expect(controller.importProgress.phase, ImportPhase.completed);

    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(controller.importProgress.phase, ImportPhase.idle);
  });

  test('keeps failed progress until the user dismisses it', () async {
    final root = await Directory.systemTemp.createTemp('gl_controller_fail_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      importAwakeModeSetter: (_) async {},
      resourcePickerService: ResourcePickerService(
        platformName: 'android',
        mobileZipImporter: ({
          required targetDirectory,
          onProgress,
        }) async {
          throw PlatformException(
            code: 'zip_import_failed',
            message: '选择的 ZIP 已损坏',
          );
        },
      ),
    );
    await controller.initialize();

    await controller.importResources();
    expect(controller.importProgress.phase, ImportPhase.failed);
    expect(controller.importProgress.message, '选择的 ZIP 已损坏');

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.importProgress.phase, ImportPhase.failed);

    controller.dismissImportProgress();
    expect(controller.importProgress.phase, ImportPhase.idle);
  });

  test('shows no selected docs path before the picker returns one', () async {
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

    expect(controller.userVisibleImportDocs, '尚未选择 ZIP');
  });

  test('imports the docs directory extracted from the selected zip', () async {
    final root = await Directory.systemTemp.createTemp('gl_controller_paths_');
    String? extractionTarget;
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      resourcePickerService: ResourcePickerService(
        platformName: 'android',
        mobileZipImporter: ({
          required targetDirectory,
          onProgress,
        }) async {
          extractionTarget = targetDirectory;
          await _writeValidResource(Directory(targetDirectory));
          return targetDirectory;
        },
      ),
    );

    await controller.initialize();
    await controller.importResources();

    expect(extractionTarget, p.join(root.path, 'slot-a'));
    expect(controller.userVisibleImportDocs, p.join(root.path, 'slot-a'));
    expect(controller.hasCurrentResource, isTrue);
    expect(controller.manifest.activeSlot, ResourceSlot.slotA);
    expect(
      await File(p.join(root.path, 'slot-a', 'index.html')).exists(),
      isTrue,
    );
    expect(await Directory(p.join(root.path, 'slot-b')).list().isEmpty, isTrue);
    final diagnostics = controller.diagnostics().toCopyText();
    expect(diagnostics, contains('activeSlot: slotA'));
    expect(diagnostics,
        contains('activeResourcePath: ${p.join(root.path, 'slot-a')}'));
    expect(diagnostics, contains('active slot validation: ready'));
  });
}

Future<void> _writeValidResource(Directory root) async {
  await root.create(recursive: true);
  await File(p.join(root.path, 'index.html')).writeAsString(
    '<html><head><title>PvZ2 Gardendless</title></head>'
    '<body>play.pvzge.com</body></html>',
  );
  await File(p.join(root.path, 'src', 'settings.json')).create(recursive: true);
  await File(p.join(root.path, 'src', 'settings.json'))
      .writeAsString('{"platform":"web-mobile"}');
  await File(p.join(root.path, 'src', 'import-map.json')).writeAsString('{}');
  await File(p.join(root.path, 'assets', 'asset.txt')).create(recursive: true);
  await File(p.join(root.path, 'assets', 'asset.txt')).writeAsString('asset');
  await File(p.join(root.path, 'cocos-js', 'cc.js')).create(recursive: true);
  await File(p.join(root.path, 'cocos-js', 'cc.js')).writeAsString('cc');
}
