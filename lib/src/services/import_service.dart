import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'local_game_server.dart';
import 'manifest_store.dart';
import 'resource_validator.dart';

typedef ImportProgressCallback = void Function(ImportProgress progress);

class ImportService {
  ImportService({
    required ResourceValidator validator,
    required LocalGameServer server,
  })  : _validator = validator,
        _server = server;

  final ResourceValidator _validator;
  final LocalGameServer _server;

  Future<ResourceManifest> importResources({
    required AppPaths paths,
    required ManifestStore manifestStore,
    ImportProgressCallback? onProgress,
  }) async {
    var manifest = await manifestStore.read();

    void report(ImportProgress progress) => onProgress?.call(progress);

    try {
      manifest = manifest.copyWith(
        transactionState: TransactionState.staging,
        resourceStatus: ResourceStatus.invalid,
        clearError: true,
      );
      await manifestStore.write(manifest);
      report(const ImportProgress(phase: ImportPhase.validating, message: '正在校验 import/docs'));

      await _resetDirectory(paths.stagingDir);
      final validation = await _validator.validate(paths.importDocsDir);
      if (!validation.isValid) {
        throw ImportFailure(
          validation.errorCode ?? 'validation_failed',
          validation.errorMessage ?? '导入资源校验失败',
        );
      }

      report(const ImportProgress(phase: ImportPhase.scanning, message: '正在统计资源'));
      final stats = await _validator.scanStats(
        paths.importDocsDir,
        detectedTitle: validation.detectedTitle,
      );

      report(ImportProgress(
        phase: ImportPhase.copying,
        totalFiles: stats.fileCount,
        totalBytes: stats.totalBytes,
        message: '正在复制到 staging',
      ));
      await _copyDirectory(
        paths.importDocsDir,
        paths.stagingDir,
        totalFiles: stats.fileCount,
        totalBytes: stats.totalBytes,
        onProgress: report,
      );

      manifest = manifest.copyWith(transactionState: TransactionState.switching);
      await manifestStore.write(manifest);
      report(ImportProgress(
        phase: ImportPhase.switching,
        totalFiles: stats.fileCount,
        totalBytes: stats.totalBytes,
        copiedFiles: stats.fileCount,
        copiedBytes: stats.totalBytes,
        message: '正在切换 current',
      ));

      await _deleteDirectory(paths.previousDir);
      if (await _hasEntries(paths.currentDir)) {
        await paths.currentDir.rename(paths.previousDir.path);
      } else {
        await _deleteDirectory(paths.currentDir);
      }
      await paths.stagingDir.rename(paths.currentDir.path);
      await paths.stagingDir.create(recursive: true);

      manifest = manifest.copyWith(transactionState: TransactionState.selfChecking);
      await manifestStore.write(manifest);
      report(ImportProgress(
        phase: ImportPhase.selfChecking,
        totalFiles: stats.fileCount,
        totalBytes: stats.totalBytes,
        copiedFiles: stats.fileCount,
        copiedBytes: stats.totalBytes,
        message: '正在通过本地 server 自检',
      ));

      await _server.selfCheck(root: paths.currentDir);
      await _server.stop();

      manifest = ResourceManifest.initial().copyWith(
        lastImportAt: DateTime.now(),
        fileCount: stats.fileCount,
        totalBytes: stats.totalBytes,
        detectedTitle: stats.detectedTitle,
        resourceStatus: ResourceStatus.ready,
        lastSelfCheckAt: DateTime.now(),
        transactionState: TransactionState.idle,
        clearError: true,
      );
      await manifestStore.write(manifest);
      report(ImportProgress(
        phase: ImportPhase.completed,
        totalFiles: stats.fileCount,
        totalBytes: stats.totalBytes,
        copiedFiles: stats.fileCount,
        copiedBytes: stats.totalBytes,
        message: '导入成功，可自行删除 import/docs 节省空间',
      ));
      return manifest;
    } catch (error) {
      await _rollback(paths);
      final failure = error is ImportFailure
          ? error
          : ImportFailure('import_failed', error.toString());
      manifest = (await manifestStore.read()).copyWith(
        resourceStatus: ResourceStatus.invalid,
        lastErrorCode: failure.code,
        lastErrorMessage: failure.message,
        transactionState: TransactionState.idle,
      );
      await manifestStore.write(manifest);
      report(ImportProgress(
        phase: ImportPhase.failed,
        message: failure.message,
      ));
      throw failure;
    } finally {
      await _resetDirectory(paths.stagingDir);
    }
  }

