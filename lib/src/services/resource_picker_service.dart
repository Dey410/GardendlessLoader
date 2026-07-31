import 'dart:io';

import 'package:flutter/services.dart';

import '../models.dart';

typedef MobileZipImporter = Future<String?> Function({
  required String targetDirectory,
  ImportProgressCallback? onProgress,
});

class ResourcePickerService {
  ResourcePickerService({
    String? platformName,
    MobileZipImporter? mobileZipImporter,
  })  : _platformName = platformName ?? Platform.operatingSystem,
        _mobileZipImporter = mobileZipImporter ?? _pickAndExtractMobileDocsZip;

  final String _platformName;
  final MobileZipImporter _mobileZipImporter;

  static const MethodChannel _mobileZipImporterChannel = MethodChannel(
    'io.github.dey410.gardendlessloader/resource_zip_importer',
  );

  Future<Directory?> pickAndExtractDocsZip({
    Directory? targetDirectory,
    ImportProgressCallback? onProgress,
  }) async {
    if (targetDirectory == null) {
      throw ResourcePickerFailure(
        'ZIP import requires an app-private target directory',
        code: 'invalid_target_directory',
      );
    }

    if (!_isSupportedPlatform) {
      throw ResourcePickerFailure(
        '当前平台不支持 ZIP 导入：$_platformName',
        code: 'platform_unsupported',
      );
    }

    try {
      final extractedPath = await _mobileZipImporter(
        targetDirectory: targetDirectory.path,
        onProgress: onProgress,
      );
      return extractedPath == null ? null : Directory(extractedPath);
    } on PlatformException catch (error) {
      throw ResourcePickerFailure(
        error.message ?? '无法导入选择的 ZIP',
        code: error.code,
      );
    }
  }

  bool get _isSupportedPlatform =>
      _platformName == 'android' ||
      _platformName == 'ios' ||
      _platformName == 'ohos';

  static Future<String?> _pickAndExtractMobileDocsZip({
    required String targetDirectory,
    ImportProgressCallback? onProgress,
  }) async {
    _mobileZipImporterChannel.setMethodCallHandler((call) async {
      if (call.method != 'progress' || onProgress == null) {
        return;
      }
      final progress = _decodeProgress(call.arguments);
      if (progress != null) {
        onProgress(progress);
      }
    });
    try {
      return await _mobileZipImporterChannel.invokeMethod<String>(
        'pickAndExtractDocsZip',
        <String, Object?>{
          'targetDirectory': targetDirectory,
        },
      );
    } finally {
      _mobileZipImporterChannel.setMethodCallHandler(null);
    }
  }

  static ImportProgress? _decodeProgress(Object? arguments) {
    if (arguments is! Map) {
      return null;
    }
    final phase = switch (arguments['phase']) {
      'receiving' => ImportPhase.receiving,
      'extracting' => ImportPhase.extracting,
      _ => null,
    };
    if (phase == null) {
      return null;
    }
    int readInt(String key) => (arguments[key] as num?)?.toInt() ?? 0;

    return ImportProgress(
      phase: phase,
      copiedBytes: readInt('processedBytes'),
      totalBytes: readInt('totalBytes'),
      copiedFiles: readInt('processedFiles'),
      totalFiles: readInt('totalFiles'),
      message: arguments['message'] as String?,
    );
  }
}

class ResourcePickerFailure implements Exception {
  ResourcePickerFailure(this.message, {this.code = 'import_extract_failed'});

  final String message;
  final String code;

  @override
  String toString() => message;
}
