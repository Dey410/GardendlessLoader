import 'dart:io';

import 'package:archive/archive.dart' as archive;
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

typedef DirectoryPathPicker = Future<String?> Function({
  String? initialDirectory,
  String? confirmButtonText,
  bool? canCreateDirectories,
});

typedef ResourceFilePicker = Future<file_selector.XFile?> Function({
  required List<file_selector.XTypeGroup> acceptedTypeGroups,
  String? initialDirectory,
  String? confirmButtonText,
});

typedef OhosDirectoryPathPicker = Future<String?> Function();
typedef AndroidDirectoryImporter = Future<String?> Function({
  required Directory targetDirectory,
});

class ResourcePickerService {
  ResourcePickerService({
    DirectoryPathPicker? directoryPathPicker,
    ResourceFilePicker? filePicker,
    OhosDirectoryPathPicker? ohosDirectoryPathPicker,
    AndroidDirectoryImporter? androidDirectoryImporter,
    String? platformName,
  })  : _directoryPathPicker =
            directoryPathPicker ?? file_selector.getDirectoryPath,
        _filePicker = filePicker ?? file_selector.openFile,
        _ohosDirectoryPathPicker =
            ohosDirectoryPathPicker ?? _pickOhosDirectory,
        _androidDirectoryImporter =
            androidDirectoryImporter ?? _pickAndCopyAndroidDirectory,
        _platformName = platformName ?? Platform.operatingSystem;

  static const MethodChannel _documentPickerChannel = MethodChannel(
    'io.github.dey410.gardendlessloader/document_picker',
  );

  final DirectoryPathPicker _directoryPathPicker;
  final ResourceFilePicker _filePicker;
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

    if (_platformName == 'ios') {
      final targetDirectory = localImportDocsDir;
      if (targetDirectory == null) {
        throw ResourcePickerFailure(
          'iOS import requires an app-private target directory',
        );
      }
      return _pickAndExtractIosZip(
        initialDirectory: initialDirectory,
        targetDirectory: targetDirectory,
      );
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

  Future<Directory?> _pickAndExtractIosZip({
    Directory? initialDirectory,
    required Directory targetDirectory,
  }) async {
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
      confirmButtonText: 'Choose ZIP',
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
          'Selected ZIP does not contain a valid docs directory',
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
      throw ResourcePickerFailure('Unable to import selected ZIP: $error');
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
          'Selected ZIP contains an unsupported symbolic link',
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
          'Selected ZIP contains a file outside docs',
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
      throw ResourcePickerFailure('Selected ZIP contains an unsafe path');
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
