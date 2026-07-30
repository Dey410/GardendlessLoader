import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/import_service.dart';
import 'package:gardendless_loader/src/services/manifest_store.dart';
import 'package:gardendless_loader/src/services/resource_self_check.dart';
import 'package:gardendless_loader/src/services/resource_validator.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late AppPaths paths;
  late ImportService importService;
  late ManifestStore manifestStore;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gl_import_');
    paths = AppPaths(
      root: temp,
      manifestFile: File(p.join(temp.path, 'manifest.json')),
    );
    for (final directory in [
      paths.legacyImportDir,
      paths.legacyCurrentDir,
      paths.legacyPreviousDir,
      paths.legacyStagingDir,
      paths.slotADir,
      paths.slotBDir,
    ]) {
      await directory.create(recursive: true);
    }
    importService = ImportService(validator: ResourceValidator());
    manifestStore = ManifestStore(paths.manifestFile);
  });

  test('first import activates the extracted slot in place', () async {
    final target = await importService.beginImport(
      paths: paths,
      manifestStore: manifestStore,
    );
    expect(target.slot, ResourceSlot.slotA);
    expect(target.directory.path, paths.slotADir.path);

    await _writeValidResource(
      target.directory,
      title: 'PvZ2 Gardendless Online | 0.12.0',
    );
    final manifest = await importService.completeImport(
      paths: paths,
      manifestStore: manifestStore,
      target: target,
    );

    expect(manifest.activeSlot, ResourceSlot.slotA);
    expect(manifest.transactionState, TransactionState.idle);
    expect(manifest.gameVersion, '0.12.0');
    expect(
      await File(p.join(paths.slotADir.path, 'index.html')).exists(),
      isTrue,
    );
    expect(await paths.slotBDir.list().isEmpty, isTrue);
  });

  test('successful update activates the inactive slot and clears the old slot',
      () async {
    var target = await importService.beginImport(
      paths: paths,
      manifestStore: manifestStore,
    );
    await _writeValidResource(
      target.directory,
      title: 'PvZ2 Gardendless Old | 0.11.0',
    );
    await importService.completeImport(
      paths: paths,
      manifestStore: manifestStore,
      target: target,
    );
    await manifestStore.write(
      (await manifestStore.read()).copyWith(autoCollectSunEnabled: true),
    );

    target = await importService.beginImport(
      paths: paths,
      manifestStore: manifestStore,
    );
    expect(target.slot, ResourceSlot.slotB);
    await _writeValidResource(
      target.directory,
      title: 'PvZ2 Gardendless New | 0.12.0',
    );
    final manifest = await importService.completeImport(
      paths: paths,
      manifestStore: manifestStore,
      target: target,
    );

    expect(manifest.activeSlot, ResourceSlot.slotB);
    expect(manifest.gameVersion, '0.12.0');
    expect(manifest.transactionState, TransactionState.idle);
    expect(manifest.autoCollectSunEnabled, isFalse);
    expect(await paths.slotADir.list().isEmpty, isTrue);
    expect(
      await File(p.join(paths.slotBDir.path, 'index.html')).exists(),
      isTrue,
    );
  });

  test(
      'startup keeps the active slot when candidate extraction was interrupted',
      () async {
    await _writeValidResource(
      paths.slotADir,
      title: 'PvZ2 Gardendless Active',
    );
    await File(p.join(paths.slotBDir.path, 'partial.bin'))
        .writeAsString('incomplete');
    await manifestStore.write(
      ResourceManifest.initial().copyWith(
        generation: 3,
        activeSlot: ResourceSlot.slotA,
        transactionSlot: ResourceSlot.slotB,
        transactionState: TransactionState.extracting,
        resourceStatus: ResourceStatus.ready,
      ),
    );

    final manifest = await importService.recoverStartupTransaction(
      paths: paths,
      manifestStore: manifestStore,
    );

    expect(manifest.activeSlot, ResourceSlot.slotA);
    expect(manifest.transactionState, TransactionState.idle);
    expect(
      await File(p.join(paths.slotADir.path, 'index.html')).exists(),
      isTrue,
    );
    expect(await paths.slotBDir.list().isEmpty, isTrue);
  });

  test('startup activates a candidate that already passed self-check',
      () async {
    await _writeValidResource(
      paths.slotADir,
      title: 'PvZ2 Gardendless Active | 0.11.0',
    );
    await _writeValidResource(
      paths.slotBDir,
      title: 'PvZ2 Gardendless Candidate | 0.12.0',
    );
    await manifestStore.write(
      ResourceManifest.initial().copyWith(
        generation: 8,
        activeSlot: ResourceSlot.slotA,
        transactionSlot: ResourceSlot.slotB,
        transactionState: TransactionState.readyToActivate,
        resourceStatus: ResourceStatus.ready,
      ),
    );

    final manifest = await importService.recoverStartupTransaction(
      paths: paths,
      manifestStore: manifestStore,
    );

    expect(manifest.activeSlot, ResourceSlot.slotB);
    expect(manifest.gameVersion, '0.12.0');
    expect(manifest.transactionState, TransactionState.idle);
    expect(await paths.slotADir.list().isEmpty, isTrue);
    expect(
      await File(p.join(paths.slotBDir.path, 'index.html')).exists(),
      isTrue,
    );
  });

  test('startup keeps the activated slot and finishes deferred cleanup',
      () async {
    await _writeValidResource(
      paths.slotADir,
      title: 'PvZ2 Gardendless Old | 0.11.0',
    );
    await _writeValidResource(
      paths.slotBDir,
      title: 'PvZ2 Gardendless Active | 0.12.0',
    );
    await manifestStore.write(
      ResourceManifest.initial().copyWith(
        generation: 12,
        activeSlot: ResourceSlot.slotB,
        transactionSlot: ResourceSlot.slotA,
        transactionState: TransactionState.cleaningOldSlot,
        gameVersion: '0.12.0',
        resourceStatus: ResourceStatus.ready,
      ),
    );

    final manifest = await importService.recoverStartupTransaction(
      paths: paths,
      manifestStore: manifestStore,
    );

    expect(manifest.activeSlot, ResourceSlot.slotB);
    expect(manifest.transactionState, TransactionState.idle);
    expect(await paths.slotADir.list().isEmpty, isTrue);
    expect(
      await File(p.join(paths.slotBDir.path, 'index.html')).exists(),
      isTrue,
    );
  });

  test('successful activation survives an old-slot cleanup failure', () async {
    await _writeValidResource(
      paths.slotADir,
      title: 'PvZ2 Gardendless Old | 0.11.0',
    );
    await manifestStore.write(
      ResourceManifest.initial().copyWith(
        generation: 1,
        activeSlot: ResourceSlot.slotA,
        resourceStatus: ResourceStatus.ready,
      ),
    );
    importService = ImportService(
      validator: ResourceValidator(),
      oldSlotCleaner: (_) async {
        throw const FileSystemException('slot is busy');
      },
    );
    final target = await importService.beginImport(
      paths: paths,
      manifestStore: manifestStore,
    );
    await _writeValidResource(
      target.directory,
      title: 'PvZ2 Gardendless New | 0.12.0',
    );

    final manifest = await importService.completeImport(
      paths: paths,
      manifestStore: manifestStore,
      target: target,
    );

    expect(manifest.activeSlot, ResourceSlot.slotB);
    expect(manifest.transactionState, TransactionState.cleaningOldSlot);
    expect(manifest.gameVersion, '0.12.0');
    expect(
      await File(p.join(paths.slotADir.path, 'index.html')).exists(),
      isTrue,
    );
    expect(
      await File(p.join(paths.slotBDir.path, 'index.html')).exists(),
      isTrue,
    );
  });

  test('startup migrates only the valid legacy current resource', () async {
    await _writeValidResource(
      paths.legacyCurrentDir,
      title: 'PvZ2 Gardendless Current | 0.12.0',
    );
    await _writeValidResource(
      paths.legacyPreviousDir,
      title: 'PvZ2 Gardendless Previous | 0.11.0',
    );
    await manifestStore.write(
      ResourceManifest.initial().copyWith(
        gameVersion: '0.12.0',
        resourceStatus: ResourceStatus.ready,
      ),
    );

    final manifest = await importService.recoverStartupTransaction(
      paths: paths,
      manifestStore: manifestStore,
    );

    expect(manifest.activeSlot, ResourceSlot.slotA);
    expect(manifest.gameVersion, '0.12.0');
    expect(manifest.transactionState, TransactionState.idle);
    expect(
      await File(p.join(paths.slotADir.path, 'index.html')).readAsString(),
      contains('Current'),
    );
    expect(await paths.slotBDir.list().isEmpty, isTrue);
    expect(await paths.legacyCurrentDir.exists(), isFalse);
    expect(await paths.legacyPreviousDir.exists(), isFalse);
  });

  test('failed candidate self-check keeps the active slot', () async {
    await _writeValidResource(
      paths.slotADir,
      title: 'PvZ2 Gardendless Active | 0.11.0',
    );
    await manifestStore.write(
      ResourceManifest.initial().copyWith(
        generation: 1,
        activeSlot: ResourceSlot.slotA,
        gameVersion: '0.11.0',
        autoCollectSunEnabled: true,
        resourceStatus: ResourceStatus.ready,
      ),
    );
    importService = ImportService(
      validator: ResourceValidator(),
      selfCheck: _FailingSelfCheck(),
    );
    final target = await importService.beginImport(
      paths: paths,
      manifestStore: manifestStore,
    );
    await _writeValidResource(
      target.directory,
      title: 'PvZ2 Gardendless Candidate | 0.12.0',
    );

    await expectLater(
      importService.completeImport(
        paths: paths,
        manifestStore: manifestStore,
        target: target,
      ),
      throwsA(isA<ImportFailure>()),
    );

    final manifest = await manifestStore.read();
    expect(manifest.activeSlot, ResourceSlot.slotA);
    expect(manifest.gameVersion, '0.11.0');
    expect(manifest.transactionState, TransactionState.idle);
    expect(manifest.autoCollectSunEnabled, isTrue);
    expect(
      await File(p.join(paths.slotADir.path, 'index.html')).exists(),
      isTrue,
    );
    expect(await paths.slotBDir.list().isEmpty, isTrue);
  });

  test('legacy interrupted switch migrates the valid previous resource',
      () async {
    await File(p.join(paths.legacyCurrentDir.path, 'broken.bin'))
        .writeAsString('broken');
    await _writeValidResource(
      paths.legacyPreviousDir,
      title: 'PvZ2 Gardendless Recovered | 0.11.0',
    );
    await manifestStore.write(
      ResourceManifest.initial().copyWith(
        transactionState: TransactionState.selfChecking,
      ),
    );

    final manifest = await importService.recoverStartupTransaction(
      paths: paths,
      manifestStore: manifestStore,
    );

    expect(manifest.activeSlot, ResourceSlot.slotA);
    expect(manifest.gameVersion, '0.11.0');
    expect(manifest.transactionState, TransactionState.idle);
    expect(
      await File(p.join(paths.slotADir.path, 'index.html')).readAsString(),
      contains('Recovered'),
    );
  });

  test('startup remains usable when deferred cleanup still fails', () async {
    await _writeValidResource(paths.slotADir, title: 'PvZ2 Gardendless Old');
    await _writeValidResource(
      paths.slotBDir,
      title: 'PvZ2 Gardendless Active | 0.12.0',
    );
    await manifestStore.write(
      ResourceManifest.initial().copyWith(
        generation: 15,
        activeSlot: ResourceSlot.slotB,
        transactionSlot: ResourceSlot.slotA,
        transactionState: TransactionState.cleaningOldSlot,
        gameVersion: '0.12.0',
        resourceStatus: ResourceStatus.ready,
      ),
    );
    importService = ImportService(
      validator: ResourceValidator(),
      oldSlotCleaner: (_) async {
        throw const FileSystemException('slot is still busy');
      },
    );

    final manifest = await importService.recoverStartupTransaction(
      paths: paths,
      manifestStore: manifestStore,
    );

    expect(manifest.activeSlot, ResourceSlot.slotB);
    expect(manifest.transactionState, TransactionState.cleaningOldSlot);
    expect(manifest.lastErrorCode, 'old_slot_cleanup_failed');
    expect(
      await File(p.join(paths.slotBDir.path, 'index.html')).exists(),
      isTrue,
    );
  });

  test('startup rebuilds a corrupt manifest from the last activated slot',
      () async {
    var target = await importService.beginImport(
      paths: paths,
      manifestStore: manifestStore,
    );
    await _writeValidResource(
      target.directory,
      title: 'PvZ2 Gardendless Older | 9.0.0',
    );
    await importService.completeImport(
      paths: paths,
      manifestStore: manifestStore,
      target: target,
    );

    importService = ImportService(
      validator: ResourceValidator(),
      oldSlotCleaner: (_) async {
        throw const FileSystemException('keep both slots for recovery');
      },
    );
    target = await importService.beginImport(
      paths: paths,
      manifestStore: manifestStore,
    );
    await _writeValidResource(
      target.directory,
      title: 'PvZ2 Gardendless Last Activated | 1.0.0',
    );
    await importService.completeImport(
      paths: paths,
      manifestStore: manifestStore,
      target: target,
    );
    await paths.manifestFile.writeAsString('{broken', flush: true);

    importService = ImportService(
      validator: ResourceValidator(),
    );
    final recovered = await importService.recoverStartupTransaction(
      paths: paths,
      manifestStore: manifestStore,
    );

    expect(recovered.activeSlot, ResourceSlot.slotB);
    expect(recovered.gameVersion, '1.0.0');
    expect(recovered.transactionState, TransactionState.idle);
    expect(await paths.slotADir.list().isEmpty, isTrue);
    expect(
      await File(p.join(paths.slotBDir.path, 'index.html')).readAsString(),
      contains('Last Activated'),
    );
  });

  test('startup removes invalid legacy resource remnants', () async {
    await File(p.join(paths.legacyCurrentDir.path, 'partial.bin'))
        .writeAsString('x');
    await File(p.join(paths.legacyPreviousDir.path, 'partial.bin'))
        .writeAsString('x');
    final importRemnant =
        File(p.join(paths.legacyImportDocsDir.path, 'partial.bin'));
    await importRemnant.create(recursive: true);
    await importRemnant.writeAsString('x');
    await File(p.join(paths.legacyStagingDir.path, 'partial.bin'))
        .writeAsString('x');

    final manifest = await importService.recoverStartupTransaction(
      paths: paths,
      manifestStore: manifestStore,
    );

    expect(manifest.activeSlot, isNull);
    expect(manifest.resourceStatus, ResourceStatus.missing);
    expect(await paths.legacyCurrentDir.exists(), isFalse);
    expect(await paths.legacyPreviousDir.exists(), isFalse);
    expect(await paths.legacyImportDir.exists(), isFalse);
    expect(await paths.legacyStagingDir.exists(), isFalse);
  });

  test('startup finishes legacy cleanup after migration activation', () async {
    await _writeValidResource(
      paths.slotADir,
      title: 'PvZ2 Gardendless Migrated | 0.12.0',
    );
    await _writeValidResource(
      paths.legacyCurrentDir,
      title: 'PvZ2 Gardendless Legacy | 0.12.0',
    );
    await manifestStore.write(
      ResourceManifest.initial().copyWith(
        generation: 20,
        activeSlot: ResourceSlot.slotA,
        transactionState: TransactionState.migrating,
        gameVersion: '0.12.0',
        resourceStatus: ResourceStatus.ready,
      ),
    );

    final manifest = await importService.recoverStartupTransaction(
      paths: paths,
      manifestStore: manifestStore,
    );

    expect(manifest.activeSlot, ResourceSlot.slotA);
    expect(manifest.transactionState, TransactionState.idle);
    expect(await paths.legacyCurrentDir.exists(), isFalse);
    expect(
      await File(p.join(paths.slotADir.path, 'index.html')).exists(),
      isTrue,
    );
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });
}

Future<void> _writeValidResource(
  Directory root, {
  String title = 'PvZ2 Gardendless',
  bool includeCcJs = true,
}) async {
  await Directory(p.join(root.path, 'assets')).create(recursive: true);
  await Directory(p.join(root.path, 'cocos-js')).create(recursive: true);
  await Directory(p.join(root.path, 'src')).create(recursive: true);
  await File(p.join(root.path, 'index.html')).writeAsString(
    '<html><head><title>$title</title></head><body>play.pvzge.com</body></html>',
  );
  await File(p.join(root.path, 'src', 'settings.json'))
      .writeAsString('{"platform":"web-mobile"}');
  await File(p.join(root.path, 'src', 'import-map.json')).writeAsString('{}');
  if (includeCcJs) {
    await File(p.join(root.path, 'cocos-js', 'cc.js'))
        .writeAsString('console.log("cc");');
  }
}

class _FailingSelfCheck implements ResourceSelfCheck {
  @override
  Future<void> validate(Directory root) async {
    throw StateError('self check failed');
  }
}
