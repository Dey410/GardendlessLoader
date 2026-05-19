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

class ResourcePickerService {
  ResourcePickerService({
    DirectoryPathPicker? directoryPathPicker,
    OhosDirectoryPathPicker? ohosDirectoryPathPicker,
    String? platformName,
  })  : _directoryPathPicker =
            directoryPathPicker ?? file_selector.getDirectoryPath,
        _ohosDirectoryPathPicker =
            ohosDirectoryPathPicker ?? _pickOhosDirectory,
        _platformName = platformName ?? Platform.operatingSystem;

  static const MethodChannel _ohosChannel = MethodChannel(
    'io.github.dey410.gardendlessloader/document_picker',
  );

  final DirectoryPathPicker _directoryPathPicker;
  final OhosDirectoryPathPicker _ohosDirectoryPathPicker;
  final String _platformName;

  Future<Directory?> pickDocsDirectory({Directory? initialDirectory}) async {
    final selectedPath = _platformName == 'ohos'
        ? await _ohosDirectoryPathPicker()
        : await _directoryPathPicker(
            initialDirectory: initialDirectory?.path,
            confirmButtonText: '选择 docs',
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
      return _ohosChannel.invokeMethod<String>('pickDocsDirectory');
    } on MissingPluginException catch (error) {
      throw ResourcePickerFailure(
        '当前鸿蒙构建缺少文档选择器实现：${error.message ?? error.toString()}',
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
