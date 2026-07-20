import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'game_update_check_service.dart';
import 'manifest_store.dart';
import 'resource_self_check.dart';
import 'resource_validator.dart';

class ImportTarget {
  const ImportTarget({required this.slot, required this.directory});

  final ResourceSlot slot;
  final Directory directory;
}

typedef OldSlotCleaner = Future<void> Function(Directory directory);

class ImportService {
  ImportService({
    required ResourceValidator validator,
    ResourceSelfCheck? selfCheck,
    GameUpdateCheckService? gameUpdateCheckService,
    OldSlotCleaner? oldSlotCleaner,
  })  : _validator = validator,
        _selfCheck = selfCheck ?? FileResourceSelfCheck(),
        _gameUpdateCheckService =
            gameUpdateCheckService ?? GameUpdateCheckService(),
        _oldSlotCleaner = oldSlotCleaner;

  final ResourceValidator _validator;
  final ResourceSelfCheck _selfCheck;
  final GameUpdateCheckService _gameUpdateCheckService;
  final OldSlotCleaner? _oldSlotCleaner;

  Directory? activeDirectory(AppPaths paths, ResourceManifest manifest) {
    final activeSlot = manifest.activeSlot;
    return activeSlot == null ? null : paths.directoryFor(activeSlot);
  }

  Future<ImportTarget> beginImport({
    required AppPaths paths,
    required ManifestStore manifestStore,
  }) async {
    final manifest = await manifestStore.read();
    if (manifest.transactionState != TransactionState.idle) {
      throw ImportFailure('import_busy', '已有资源导入事务正在处理中');
    }

    final slot = manifest.activeSlot?.other ?? ResourceSlot.slotA;
    final directory = paths.directoryFor(slot);
    await _resetDirectory(directory);
    await manifestStore.write(
      manifest.copyWith(
        generation: manifest.generation + 1,
        transactionSlot: slot,
        transactionState: TransactionState.extracting,
        clearError: true,
      ),
    );
    return ImportTarget(slot: slot, directory: directory);
  }

  Future<ResourceManifest> abortImport({
    required AppPaths paths,
    required ManifestStore manifestStore,
  }) async {
    final manifest = await manifestStore.read();
    final candidateSlot = manifest.transactionSlot;
    if (candidateSlot != null && candidateSlot != manifest.activeSlot) {
      await _resetDirectory(paths.directoryFor(candidateSlot));
    }
    final aborted = manifest.copyWith(
      generation: manifest.generation + 1,
      transactionState: TransactionState.idle,
      clearTransactionSlot: true,
    );
    await manifestStore.write(aborted);
    return aborted;
  }

