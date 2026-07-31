import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'app_logger.dart';

class ManifestStore {
  ManifestStore(this._file, {AppLogger? logger})
      : _logger = logger ?? AppLogger.instance;

  final File _file;
  final AppLogger _logger;

  File get _temporaryFile => File('${_file.path}.tmp');

  Future<ResourceManifest> read() async {
    final operation = _logger.beginOperation(
      'manifest.storage',
      'Manifest read',
      data: <String, Object?>{'path': _file.path},
    );
    try {
      final mainExists = await _file.exists();
      final temporaryExists = await _temporaryFile.exists();
      if (!mainExists && !temporaryExists) {
        operation.complete(
          message: 'Manifest does not exist; initial state selected',
          data: const <String, Object?>{
            'mainExists': false,
            'temporaryExists': false,
            'generation': 0,
          },
        );
        return ResourceManifest.initial();
      }

      final main = mainExists
          ? await _tryRead(_file, temporary: false)
          : null;
      final temporary = temporaryExists
          ? await _tryRead(_temporaryFile, temporary: true)
          : null;
      final useTemporary = temporary != null &&
          (main == null || temporary.generation > main.generation);
      final selected = useTemporary ? temporary : main;
      if (selected == null) {
        final invalid = ResourceManifest.initial().copyWith(
          resourceStatus: ResourceStatus.invalid,
          lastErrorCode: 'manifest_unreadable',
          lastErrorMessage: 'manifest.json 无法读取或不是有效 JSON',
        );
        operation.fail(
          const FormatException('No readable manifest candidate'),
          StackTrace.current,
          code: 'manifest_unreadable',
          data: <String, Object?>{
            'mainExists': mainExists,
            'temporaryExists': temporaryExists,
          },
        );
        return invalid;
      }

      if (useTemporary) {
        try {
          if (await _file.exists()) {
            await _file.delete();
          }
          await _temporaryFile.rename(_file.path);
          _logger.warning(
            'manifest.storage',
            'Manifest recovered from newer temporary file',
            operationId: operation.operationId,
            code: 'manifest_recovered_from_temp',
            data: <String, Object?>{
              'generation': selected.generation,
              'path': _file.path,
            },
          );
        } catch (error, stackTrace) {
          _logger.error(
            'manifest.storage',
            'Newer temporary manifest could not be promoted',
            operationId: operation.operationId,
            code: 'manifest_temp_promotion_failed',
            error: error,
            stackTrace: stackTrace,
            data: <String, Object?>{
              'generation': selected.generation,
              'temporaryPath': _temporaryFile.path,
            },
          );
          rethrow;
        }
      } else if (temporaryExists) {
        try {
          await _temporaryFile.delete();
          _logger.warning(
            'manifest.storage',
            'Stale manifest temporary file removed',
            operationId: operation.operationId,
            code: 'manifest_stale_temp_removed',
            data: <String, Object?>{'path': _temporaryFile.path},
          );
        } catch (error, stackTrace) {
          _logger.warning(
            'manifest.storage',
            'Unable to remove stale manifest temporary file',
            operationId: operation.operationId,
            code: 'manifest_stale_temp_delete_failed',
            error: error,
            stackTrace: stackTrace,
            data: <String, Object?>{'path': _temporaryFile.path},
          );
        }
      }
      operation.complete(
        data: <String, Object?>{
          'generation': selected.generation,
          'activeSlot': selected.activeSlot?.name,
          'transactionSlot': selected.transactionSlot?.name,
          'transactionState': selected.transactionState.name,
          'resourceStatus': selected.resourceStatus.name,
          'selectedTemporary': useTemporary,
        },
      );
      return selected;
    } catch (error, stackTrace) {
      operation.fail(error, stackTrace, code: 'manifest_read_failed');
      rethrow;
    }
  }

  Future<void> write(ResourceManifest manifest) async {
    final operation = _logger.beginOperation(
      'manifest.storage',
      'Manifest write',
      data: <String, Object?>{
        'path': _file.path,
        'generation': manifest.generation,
        'activeSlot': manifest.activeSlot?.name,
        'transactionSlot': manifest.transactionSlot?.name,
        'transactionState': manifest.transactionState.name,
        'resourceStatus': manifest.resourceStatus.name,
        'lastErrorCode': manifest.lastErrorCode,
      },
    );
    try {
      await _file.parent.create(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      await _temporaryFile.writeAsString(
        '${encoder.convert(manifest.toJson())}\n',
        flush: true,
      );
      if (await _file.exists()) {
        await _file.delete();
      }
      await _temporaryFile.rename(_file.path);
      operation.complete();
    } catch (error, stackTrace) {
      operation.fail(error, stackTrace, code: 'manifest_write_failed');
      rethrow;
    }
  }

  Future<ResourceManifest?> _tryRead(
    File file, {
    required bool temporary,
  }) async {
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final manifest = ResourceManifest(
        schemaVersion: ResourceManifest.initial().schemaVersion,
        generation: json['generation'] as int? ?? 0,
        activeSlot: _parseResourceSlot(json['activeSlot']),
        transactionSlot: _parseResourceSlot(
          (json['transaction'] as Map?)?['slot'],
        ),
        gameVersion: json['gameVersion'] as String?,
        lastImportAt: _parseDate(json['lastImportAt']),
        fileCount: json['fileCount'] as int? ?? 0,
        totalBytes: json['totalBytes'] as int? ?? 0,
        detectedTitle: json['detectedTitle'] as String?,
        buildProfile: _parseBuildProfile(json['buildProfile']),
        gpNextVersion: json['gpNextVersion'] as String?,
        gpNextCompatibilityError: json['gpNextCompatibilityError'] as String?,
        resourceStatus: _parseResourceStatus(json['resourceStatus']),
        lastSelfCheckAt: _parseDate(json['lastSelfCheckAt']),
        lastErrorCode: json['lastErrorCode'] as String?,
        lastErrorMessage: json['lastErrorMessage'] as String?,
        transactionState: _parseTransactionState(
          (json['transaction'] as Map?)?['state'],
        ),
      );
      _logger.debug(
        'manifest.storage',
        'Manifest candidate parsed',
        data: <String, Object?>{
          'path': file.path,
          'temporary': temporary,
          'generation': manifest.generation,
          'transactionState': manifest.transactionState.name,
        },
      );
      return manifest;
    } catch (error, stackTrace) {
      _logger.warning(
        'manifest.storage',
        'Manifest candidate was unreadable',
        code: temporary
            ? 'manifest_temp_unreadable'
            : 'manifest_main_unreadable',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{
          'path': file.path,
          'temporary': temporary,
        },
      );
      return null;
    }
  }

  DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  ResourceStatus _parseResourceStatus(Object? value) {
    return ResourceStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => ResourceStatus.missing,
    );
  }

  ResourceBuildProfile _parseBuildProfile(Object? value) {
    return ResourceBuildProfile.values.firstWhere(
      (profile) => profile.name == value,
      orElse: () => ResourceBuildProfile.standardWeb,
    );
  }

  ResourceSlot? _parseResourceSlot(Object? value) {
    return ResourceSlot.values.cast<ResourceSlot?>().firstWhere(
          (slot) => slot?.name == value,
          orElse: () => null,
        );
  }

  TransactionState _parseTransactionState(Object? value) {
    if (value == 'staging' || value == 'switching') {
      return TransactionState.migrating;
    }
    return TransactionState.values.firstWhere(
      (state) => state.name == value,
      orElse: () => TransactionState.idle,
    );
  }
}