  Future<ResourceManifest> recoverStartupTransaction({
    required AppPaths paths,
    required ManifestStore manifestStore,
  }) async {
    var manifest = await manifestStore.read();
    if (manifest.transactionState == TransactionState.staging) {
      await _resetDirectory(paths.stagingDir);
      manifest = manifest.copyWith(transactionState: TransactionState.idle);
      await manifestStore.write(manifest);
      return manifest;
    }

    if (manifest.transactionState == TransactionState.switching ||
        manifest.transactionState == TransactionState.selfChecking) {
      final currentValidation = await _validator.validate(paths.currentDir);
      if (currentValidation.isValid) {
        manifest = manifest.copyWith(
          resourceStatus: ResourceStatus.ready,
          detectedTitle: currentValidation.detectedTitle,
          transactionState: TransactionState.idle,
          clearError: true,
        );
        await manifestStore.write(manifest);
        return manifest;
      }

      final previousValidation = await _validator.validate(paths.previousDir);
      if (previousValidation.isValid) {
        await _deleteDirectory(paths.currentDir);
        await paths.previousDir.rename(paths.currentDir.path);
        await paths.previousDir.create(recursive: true);
        manifest = manifest.copyWith(
          resourceStatus: ResourceStatus.ready,
          detectedTitle: previousValidation.detectedTitle,
          transactionState: TransactionState.idle,
          clearError: true,
        );
        await manifestStore.write(manifest);
        return manifest;
      }

      await _deleteDirectory(paths.currentDir);
      await paths.currentDir.create(recursive: true);
      manifest = manifest.copyWith(
        resourceStatus: ResourceStatus.missing,
        transactionState: TransactionState.idle,
        lastErrorCode: 'startup_recovery_failed',
        lastErrorMessage: 'current 和 previous 均无有效资源',
      );
      await manifestStore.write(manifest);
    }

    return manifest;
  }

  Future<void> _rollback(AppPaths paths) async {
    await _server.stop();
    await _deleteDirectory(paths.currentDir);
    if (await _hasEntries(paths.previousDir)) {
      await paths.previousDir.rename(paths.currentDir.path);
      await paths.previousDir.create(recursive: true);
    } else {
      await paths.currentDir.create(recursive: true);
    }
  }

  Future<void> _copyDirectory(
    Directory source,
    Directory target, {
    required int totalFiles,
    required int totalBytes,
    required ImportProgressCallback onProgress,
  }) async {
    var copiedFiles = 0;
    var copiedBytes = 0;
    await target.create(recursive: true);

    await for (final entity in source.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: source.path);
      final targetPath = p.join(target.path, relative);
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        await File(targetPath).parent.create(recursive: true);
        await entity.copy(targetPath);
        copiedFiles++;
        copiedBytes += await entity.length();
        onProgress(ImportProgress(
          phase: ImportPhase.copying,
          copiedFiles: copiedFiles,
          copiedBytes: copiedBytes,
          totalFiles: totalFiles,
          totalBytes: totalBytes,
          message: '正在复制资源',
        ));
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

  Future<bool> _hasEntries(Directory directory) async {
    if (!await directory.exists()) {
      return false;
    }
    return !(await directory.list(followLinks: false).isEmpty);
  }
}

class ImportFailure implements Exception {
  ImportFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}