  Future<ResourceManifest> completeImport({
    required AppPaths paths,
    required ManifestStore manifestStore,
    required ImportTarget target,
    ImportProgressCallback? onProgress,
  }) async {
    var manifest = await manifestStore.read();
    var activated = false;
    final expectedDirectory = paths.directoryFor(target.slot);
    if (manifest.transactionSlot != target.slot ||
        !p.equals(
          p.normalize(target.directory.absolute.path),
          p.normalize(expectedDirectory.absolute.path),
        )) {
      throw ImportFailure('invalid_import_target', '导入目标不是当前空闲槽');
    }

    void report(ImportProgress progress) => onProgress?.call(progress);

    try {
      manifest = manifest.copyWith(
        generation: manifest.generation + 1,
        transactionState: TransactionState.validating,
      );
      await manifestStore.write(manifest);
      report(
        const ImportProgress(phase: ImportPhase.validating, message: '正在校验资源'),
      );

      final validation = await _validator.validate(target.directory);
      if (!validation.isValid) {
        throw ImportFailure(
          validation.errorCode ?? 'validation_failed',
          validation.errorMessage ?? '导入资源校验失败',
        );
      }
      final stats = await _validator.scanStats(
        target.directory,
        detectedTitle: validation.detectedTitle,
        buildProfile: validation.buildProfile,
        gpNextVersion: validation.gpNextVersion,
        gpNextCompatibilityError: validation.gpNextCompatibilityError,
      );

      manifest = manifest.copyWith(
        generation: manifest.generation + 1,
        transactionState: TransactionState.selfChecking,
      );
      await manifestStore.write(manifest);
      report(
        ImportProgress(
          phase: ImportPhase.selfChecking,
          copiedFiles: stats.fileCount,
          copiedBytes: stats.totalBytes,
          totalFiles: stats.fileCount,
          totalBytes: stats.totalBytes,
          message: '正在检查原生宿主入口资源',
        ),
      );
      await _selfCheck.validate(target.directory);

      final now = DateTime.now();
      final gameVersion = await _gameUpdateCheckService.loadCurrentVersion(
        target.directory,
      );
      manifest = manifest.copyWith(
        generation: manifest.generation + 1,
        transactionState: TransactionState.readyToActivate,
      );
      await manifestStore.write(manifest);

      final oldSlot = manifest.activeSlot;
      final activationGeneration = manifest.generation + 1;
      await _writeSlotMetadata(
        directory: target.directory,
        generation: activationGeneration,
        gameVersion: gameVersion,
        importedAt: now,
        lastSelfCheckAt: now,
      );
      manifest = ResourceManifest.initial().copyWith(
        generation: activationGeneration,
        activeSlot: target.slot,
        transactionSlot: oldSlot,
        transactionState: TransactionState.cleaningOldSlot,
        gameVersion: gameVersion,
        lastImportAt: now,
        fileCount: stats.fileCount,
        totalBytes: stats.totalBytes,
        detectedTitle: stats.detectedTitle,
        buildProfile: stats.buildProfile,
        gpNextVersion: stats.gpNextVersion,
        gpNextCompatibilityError: stats.gpNextCompatibilityError,
        clearGpNextVersion: stats.gpNextVersion == null,
        clearGpNextCompatibilityError: stats.gpNextCompatibilityError == null,
        resourceStatus: ResourceStatus.ready,
        lastSelfCheckAt: now,
        clearError: true,
      );
      await manifestStore.write(manifest);
      activated = true;

      if (oldSlot != null) {
        await _cleanOldSlot(paths.directoryFor(oldSlot));
      }
      manifest = manifest.copyWith(
        generation: manifest.generation + 1,
        transactionState: TransactionState.idle,
        clearTransactionSlot: true,
        clearError: true,
      );
      await manifestStore.write(manifest);
      report(
        ImportProgress(
          phase: ImportPhase.completed,
          copiedFiles: stats.fileCount,
          copiedBytes: stats.totalBytes,
          totalFiles: stats.fileCount,
          totalBytes: stats.totalBytes,
          message: '导入成功',
        ),
      );
      return manifest;
    } catch (error) {
      if (activated) {
        final current = await manifestStore.read();
        final pendingCleanup = current.copyWith(
          generation: current.generation + 1,
          lastErrorCode: 'old_slot_cleanup_failed',
          lastErrorMessage: error.toString(),
        );
        await manifestStore.write(pendingCleanup);
        report(
          const ImportProgress(
            phase: ImportPhase.completed,
            message: '导入成功，旧槽将在下次启动清理',
          ),
        );
        return pendingCleanup;
      }
      await _resetDirectory(target.directory);
      final failure = error is ImportFailure
          ? error
          : ImportFailure('import_failed', error.toString());
      final current = await manifestStore.read();
      final failed = current.copyWith(
        generation: current.generation + 1,
        resourceStatus: current.activeSlot == null
            ? ResourceStatus.missing
            : ResourceStatus.ready,
        transactionState: TransactionState.idle,
        clearTransactionSlot: true,
        lastErrorCode: failure.code,
        lastErrorMessage: failure.message,
      );
      await manifestStore.write(failed);
      report(
        ImportProgress(phase: ImportPhase.failed, message: failure.message),
      );
      throw failure;
    }
  }

