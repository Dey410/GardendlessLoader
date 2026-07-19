import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models.dart';

typedef GpNextOpenPathHandler = Future<List<String>> Function();
typedef GpNextOpenUrlHandler = Future<void> Function(Uri uri);
typedef GpNextExportHandler = Future<void> Function(File file, String name);

class GpNextBridgeService {
  GpNextBridgeService({
    required AppPaths paths,
    required GpNextOpenPathHandler openPath,
    required GpNextOpenUrlHandler openUrl,
    required GpNextExportHandler exportFile,
  })  : _paths = paths,
        _openPath = openPath,
        _openUrl = openUrl,
        _exportFile = exportFile;

  final AppPaths _paths;
  final GpNextOpenPathHandler _openPath;
  final GpNextOpenUrlHandler _openUrl;
  final GpNextExportHandler _exportFile;
  int _nextEventId = 1;
  final Set<String> _pendingExports = <String>{};

  Future<void> initialize() async {
    await _paths.gpNextPacksDir.create(recursive: true);
    await _paths.gpNextPatchesDir.create(recursive: true);
  }

  Future<Object?> invoke(Map<Object?, Object?> request) async {
    final command = request['command'] as String? ?? '';
    final args = _map(request['args']);
    final options = _map(request['options']);
    switch (command) {
      case 'plugin:path|resolve_directory':
        if (args['directory'] != 14) {
          throw GpNextBridgeFailure(
            '不允许解析 Tauri directory ${args['directory']}',
          );
        }
        return _paths.root.path;
      case 'plugin:fs|mkdir':
        await _makeDirectory(args['path'], args['options'] ?? options);
        return null;
      case 'plugin:fs|read_dir':
        return _readDirectory(args['path'], args['options'] ?? options);
      case 'plugin:fs|read_file':
      case 'plugin:fs|read_text_file':
        return _readFile(args['path'], args['options'] ?? options);
      case 'plugin:fs|exists':
        return _exists(args['path'], args['options'] ?? options);
      case 'plugin:fs|remove':
        await _remove(args['path'], args['options'] ?? options);
        return null;
      case 'plugin:fs|write_text_file':
        await _writeTextFile(args, options, request['args']);
        return null;
      case 'plugin:dialog|save':
        return _prepareExportPath(args);
      case 'plugin:opener|open_path':
        await _openPath();
        return null;
      case 'plugin:opener|open_url':
        final url = Uri.tryParse(args['url'] as String? ?? '');
        if (url == null || (url.scheme != 'https' && url.scheme != 'http')) {
          throw const GpNextBridgeFailure('GP-Next 请求打开无效网址');
        }
        await _openUrl(url);
        return null;
      case 'plugin:event|listen':
        return _nextEventId++;
      case 'plugin:event|unlisten':
      case 'plugin:event|emit':
      case 'plugin:event|emit_to':
      case 'plugin:resources|close':
        return null;
      case 'plugin:deep-link|get_current':
        return const <String>[];
      case 'plugin:deep-link|is_registered':
        return false;
      case 'plugin:deep-link|register':
      case 'plugin:deep-link|unregister':
        return null;
      case 'update_macos_menu':
        return null;
      case 'plugin:drpc|is_running':
        return false;
      case 'plugin:drpc|destroy_thread':
      case 'plugin:drpc|spawn_thread':
      case 'plugin:drpc|set_activity':
        return null;
      default:
        if (command.startsWith('plugin:window|') ||
            command.startsWith('plugin:image|')) {
          throw GpNextBridgeFailure('移动平台不支持 $command');
        }
        throw GpNextBridgeFailure('未兼容的 GP-Next 命令：$command');
    }
  }

