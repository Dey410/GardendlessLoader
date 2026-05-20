import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

typedef DirectoryPathPicker = Future<String?> Function({
  String? initialDirectory,
  String? confirmButtonText,
  bool? canCreateDirectories,
});

typedef OhosDirectoryPathPicker = Future<String?> Function();
typedef AndroidDirectoryImporter = Future<String?> Function({
  required Directory targetDirectory,
});

class ResourcePickerService {
  ResourcePickerService({
    DirectoryPathPicker? directoryPathPicker,
    OhosDirectoryPathPicker? ohosDirectoryPathPicker,
    AndroidDirectoryImporter? androidDirectoryImporter,
    String? platformName,
  })  : _directoryPathPicker =
            directoryPathPicker ?? file_selector.getDirectoryPath,
        _ohosDirectoryPathPicker =
            ohosDirectoryPathPicker ?? _pickOhosDirectory,
        _androidDirectoryImporter =
            androidDirectoryImporter ?? _pickAndCopyAndroidDirectory,
        _platformName = platformName ?? Platform.operatingSystem;

  static const MethodChannel _documentPickerChannel = MethodChannel(
    'io.github.dey410.gardendlessloader/document_picker',
  );

  final DirectoryPathPicker _directoryPathPicker;
  final OhosDirectoryPathPicker _ohosDirectoryPathPicker;
  final AndroidDirectoryImporter _androidDirectoryImporter;
  final String _platformName;

  Future<Directory?> pickDocsDirectory({
    Directory? initialDirectory,
    Directory? localImportDocsDir,
  }) async {
    if (_platformName == 'android') {
      final targetDirectory = localImportDocsDir;
      if (targetDirectory == null) {
        throw ResourcePickerFailure(
          'Android import requires an app-private target directory',
        );
      }
      final copiedPath = await _androidDirectoryImporter(
        targetDirectory: targetDirectory,
      );
      if (copiedPath == null || copiedPath.trim().isEmpty) {
        return null;
      }
      return Directory(copiedPath.trim());
    }

    final selectedPath = _platformName == 'ohos'
        ? await _ohosDirectoryPathPicker()
        : await _directoryPathPicker(
            initialDirectory: initialDirectory?.path,
            confirmButtonText: '\u9009\u62e9 docs',
            canCreateDirectories: false,
          );

    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return null;
    }

    return _resolveDocsDirectory(Directory(selectedPath.trim()));
  }

  Future<Directory> _resolveDocsDirectory(Directory selected) async {
    if (await _looksLikeDocsDirectory(selected)) {
      return selected;
    }

    final nestedDocs = Directory(p.join(selected.path, 'docs'));
    if (await _looksLikeDocsDirectory(nestedDocs)) {
      return nestedDocs;
    }

    return selected;
  }

  Future<bool> _looksLikeDocsDirectory(Directory directory) async {
    return File(p.join(directory.path, 'index.html')).exists();
  }

  static Future<String?> _pickOhosDirectory() async {
    try {
      return _documentPickerChannel.invokeMethod<String>('pickDocsDirectory');
    } on MissingPluginException catch (error) {
      throw ResourcePickerFailure(
        'Current OHOS build does not implement the document picker: '
        '${error.message ?? error.toString()}',
      );
    } on PlatformException catch (error) {
      throw ResourcePickerFailure(error.message ?? error.code);
    }
  }

  static Future<String?> _pickAndCopyAndroidDirectory({
    required Directory targetDirectory,
  }) async {
    try {
      return _documentPickerChannel.invokeMethod<String>('pickDocsDirectory', {
        'targetDirectory': targetDirectory.path,
      });
    } on MissingPluginException catch (error) {
      throw ResourcePickerFailure(
        'Current Android build does not implement the document picker: '
        '${error.message ?? error.toString()}',
      );
    } on PlatformException catch (error) {
      throw ResourcePickerFailure(error.message ?? error.code);
    }
  }
}

class ResourcePickerFailure implements Exception {
  ResourcePickerFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