  Future<ResourceManifest> recoverStartupTransaction({
    required AppPaths paths,
    required ManifestStore manifestStore,
  }) async {
    var manifest = await manifestStore.read();
    if (manifest.activeSlot == null &&
        manifest.transactionState == TransactionState.idle) {
      final recovered = await _recoverFromSlotMetadata(
        paths: paths,
        manifestStore: manifestStore,
        manifest: manifest,
      );
      if (recovered.activeSlot != null) {
        manifest = recovered;
      }
    }
    final isLegacyTransaction = manifest.activeSlot == null &&
        manifest.transactionSlot == null &&
        manifest.transactionState == TransactionState.selfChecking;
    if (isLegacyTransaction) {
      manifest = manifest.copyWith(
        generation: manifest.generation + 1,
        transactionState: TransactionState.idle,
      );
      await manifestStore.write(manifest);
    }
    if (manifest.transactionState == TransactionState.migrating) {
      if (manifest.activeSlot != null) {
        await _deleteLegacyDirectories(paths);
      } else {
        final targetSlot = manifest.transactionSlot;
        if (targetSlot != null) {
          await _resetDirectory(paths.directoryFor(targetSlot));
        }
      }
      manifest = manifest.copyWith(
        generation: manifest.generation + 1,
        transactionState: TransactionState.idle,
        clearTransactionSlot: true,
      );
      await manifestStore.write(manifest);
    }
    if (manifest.activeSlot == null &&
        manifest.transactionState == TransactionState.idle) {
      manifest = await _migrateLegacyResources(
        paths: paths,
        manifestStore: manifestStore,
        manifest: manifest,
      );
    }
    if (manifest.transactionState == TransactionState.extracting ||
        manifest.transactionState == TransactionState.validating ||
        manifest.transactionState == TransactionState.selfChecking) {
      final candidateSlot = manifest.transactionSlot;
      if (candidateSlot != null && candidateSlot != manifest.activeSlot) {
        await _resetDirectory(paths.directoryFor(candidateSlot));
      }
      manifest = manifest.copyWith(
        generation: manifest.generation + 1,
        transactionState: TransactionState.idle,
        clearTransactionSlot: true,
      );
      await manifestStore.write(manifest);
      return manifest;
    }

    if (manifest.transactionState == TransactionState.readyToActivate) {
      final candidateSlot = manifest.transactionSlot;
      if (candidateSlot == null) {
        return manifest;
      }
      final candidate = paths.directoryFor(candidateSlot);
      final validation = await _validator.validate(candidate);
      if (!validation.isValid) {
        await _resetDirectory(candidate);
        manifest = manifest.copyWith(
          generation: manifest.generation + 1,
          transactionState: TransactionState.idle,
          clearTransactionSlot: true,
          lastErrorCode: 'candidate_recovery_failed',
          lastErrorMessage: validation.errorMessage ?? '候选槽恢复校验失败',
        );
        await manifestStore.write(manifest);
        return manifest;
      }

      final stats = await _validator.scanStats(
        candidate,
        detectedTitle: validation.detectedTitle,
        buildProfile: validation.buildProfile,
        gpNextVersion: validation.gpNextVersion,
        gpNextCompatibilityError: validation.gpNextCompatibilityError,
      );
      final gameVersion = await _gameUpdateCheckService.loadCurrentVersion(
        candidate,
      );
      final oldSlot = manifest.activeSlot;
      final now = DateTime.now();
      final activationGeneration = manifest.generation + 1;
      await _writeSlotMetadata(
        directory: candidate,
        generation: activationGeneration,
        gameVersion: gameVersion,
        importedAt: now,
        lastSelfCheckAt: now,
      );
      manifest = ResourceManifest.initial().copyWith(
        generation: activationGeneration,
        activeSlot: candidateSlot,
        transactionSlot: oldSlot,
        transactionState: TransactionState.cleaningOldSlot,
        gameVersion: gameVersion,
        lastImportAt: now,
        fileCount: stats.fileCount,
        totalBytes: stats.totalBytes,
        detectedTitle: stats.detectedTitle,
        buildProfile: stats.buildProfile,
        gpNextVersion: stats.gpNextVersion,
        gpNextCompatibilityError: stats.gpNextCompatibilityError,
        clearGpNextVersion: stats.gpNextVersion == null,
        clearGpNextCompatibilityError: stats.gpNextCompatibilityError == null,
        resourceStatus: ResourceStatus.ready,
        lastSelfCheckAt: now,
        clearError: true,
      );
      await manifestStore.write(manifest);
      return _completeDeferredCleanup(
        paths: paths,
        manifestStore: manifestStore,
        manifest: manifest,
      );
    }

    if (manifest.transactionState == TransactionState.cleaningOldSlot) {
      return _completeDeferredCleanup(
        paths: paths,
        manifestStore: manifestStore,
        manifest: manifest,
      );
    }

    return manifest;
  }