  Future<List<Map<String, Object?>>> _readDirectory(
    Object? path,
    Object? options,
  ) async {
    final directory = _directory(path, options);
    await _assertNoSymlink(directory.path);
    if (!await directory.exists()) {
      throw GpNextBridgeFailure('目录不存在：${directory.path}');
    }
    final entries = <Map<String, Object?>>[];
    await for (final entity in directory.list(followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      entries.add({
        'name': p.basename(entity.path),
        'isFile': type == FileSystemEntityType.file,
        'isDirectory': type == FileSystemEntityType.directory,
        'isSymlink': type == FileSystemEntityType.link,
      });
    }
    entries.sort(
      (left, right) =>
          (left['name'] as String).compareTo(right['name'] as String),
    );
    return entries;
  }

  Future<bool> _exists(Object? path, Object? options) async {
    final resolved = _resolve(path, options);
    await _assertNoSymlink(resolved);
    return FileSystemEntity.type(
      resolved,
      followLinks: false,
    ).then((type) => type != FileSystemEntityType.notFound);
  }

  Future<List<int>> _readFile(Object? path, Object? options) async {
    final file = _file(path, options);
    await _assertNoSymlink(file.path);
    return file.readAsBytes();
  }

  Future<void> _makeDirectory(Object? path, Object? options) async {
    final directory = _directory(path, options);
    await _assertNoSymlink(directory.path);
    await directory.create(recursive: _recursive(options));
  }

  Future<void> _remove(Object? path, Object? options) async {
    final resolved = _resolve(path, options);
    await _assertNoSymlink(resolved);
    final type = await FileSystemEntity.type(resolved, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return;
    }
    if (type == FileSystemEntityType.link) {
      throw const GpNextBridgeFailure('不允许操作符号链接');
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(resolved).delete(recursive: _recursive(options));
    } else {
      await File(resolved).delete();
    }
  }

  Future<void> _writeTextFile(
    Map<Object?, Object?> args,
    Map<Object?, Object?> options,
    Object? rawArgs,
  ) async {
    final headers = _map(options['headers']);
    final encodedPath = headers['path'] as String?;
    final headerOptions = _decodeJsonMap(headers['options']);
    final path =
        encodedPath == null ? args['path'] : Uri.decodeComponent(encodedPath);
    final file = _file(path, headerOptions);
    await _assertNoSymlink(file.path);
    final bytes = _bytes(rawArgs);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    final normalized = p.normalize(file.absolute.path);
    if (_pendingExports.remove(normalized)) {
      await _exportFile(file, p.basename(file.path));
    }
  }

  Future<String?> _prepareExportPath(Map<Object?, Object?> args) async {
    final options = _map(args['options']);
    final requested = options['defaultPath'] as String?;
    final name = _safeFileName(requested ?? 'gardendless-export.json');
    final directory = Directory(p.join(_paths.gpNextDir.path, '.exports'));
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, name));
    _pendingExports.add(p.normalize(file.absolute.path));
    return file.path;
  }

  File _file(Object? path, Object? options) => File(_resolve(path, options));

  Directory _directory(Object? path, Object? options) =>
      Directory(_resolve(path, options));

  String _resolve(Object? value, Object? options) {
    if (value is! String || value.trim().isEmpty) {
      throw const GpNextBridgeFailure('GP-Next 文件路径为空');
    }
    final optionMap = _map(options);
    var raw = value.trim();
    if (raw.startsWith('file:')) {
      raw = Uri.parse(raw).toFilePath();
    }
    raw = raw
        .replaceAll('\\', Platform.pathSeparator)
        .replaceAll('/', Platform.pathSeparator);
    final baseDir = optionMap['baseDir'];
    final candidate = p.isAbsolute(raw)
        ? p.normalize(raw)
        : p.normalize(p.join(_paths.root.path, raw));
    if (baseDir != null && baseDir != 14) {
      throw GpNextBridgeFailure('不允许访问 Tauri baseDir $baseDir');
    }
    final root = p.normalize(_paths.gpNextDir.absolute.path);
    final absolute = p.normalize(File(candidate).absolute.path);
    if (!p.equals(root, absolute) && !p.isWithin(root, absolute)) {
      throw const GpNextBridgeFailure('GP-Next 路径超出 Loader 沙箱');
    }
    return absolute;
  }

  bool _recursive(Object? options) => _map(options)['recursive'] != false;

  Future<void> _assertNoSymlink(String resolved) async {
    final root = p.normalize(_paths.gpNextDir.absolute.path);
    if (await FileSystemEntity.type(root, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const GpNextBridgeFailure('GP-Next 根目录不能是符号链接');
    }
    final relative = p.relative(resolved, from: root);
    if (relative == '.') {
      return;
    }
    var current = root;
    for (final component in p.split(relative)) {
      current = p.join(current, component);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const GpNextBridgeFailure('不允许通过符号链接访问文件');
      }
      if (type == FileSystemEntityType.notFound) {
        return;
      }
    }
  }

  Map<Object?, Object?> _map(Object? value) {
    if (value is Map<Object?, Object?>) {
      return value;
    }
    if (value is Map) {
      return Map<Object?, Object?>.from(value);
    }
    return const <Object?, Object?>{};
  }

  Map<Object?, Object?> _decodeJsonMap(Object? value) {
    if (value is! String || value.isEmpty || value == 'undefined') {
      return const <Object?, Object?>{};
    }
    try {
      return _map(jsonDecode(value));
    } catch (_) {
      return const <Object?, Object?>{};
    }
  }

  List<int> _bytes(Object? raw) {
    final map = _map(raw);
    final values = map['__gardendlessBytes'];
    if (values is List) {
      return values.whereType<num>().map((value) => value.toInt()).toList();
    }
    if (raw is Uint8List) {
      return raw;
    }
    if (raw is List) {
      return raw.whereType<num>().map((value) => value.toInt()).toList();
    }
    throw const GpNextBridgeFailure('GP-Next 写入内容不是字节数组');
  }

  String _safeFileName(String value) {
    final basename = p.basename(value.replaceAll('\\', '/')).trim();
    final cleaned = basename
        .replaceAll(RegExp(r'[\x00-\x1f]'), '')
        .replaceAll(RegExp(r'[:*?"<>|]'), '_');
    return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
        ? 'gardendless-export.json'
        : cleaned;
  }
}

class GpNextBridgeFailure implements Exception {
  const GpNextBridgeFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
