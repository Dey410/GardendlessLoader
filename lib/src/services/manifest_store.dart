import 'dart:convert';
import 'dart:io';

import '../models.dart';

class ManifestStore {
  ManifestStore(this._file);

  final File _file;

  File get _temporaryFile => File('${_file.path}.tmp');

  Future<ResourceManifest> read() async {
    final mainExists = await _file.exists();
    final temporaryExists = await _temporaryFile.exists();
    if (!mainExists && !temporaryExists) {
      return ResourceManifest.initial();
    }

    final main = mainExists ? await _tryRead(_file) : null;
    final temporary = temporaryExists ? await _tryRead(_temporaryFile) : null;
    final useTemporary = temporary != null &&
        (main == null || temporary.generation > main.generation);
    final selected = useTemporary ? temporary : main;
    if (selected == null) {
      return ResourceManifest.initial().copyWith(
        resourceStatus: ResourceStatus.invalid,
        lastErrorCode: 'manifest_unreadable',
        lastErrorMessage: 'manifest.json 无法读取或不是有效 JSON',
      );
    }

    if (useTemporary) {
      await _temporaryFile.rename(_file.path);
    } else if (temporaryExists) {
      await _temporaryFile.delete();
    }
    return selected;
  }

  Future<void> write(ResourceManifest manifest) async {
    await _file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _temporaryFile.writeAsString(
      '${encoder.convert(manifest.toJson())}\n',
      flush: true,
    );
    await _temporaryFile.rename(_file.path);
  }

  Future<ResourceManifest?> _tryRead(File file) async {
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return ResourceManifest(
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
        autoCollectSunEnabled: json['autoCollectSunEnabled'] as bool? ?? false,
        resourceStatus: _parseResourceStatus(json['resourceStatus']),
        lastSelfCheckAt: _parseDate(json['lastSelfCheckAt']),
        lastErrorCode: json['lastErrorCode'] as String?,
        lastErrorMessage: json['lastErrorMessage'] as String?,
        transactionState: _parseTransactionState(
          (json['transaction'] as Map?)?['state'],
        ),
      );
    } catch (_) {
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
