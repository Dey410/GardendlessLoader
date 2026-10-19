import 'dart:io';

import 'package:flutter/services.dart';

import '../models.dart';

class ResourcePickerService {
  ResourcePickerService() {
    _mobileZipImporterChannel.setMethodCallHandler(_handleNativeCall);
  }

  final String _platformName = Platform.operatingSystem;

  static const MethodChannel _mobileZipImporterChannel = MethodChannel(
    'io.github.dey410.gardendlessloader/resource_zip_importer',
  );

  ImportProgressCallback? _onProgress;

  /// Called with the file name when another app opens or shares a ZIP with
  /// the loader while the launcher is running.
  void Function(String name)? onIncomingZip;

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'progress':
        final progress = _decodeProgress(call.arguments);
        if (progress != null) _onProgress?.call(progress);
      case 'incomingZipReceived':
        final name = call.arguments;
        if (name is String) onIncomingZip?.call(name);
    }
  }

  /// File name of a ZIP another app handed to the loader and that is still
  /// waiting for the user's decision.
  Future<String?> incomingZipName() =>
      _mobileZipImporterChannel.invokeMethod<String>('incomingZip');

  Future<void> discardIncomingZip() =>
      _mobileZipImporterChannel.invokeMethod<void>('discardIncomingZip');

  /// Extracts from the system picker when [incoming] is false, otherwise
  /// from the ZIP another app handed to the loader.
  Future<Directory?> extractDocsZip({
    required bool incoming,
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

    _onProgress = onProgress;
    try {
      final extractedPath =
          await _mobileZipImporterChannel.invokeMethod<String>(
        incoming ? 'extractIncomingDocsZip' : 'pickAndExtractDocsZip',
        <String, Object?>{'targetDirectory': targetDirectory.path},
      );
      return extractedPath == null ? null : Directory(extractedPath);
    } on PlatformException catch (error) {
      throw ResourcePickerFailure(
        error.message ?? '无法导入选择的 ZIP',
        code: error.code,
      );
    } finally {
      _onProgress = null;
    }
  }

  bool get _isSupportedPlatform =>
      _platformName == 'android' ||
      _platformName == 'ios' ||
      _platformName == 'ohos';

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
