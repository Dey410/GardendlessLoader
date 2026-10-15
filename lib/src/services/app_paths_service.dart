import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../models.dart';

const _androidMediaIgnoreFileName = '.nomedia';

typedef DirectoryProvider = Future<Directory> Function();
typedef NullableDirectoryProvider = Future<Directory?> Function();

class AppPathsService {
  AppPathsService({
    Directory? rootOverride,
    String? platformName,
    DirectoryProvider? documentsDirectoryProvider,
    NullableDirectoryProvider? externalStorageDirectoryProvider,
  })  : _rootOverride = rootOverride,
        _platformName = platformName ?? Platform.operatingSystem,
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
        _externalStorageDirectoryProvider =
            externalStorageDirectoryProvider ?? getExternalStorageDirectory;

  final Directory? _rootOverride;
  final String _platformName;
  final DirectoryProvider _documentsDirectoryProvider;
  final NullableDirectoryProvider _externalStorageDirectoryProvider;

  Future<AppPaths> ensureInitialized() async {
    final root = _rootOverride ?? await _defaultRoot();
    final paths = _buildPaths(root);
    await _createPaths(paths);
    return paths;
  }

  AppPaths _buildPaths(Directory root) {
    return AppPaths(
      root: root,
      manifestFile: File(p.join(root.path, 'manifest.json')),
    );
  }

  Future<void> _createPaths(AppPaths paths) async {
    await paths.root.create(recursive: true);
    if (_platformName == 'android') {
      await File(p.join(paths.root.path, _androidMediaIgnoreFileName)).create();
    }
    await paths.slotADir.create(recursive: true);
    await paths.slotBDir.create(recursive: true);
    await paths.gpNextPacksDir.create(recursive: true);
    await paths.gpNextPatchesDir.create(recursive: true);
  }

  Future<Directory> _defaultRoot() async {
    if (_platformName == 'ios' || _platformName == 'ohos') {
      final documents = await _documentsDirectoryProvider();
      return Directory(p.join(documents.path, resourceFolderName));
    }

    if (_platformName == 'android') {
      final external = await _externalStorageDirectoryProvider();
      if (external != null) {
        return Directory(p.join(external.path, resourceFolderName));
      }
    }

    if (_platformName == 'android') {
      final documents = await _documentsDirectoryProvider();
      return Directory(p.join(documents.path, resourceFolderName));
    }

    throw UnsupportedError('当前平台不受支持：$_platformName');
  }
}
