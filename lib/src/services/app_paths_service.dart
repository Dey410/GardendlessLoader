import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../models.dart';

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
    final paths = AppPaths(
      root: root,
      manifestFile: File(p.join(root.path, 'manifest.json')),
      importDir: Directory(p.join(root.path, 'import')),
      importDocsDir: Directory(p.join(root.path, 'import', 'docs')),
      currentDir: Directory(p.join(root.path, 'current')),
      previousDir: Directory(p.join(root.path, 'previous')),
      stagingDir: Directory(p.join(root.path, 'staging')),
    );

    await paths.root.create(recursive: true);
    await paths.importDir.create(recursive: true);
    await paths.currentDir.create(recursive: true);
    await paths.previousDir.create(recursive: true);
    await paths.stagingDir.create(recursive: true);

    return paths;
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

    final documents = await _documentsDirectoryProvider();
    return Directory(p.join(documents.path, resourceFolderName));
  }
}
