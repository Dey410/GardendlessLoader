import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/logging/app_logger.dart';
import 'package:gardendless_loader/src/logging/log_event_catalog.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:gardendless_loader/src/services/import_service.dart';
import 'package:gardendless_loader/src/services/manifest_store.dart';
import 'package:gardendless_loader/src/services/resource_picker_service.dart';
import 'package:gardendless_loader/src/services/resource_validator.dart';
import 'package:path/path.dart' as p;

void main() {
  test('initialization failure keeps user feedback and records diagnostics',
      () async {
    final logger = InMemoryAppLogger(
      appSessionId: 'app-session-1',
      source: LogSource.dart,
    );
    final controller = AppController(
      pathsService: AppPathsService(platformName: 'unsupported'),
      appLogger: logger,
    );

    await controller.initialize();

    expect(
      <String, Object?>{
        'showsFailure': controller.message?.startsWith('启动失败：') ?? false,
        'events': logger.events
            .map(
              (event) => <String, Object?>{
                'event': event.event,
                'outcome': event.outcome.name,
                'code': event.code,
                'operationId': event.operationId,
              },
            )
            .toList(),
      },
      <String, Object?>{
        'showsFailure': true,
        'events': <Map<String, Object?>>[
          {
            'event': 'app_initialization_started',
            'outcome': 'started',
            'code': null,
            'operationId': 'app-initialize',
          },
          {
            'event': 'app_initialization_stage_changed',
            'outcome': 'observed',
            'code': null,
            'operationId': 'app-initialize',
          },
          {
            'event': 'app_initialization_finished',
            'outcome': 'failed',
            'code': 'app_initialization_failed',
            'operationId': 'app-initialize',
          },
        ],
      },
    );
  });

  test('enables the game watermark by default', () async {
    final root = await Directory.systemTemp.createTemp('gl_settings_default_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );
    await controller.initialize();

    expect(controller.watermarkEnabled, isTrue);
  });

  test('remembers a disabled game watermark across app restarts', () async {
    final root = await Directory.systemTemp.createTemp('gl_settings_saved_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final firstController = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );
    await firstController.initialize();
    await firstController.setWatermarkEnabled(false);

    final restartedController = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );
    await restartedController.initialize();

    expect(restartedController.watermarkEnabled, isFalse);
  });

  test('persists re-enabling the game watermark', () async {
    final root = await Directory.systemTemp.createTemp('gl_settings_toggle_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final firstController = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );
    await firstController.initialize();
    await firstController.setWatermarkEnabled(false);
    await firstController.setWatermarkEnabled(true);

    final restartedController = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );
    await restartedController.initialize();

    expect(restartedController.watermarkEnabled, isTrue);
  });

  test('persists the latest watermark choice after rapid toggles', () async {
    final root = await Directory.systemTemp.createTemp('gl_settings_rapid_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final firstController = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );
    await firstController.initialize();
    final disable = firstController.setWatermarkEnabled(false);
    final enable = firstController.setWatermarkEnabled(true);
    await Future.wait([disable, enable]);

    final restartedController = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );
    await restartedController.initialize();

    expect(restartedController.watermarkEnabled, isTrue);
  });

  test('remembers automatic sun collection across app restarts', () async {
    final root = await Directory.systemTemp.createTemp('gl_auto_sun_saved_');
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
    await ManifestStore(paths.manifestFile).write(
      ResourceManifest.initial().copyWith(
        activeSlot: ResourceSlot.slotA,
        resourceStatus: ResourceStatus.ready,
      ),
    );

    final firstController = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );
    await firstController.initialize();
    await firstController.setAutoCollectSunEnabled(true);

    final restartedController = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );
    await restartedController.initialize();

    expect(restartedController.autoCollectSunEnabled, isTrue);
  });

  test('persists the latest automatic sun choice after rapid toggles',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_auto_sun_rapid_');
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
    await ManifestStore(paths.manifestFile).write(
      ResourceManifest.initial().copyWith(
        activeSlot: ResourceSlot.slotA,
        resourceStatus: ResourceStatus.ready,
      ),
    );

    final firstController = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );
    await firstController.initialize();
    final enable = firstController.setAutoCollectSunEnabled(true);
    final disable = firstController.setAutoCollectSunEnabled(false);
    await Future.wait([enable, disable]);

    final restartedController = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
    );
    await restartedController.initialize();

    expect(restartedController.autoCollectSunEnabled, isFalse);
  });

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
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      importService: ImportService(
        validator: ResourceValidator(),
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

    final extractionPublished = Completer<ImportProgress>();
    final elapsedAdvanced = Completer<ImportProgress>();
    void captureExtractionProgress() {
      final progress = controller.importProgress;
      if (progress.phase != ImportPhase.extracting) {
        return;
      }
      if (!extractionPublished.isCompleted) {
        extractionPublished.complete(progress);
      }
      if (progress.elapsed > Duration.zero && !elapsedAdvanced.isCompleted) {
        elapsedAdvanced.complete(progress);
      }
    }

    controller.addListener(captureExtractionProgress);
    addTearDown(
      () => controller.removeListener(captureExtractionProgress),
    );

    final importFuture = controller.importResources();
    try {
      final initialProgress = await extractionPublished.future.timeout(
        const Duration(seconds: 1),
      );
      expect(initialProgress.value, 0.25);

      final advancedProgress = await elapsedAdvanced.future.timeout(
        const Duration(seconds: 1),
      );
      expect(
        advancedProgress.elapsed,
        greaterThan(initialProgress.elapsed),
      );
    } finally {
      releaseImporter.complete();
      await importFuture;
    }
  });

  test('shows feedback before opening the native ZIP picker', () async {
    final root = await Directory.systemTemp.createTemp('gl_picker_feedback_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    late final AppController controller;
    controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      importAwakeModeGetter: () async => true,
      importAwakeModeSetter: (_) async {},
      resourcePickerService: ResourcePickerService(
        platformName: 'android',
        mobileZipImporter: ({
          required targetDirectory,
          onProgress,
        }) async {
          expect(controller.message, '正在打开系统文件选择器');
          return null;
        },
      ),
    );
    await controller.initialize();

    await controller.importResources();

    expect(controller.message, '已取消选择 ZIP');
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
    final logger = InMemoryAppLogger(
      appSessionId: 'app-session-import',
      source: LogSource.dart,
      eventSchemas: defaultLogEventSchemas,
    );
    String? extractionTarget;
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      appLogger: logger,
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
    final importEvents = logger.events
        .where((event) => event.category.startsWith('resource.'))
        .toList(growable: false);
    expect(
      importEvents.map((event) => event.event),
      containsAll(<String>[
        'resource_import_started',
        'resource_import_picker_started',
        'resource_import_picker_finished',
        'resource_validation_started',
        'resource_validation_finished',
        'resource_slot_activated',
        'resource_import_finished',
      ]),
    );
    expect(
      importEvents.map((event) => event.operationId).toSet(),
      hasLength(1),
    );
    expect(importEvents.first.operationId, isNotNull);
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