  Future<ResourceManifest> _recoverFromSlotMetadata({
    required AppPaths paths,
    required ManifestStore manifestStore,
    required ResourceManifest manifest,
  }) async {
    final candidates = <({
      ResourceSlot slot,
      Directory directory,
      ResourceValidationResult validation,
      _SlotMetadata? metadata,
    })>[];
    for (final slot in ResourceSlot.values) {
      final directory = paths.directoryFor(slot);
      final validation = await _validator.validate(directory);
      if (validation.isValid) {
        candidates.add((
          slot: slot,
          directory: directory,
          validation: validation,
          metadata: await _readSlotMetadata(directory),
        ));
      }
    }
    if (candidates.isEmpty) {
      return manifest;
    }
    candidates.sort(
      (left, right) => (right.metadata?.generation ?? 0).compareTo(
        left.metadata?.generation ?? 0,
      ),
    );
    final selected = candidates.first;
    final stats = await _validator.scanStats(
      selected.directory,
      detectedTitle: selected.validation.detectedTitle,
      buildProfile: selected.validation.buildProfile,
      gpNextVersion: selected.validation.gpNextVersion,
      gpNextCompatibilityError: selected.validation.gpNextCompatibilityError,
    );
    final gameVersion = await _gameUpdateCheckService.loadCurrentVersion(
      selected.directory,
    );
    final generation = [
      manifest.generation + 1,
      selected.metadata?.generation ?? 0,
    ].reduce((left, right) => left > right ? left : right);
    final now = DateTime.now();
    await _writeSlotMetadata(
      directory: selected.directory,
      generation: generation,
      gameVersion: gameVersion,
      importedAt: selected.metadata?.importedAt ?? now,
      lastSelfCheckAt: selected.metadata?.lastSelfCheckAt,
    );
    ({
      ResourceSlot slot,
      Directory directory,
      ResourceValidationResult validation,
      _SlotMetadata? metadata,
    })? otherCandidate;
    for (final candidate in candidates) {
      if (candidate.slot != selected.slot) {
        otherCandidate = candidate;
        break;
      }
    }
    final recovered = ResourceManifest.initial().copyWith(
      generation: generation,
      activeSlot: selected.slot,
      transactionSlot: otherCandidate?.slot,
      transactionState: otherCandidate == null
          ? TransactionState.idle
          : TransactionState.cleaningOldSlot,
      gameVersion: gameVersion,
      lastImportAt: selected.metadata?.importedAt ?? now,
      fileCount: stats.fileCount,
      totalBytes: stats.totalBytes,
      detectedTitle: stats.detectedTitle,
      buildProfile: stats.buildProfile,
      gpNextVersion: stats.gpNextVersion,
      gpNextCompatibilityError: stats.gpNextCompatibilityError,
      clearGpNextVersion: stats.gpNextVersion == null,
      clearGpNextCompatibilityError: stats.gpNextCompatibilityError == null,
      resourceStatus: ResourceStatus.ready,
      lastSelfCheckAt: selected.metadata?.lastSelfCheckAt,
      clearError: true,
    );
    await manifestStore.write(recovered);
    if (otherCandidate == null) {
      return recovered;
    }
    return _completeDeferredCleanup(
      paths: paths,
      manifestStore: manifestStore,
      manifest: recovered,
    );
  }

  Future<ResourceManifest> _completeDeferredCleanup({
    required AppPaths paths,
    required ManifestStore manifestStore,
    required ResourceManifest manifest,
  }) async {
    try {
      final oldSlot = manifest.transactionSlot;
      if (oldSlot != null && oldSlot != manifest.activeSlot) {
        await _cleanOldSlot(paths.directoryFor(oldSlot));
      }
      final completed = manifest.copyWith(
        generation: manifest.generation + 1,
        transactionState: TransactionState.idle,
        clearTransactionSlot: true,
        clearError: true,
      );
      await manifestStore.write(completed);
      return completed;
    } catch (error) {
      final pending = manifest.copyWith(
        generation: manifest.generation + 1,
        lastErrorCode: 'old_slot_cleanup_failed',
        lastErrorMessage: error.toString(),
      );
      await manifestStore.write(pending);
      return pending;
    }
  }

