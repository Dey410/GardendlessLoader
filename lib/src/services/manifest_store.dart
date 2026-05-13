import 'dart:convert';
import 'dart:io';

import '../models.dart';

class ManifestStore {
  ManifestStore(this._file);

  final File _file;

  Future<ResourceManifest> read() async {
    if (!await _file.exists()) {
      return ResourceManifest.initial();
    }

    try {
      final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      return ResourceManifest(
        schemaVersion: json['schemaVersion'] as int? ?? 1,
        lastImportAt: _parseDate(json['lastImportAt']),
        fileCount: json['fileCount'] as int? ?? 0,
        totalBytes: json['totalBytes'] as int? ?? 0,
        detectedTitle: json['detectedTitle'] as String?,
        resourceStatus: _parseResourceStatus(json['resourceStatus']),
        lastSelfCheckAt: _parseDate(json['lastSelfCheckAt']),
        lastErrorCode: json['lastErrorCode'] as String?,
        lastErrorMessage: json['lastErrorMessage'] as String?,
        transactionState: _parseTransactionState(
          (json['transaction'] as Map?)?['state'],
        ),
      );
    } catch (_) {
      return ResourceManifest.initial().copyWith(
        resourceStatus: ResourceStatus.invalid,
        lastErrorCode: 'manifest_unreadable',
        lastErrorMessage: 'manifest.json 无法读取或不是有效 JSON',
      );
    }
  }

  Future<void> write(ResourceManifest manifest) async {
    await _file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _file.writeAsString('${encoder.convert(manifest.toJson())}\n');
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

  TransactionState _parseTransactionState(Object? value) {
    return TransactionState.values.firstWhere(
      (state) => state.name == value,
      orElse: () => TransactionState.idle,
    );
  }
}
