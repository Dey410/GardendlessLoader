import 'dart:io';

import 'package:archive/archive.dart' as archive;
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

typedef ResourceFilePicker = Future<file_selector.XFile?> Function({
  required List<file_selector.XTypeGroup> acceptedTypeGroups,
  String? initialDirectory,
  String? confirmButtonText,
});

typedef AndroidZipImporter = Future<String?> Function({
  required String targetDirectory,
});

class ResourcePickerService {
  ResourcePickerService({
    ResourceFilePicker? filePicker,
    String? platformName,
    AndroidZipImporter? androidZipImporter,
  })  : _filePicker = filePicker ?? file_selector.openFile,
        _platformName = platformName ?? Platform.operatingSystem,
        _androidZipImporter =
            androidZipImporter ?? _pickAndExtractAndroidDocsZip;

  final ResourceFilePicker _filePicker;
  final String _platformName;
  final AndroidZipImporter _androidZipImporter;

  static const MethodChannel _androidZipImporterChannel = MethodChannel(
    'io.github.dey410.gardendlessloader/resource_zip_importer',
  );

  Future<Directory?> pickAndExtractDocsZip({
    Directory? initialDirectory,
    Directory? localImportDocsDir,
  }) async {
    final targetDirectory = localImportDocsDir;
    if (targetDirectory == null) {
      throw ResourcePickerFailure(
        'ZIP import requires an app-private target directory',
      );
    }

    if (_platformName == 'android') {
      try {
        final extractedPath = await _androidZipImporter(
          targetDirectory: targetDirectory.path,
        );
        return extractedPath == null ? null : Directory(extractedPath);
      } on PlatformException catch (error) {
        throw ResourcePickerFailure(
          error.message ?? '无法导入选择的 ZIP',
        );
      }
    }

    final selectedZip = await _filePicker(
      acceptedTypeGroups: const [
        file_selector.XTypeGroup(
          label: 'ZIP archive',
          extensions: ['zip'],
          mimeTypes: ['application/zip'],
          uniformTypeIdentifiers: ['public.zip-archive'],
        ),
      ],
      initialDirectory: initialDirectory?.path,
      confirmButtonText: '选择 ZIP',
    );
    if (selectedZip == null) {
      return null;
    }

    try {
      final zipBytes = await selectedZip.readAsBytes();
      final decoded = archive.ZipDecoder().decodeBytes(zipBytes, verify: true);
      final docsPrefix = _findDocsPrefix(decoded);
      if (docsPrefix == null) {
        throw ResourcePickerFailure(
          '选择的 ZIP 中没有找到有效的 docs 资源目录',
        );
      }

      await _resetDirectory(targetDirectory);
      await _extractArchivePrefix(
        decoded,
        prefix: docsPrefix,
        targetDirectory: targetDirectory,
      );
      return targetDirectory;
    } on ResourcePickerFailure {
      rethrow;
    } catch (error) {
      throw ResourcePickerFailure('无法导入选择的 ZIP：$error');
    }
  }

  String? _findDocsPrefix(archive.Archive decoded) {
    final filePaths = decoded.files
        .where((file) => file.isFile)
        .map((file) => _safeArchivePath(file.name))
        .toSet();
    final directoryPaths = decoded.files
        .where((file) => !file.isFile)
        .map((file) => _safeArchivePath(file.name))
        .toSet();

    final candidates = <String>{};
    for (final path in filePaths) {
      if (p.posix.basename(path).toLowerCase() == 'index.html') {
        final directory = p.posix.dirname(path);
        candidates.add(directory == '.' ? '' : directory);
      }
    }

    final validCandidates = candidates.where((candidate) {
      bool hasFile(String relativePath) {
        final path = candidate.isEmpty
            ? relativePath
            : p.posix.join(candidate, relativePath);
        return filePaths.contains(path);
      }

      bool hasDirectory(String relativePath) {
        final path = candidate.isEmpty
            ? relativePath
            : p.posix.join(candidate, relativePath);
        return directoryPaths.contains(path) ||
            filePaths.any((filePath) => filePath.startsWith('$path/'));
      }

      return hasFile('index.html') &&
          hasFile(p.posix.join('src', 'settings.json')) &&
          hasFile(p.posix.join('src', 'import-map.json')) &&
          hasDirectory('assets') &&
          hasDirectory('cocos-js') &&
          hasDirectory('src');
    }).toList()
      ..sort((a, b) {
        final aIsDocs = p.posix.basename(a) == 'docs';
        final bIsDocs = p.posix.basename(b) == 'docs';
        if (aIsDocs != bIsDocs) {
          return aIsDocs ? -1 : 1;
        }
        return a.length.compareTo(b.length);
      });

    return validCandidates.isEmpty ? null : validCandidates.first;
  }

  Future<void> _extractArchivePrefix(
    archive.Archive decoded, {
    required String prefix,
    required Directory targetDirectory,
  }) async {
    final rootPath = p.normalize(targetDirectory.path);

    for (final file in decoded.files) {
      if (file.isSymbolicLink) {
        throw ResourcePickerFailure(
          '选择的 ZIP 包含不支持的符号链接',
        );
      }

      final archivePath = _safeArchivePath(file.name);
      if (!_isWithinArchivePrefix(archivePath, prefix)) {
        continue;
      }

      final relativePath = prefix.isEmpty
          ? archivePath
          : p.posix.relative(archivePath, from: prefix);
      if (relativePath == '.' || relativePath.isEmpty) {
        continue;
      }

      final diskPath = p.joinAll([
        targetDirectory.path,
        ...p.posix.split(relativePath),
      ]);
      final normalizedDiskPath = p.normalize(diskPath);
      if (!p.equals(rootPath, normalizedDiskPath) &&
          !p.isWithin(rootPath, normalizedDiskPath)) {
        throw ResourcePickerFailure(
          '选择的 ZIP 包含 docs 外部路径',
        );
      }

      if (file.isFile) {
        final targetFile = File(normalizedDiskPath);
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(file.content as List<int>, flush: true);
      } else {
        await Directory(normalizedDiskPath).create(recursive: true);
      }
    }
  }

  String _safeArchivePath(String path) {
    final normalized = p.posix.normalize(path.replaceAll('\\', '/'));
    if (normalized == '.' ||
        p.posix.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.contains('/../')) {
      throw ResourcePickerFailure('选择的 ZIP 包含不安全路径');
    }
    return normalized;
  }

  bool _isWithinArchivePrefix(String path, String prefix) {
    if (prefix.isEmpty) {
      return true;
    }
    return path == prefix || path.startsWith('$prefix/');
  }

  Future<void> _resetDirectory(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
  }

  static Future<String?> _pickAndExtractAndroidDocsZip({
    required String targetDirectory,
  }) {
    return _androidZipImporterChannel.invokeMethod<String>(
      'pickAndExtractDocsZip',
      <String, Object?>{
        'targetDirectory': targetDirectory,
      },
    );
  }
}

class ResourcePickerFailure implements Exception {
  ResourcePickerFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