  Future<ResourceManifest> _migrateLegacyResources({
    required AppPaths paths,
    required ManifestStore manifestStore,
    required ResourceManifest manifest,
  }) async {
    final currentValidation = await _validator.validate(paths.legacyCurrentDir);
    final previousValidation = currentValidation.isValid
        ? null
        : await _validator.validate(paths.legacyPreviousDir);
    final source = currentValidation.isValid
        ? paths.legacyCurrentDir
        : previousValidation?.isValid == true
            ? paths.legacyPreviousDir
            : null;
    final sourceValidation = currentValidation.isValid
        ? currentValidation
        : previousValidation?.isValid == true
            ? previousValidation!
            : null;
    if (source == null || sourceValidation == null) {
      await _deleteLegacyDirectories(paths);
      return manifest;
    }

    final targetSlot = ResourceSlot.slotA;
    final target = paths.directoryFor(targetSlot);
    await _resetDirectory(target);
    manifest = manifest.copyWith(
      generation: manifest.generation + 1,
      transactionSlot: targetSlot,
      transactionState: TransactionState.migrating,
      clearError: true,
    );
    await manifestStore.write(manifest);

    final unusedLegacy = p.equals(source.path, paths.legacyCurrentDir.path)
        ? paths.legacyPreviousDir
        : paths.legacyCurrentDir;
    await _deleteDirectory(unusedLegacy);
    await _deleteDirectory(paths.legacyImportDir);
    await _deleteDirectory(paths.legacyStagingDir);
    await _copyDirectoryContents(source, target);
    final migratedValidation = await _validator.validate(target);
    if (!migratedValidation.isValid) {
      throw ImportFailure('legacy_migration_failed', '旧资源迁移后的校验失败');
    }
    final stats = await _validator.scanStats(
      target,
      detectedTitle: migratedValidation.detectedTitle,
      buildProfile: migratedValidation.buildProfile,
      gpNextVersion: migratedValidation.gpNextVersion,
      gpNextCompatibilityError: migratedValidation.gpNextCompatibilityError,
    );
    final gameVersion = await _gameUpdateCheckService.loadCurrentVersion(
      target,
    );
    final now = DateTime.now();
    final activationGeneration = manifest.generation + 1;
    await _writeSlotMetadata(
      directory: target,
      generation: activationGeneration,
      gameVersion: gameVersion,
      importedAt: manifest.lastImportAt ?? now,
      lastSelfCheckAt: manifest.lastSelfCheckAt,
    );
    manifest = ResourceManifest.initial().copyWith(
      generation: activationGeneration,
      activeSlot: targetSlot,
      gameVersion: gameVersion,
      lastImportAt: manifest.lastImportAt ?? now,
      fileCount: stats.fileCount,
      totalBytes: stats.totalBytes,
      detectedTitle: stats.detectedTitle,
      buildProfile: stats.buildProfile,
      gpNextVersion: stats.gpNextVersion,
      gpNextCompatibilityError: stats.gpNextCompatibilityError,
      clearGpNextVersion: stats.gpNextVersion == null,
      clearGpNextCompatibilityError: stats.gpNextCompatibilityError == null,
      resourceStatus: ResourceStatus.ready,
      lastSelfCheckAt: manifest.lastSelfCheckAt,
      transactionState: TransactionState.migrating,
      clearError: true,
    );
    await manifestStore.write(manifest);
    await _deleteLegacyDirectories(paths);
    manifest = manifest.copyWith(
      generation: manifest.generation + 1,
      transactionState: TransactionState.idle,
      clearTransactionSlot: true,
    );
    await manifestStore.write(manifest);
    return manifest;
  }

  Future<void> _deleteLegacyDirectories(AppPaths paths) async {
    await _deleteDirectory(paths.legacyCurrentDir);
    await _deleteDirectory(paths.legacyPreviousDir);
    await _deleteDirectory(paths.legacyImportDir);
    await _deleteDirectory(paths.legacyStagingDir);
  }

  Future<void> _copyDirectoryContents(
    Directory source,
    Directory target,
  ) async {
    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: source.path);
      final targetPath = p.join(target.path, relative);
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        await File(targetPath).parent.create(recursive: true);
        await entity.copy(targetPath);
      }
    }
  }

  Future<void> _resetDirectory(Directory directory) async {
    await _deleteDirectory(directory);
    await directory.create(recursive: true);
  }

  Future<void> _deleteDirectory(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> _cleanOldSlot(Directory directory) {
    final cleaner = _oldSlotCleaner;
    return cleaner == null ? _resetDirectory(directory) : cleaner(directory);
  }

  File _slotMetadataFile(Directory directory) {
    return File(p.join(directory.path, '.slot-metadata.json'));
  }

  Future<void> _writeSlotMetadata({
    required Directory directory,
    required int generation,
    required String? gameVersion,
    required DateTime importedAt,
    required DateTime? lastSelfCheckAt,
  }) async {
    final file = _slotMetadataFile(directory);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      '${jsonEncode({
            'generation': generation,
            'gameVersion': gameVersion,
            'importedAt': importedAt.toUtc().toIso8601String(),
            'lastSelfCheckAt': lastSelfCheckAt?.toUtc().toIso8601String()
          })}\n',
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<_SlotMetadata?> _readSlotMetadata(Directory directory) async {
    try {
      final decoded =
          jsonDecode(await _slotMetadataFile(directory).readAsString())
              as Map<String, dynamic>;
      final generation = decoded['generation'];
      final importedAt = DateTime.tryParse(
        decoded['importedAt'] as String? ?? '',
      );
      if (generation is! int || importedAt == null) {
        return null;
      }
      return _SlotMetadata(
        generation: generation,
        importedAt: importedAt,
        lastSelfCheckAt: DateTime.tryParse(
          decoded['lastSelfCheckAt'] as String? ?? '',
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

class _SlotMetadata {
  const _SlotMetadata({
    required this.generation,
    required this.importedAt,
    required this.lastSelfCheckAt,
  });

  final int generation;
  final DateTime importedAt;
  final DateTime? lastSelfCheckAt;
}

class ImportFailure implements Exception {
  ImportFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}
