import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models.dart';

typedef GpNextNativeFilePicker = Future<List<String>?> Function(
    String targetDirectory);
typedef GpNextReplaceConfirmation = Future<bool> Function(String fileName);

class GpNextPackageImporter {
  GpNextPackageImporter({
    required AppPaths paths,
    required GpNextReplaceConfirmation confirmReplace,
    GpNextNativeFilePicker? nativeFilePicker,
  })  : _paths = paths,
        _confirmReplace = confirmReplace,
        _nativeFilePicker = nativeFilePicker ?? _pickNativeFiles;

  static const MethodChannel _channel = MethodChannel(
    'io.github.dey410.gardendlessloader/gp_next_file_importer',
  );

  final AppPaths _paths;
  final GpNextReplaceConfirmation _confirmReplace;
  final GpNextNativeFilePicker _nativeFilePicker;

  Future<List<String>> pickAndImport() async {
    await _paths.gpNextPacksDir.create(recursive: true);
    await _paths.gpNextPatchesDir.create(recursive: true);
    final staging = Directory(
      p.join(
        _paths.gpNextDir.path,
        '.import-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await staging.create(recursive: true);
    try {
      final selected = await _nativeFilePicker(staging.path);
      if (selected == null || selected.isEmpty) {
        return const <String>[];
      }
      final imported = <String>[];
      for (final selectedPath in selected) {
        final source = File(selectedPath);
        _requireInside(staging, source);
        if (!await source.exists()) {
          throw GpNextPackageImportFailure('选择的文件不存在：$selectedPath');
        }
        final extension = p.extension(source.path).toLowerCase();
        final Directory destinationDirectory;
        switch (extension) {
          case '.zip':
            if (!await _zipContainsRootPackJson(source)) {
              throw GpNextPackageImportFailure(
                '${p.basename(source.path)} 缺少根目录 pack.json',
              );
            }
            destinationDirectory = _paths.gpNextPacksDir;
            break;
          case '.json':
            await _validateJson(source);
            destinationDirectory = _paths.gpNextPatchesDir;
            break;
          case '.json5':
            if (await source.length() == 0) {
              throw GpNextPackageImportFailure(
                '${p.basename(source.path)} 是空文件',
              );
            }
            destinationDirectory = _paths.gpNextPatchesDir;
            break;
          default:
            throw GpNextPackageImportFailure(
              '不支持的 GP-Next 文件：${p.basename(source.path)}',
            );
        }
        final safeName = _safeFileName(p.basename(source.path));
        final name = '${p.basenameWithoutExtension(safeName)}$extension';
        final destination = File(p.join(destinationDirectory.path, name));
        if (await destination.exists() && !await _confirmReplace(name)) {
          continue;
        }
        await _replaceTransactionally(source, destination);
        imported.add(name);
      }
      return imported;
    } finally {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<void> _replaceTransactionally(File source, File destination) async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final incoming = File('${destination.path}.incoming-$suffix');
    final backup = File('${destination.path}.backup-$suffix');
    await incoming.parent.create(recursive: true);
    await source.copy(incoming.path);
    var movedOld = false;
    try {
      if (await destination.exists()) {
        await destination.rename(backup.path);
        movedOld = true;
      }
      await incoming.rename(destination.path);
      if (movedOld && await backup.exists()) {
        try {
          await backup.delete();
        } catch (_) {
          if (await destination.exists()) {
            await destination.delete();
          }
          if (await backup.exists()) {
            await backup.rename(destination.path);
          }
          rethrow;
        }
      }
    } catch (_) {
      if (await incoming.exists()) {
        await incoming.delete();
      }
      if (movedOld && await backup.exists() && !await destination.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
  }

  Future<void> _validateJson(File file) async {
    try {
      jsonDecode(await file.readAsString());
    } catch (_) {
      throw GpNextPackageImportFailure('${p.basename(file.path)} 不是有效 JSON');
    }
  }

  Future<bool> _zipContainsRootPackJson(File file) async {
    final handle = await file.open();
    try {
      final length = await handle.length();
      if (length < 22) {
        return false;
      }
      final tailLength = length < 65557 ? length : 65557;
      await handle.setPosition(length - tailLength);
      final tail = Uint8List.fromList(await handle.read(tailLength));
      var eocd = -1;
      for (var index = tail.length - 22; index >= 0; index--) {
        if (_u32(tail, index) == 0x06054b50) {
          eocd = index;
          break;
        }
      }
      if (eocd < 0) {
        return false;
      }
      final entryCount = _u16(tail, eocd + 10);
      final centralOffset = _u32(tail, eocd + 16);
      if (entryCount == 0xffff || centralOffset == 0xffffffff) {
        throw const GpNextPackageImportFailure('暂不支持 ZIP64 格式的 GP-Next 补丁包');
      }
      await handle.setPosition(centralOffset);
      for (var index = 0; index < entryCount; index++) {
        final header = Uint8List.fromList(await handle.read(46));
        if (header.length != 46 || _u32(header, 0) != 0x02014b50) {
          return false;
        }
        final flags = _u16(header, 8);
        if ((flags & 0x0001) != 0) {
          throw const GpNextPackageImportFailure('不支持加密的 GP-Next 补丁包');
        }
        final nameLength = _u16(header, 28);
        final extraLength = _u16(header, 30);
        final commentLength = _u16(header, 32);
        final nameBytes = await handle.read(nameLength);
        final name = utf8
            .decode(nameBytes, allowMalformed: true)
            .replaceAll('\\', '/')
            .replaceFirst(RegExp(r'^\./'), '');
        if (name == 'pack.json') {
          return true;
        }
        await handle.setPosition(
          await handle.position() + extraLength + commentLength,
        );
      }
      return false;
    } finally {
      await handle.close();
    }
  }

  int _u16(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  int _u32(Uint8List bytes, int offset) =>
      _u16(bytes, offset) | (_u16(bytes, offset + 2) << 16);

  void _requireInside(Directory root, File file) {
    final rootPath = p.normalize(root.absolute.path);
    final filePath = p.normalize(file.absolute.path);
    if (!p.isWithin(rootPath, filePath)) {
      throw const GpNextPackageImportFailure('系统文件选择器返回了沙箱外路径');
    }
  }

  String _safeFileName(String value) {
    final cleaned = p
        .basename(value.replaceAll('\\', '/'))
        .replaceAll(RegExp(r'[\x00-\x1f]'), '')
        .replaceAll(RegExp(r'[:*?"<>|]'), '_')
        .trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      throw const GpNextPackageImportFailure('补丁文件名无效');
    }
    return cleaned;
  }

  static Future<List<String>?> _pickNativeFiles(String targetDirectory) async {
    final result = await _channel.invokeListMethod<String>(
      'pickAndCopyFiles',
      <String, Object?>{'targetDirectory': targetDirectory},
    );
    return result;
  }
}

class GpNextPackageImportFailure implements Exception {
  const GpNextPackageImportFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
