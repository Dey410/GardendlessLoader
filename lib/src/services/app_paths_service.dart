import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../models.dart';

const _androidMediaIgnoreFileName = '.nomedia';

class AppPathsService {
  final String _platformName = Platform.operatingSystem;

  Future<AppPaths> ensureInitialized() async {
    final root = await _defaultRoot();
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
    // gp-next stays absent until GP-Next creates it: its fresh-install check
    // treats an existing gp-next directory as a legacy installation.
  }

  Future<Directory> _defaultRoot() async {
    if (_platformName == 'ios' || _platformName == 'ohos') {
      final documents = await getApplicationDocumentsDirectory();
      return Directory(p.join(documents.path, resourceFolderName));
    }

    if (_platformName == 'android') {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        return Directory(p.join(external.path, resourceFolderName));
      }
    }

    if (_platformName == 'android') {
      final documents = await getApplicationDocumentsDirectory();
      return Directory(p.join(documents.path, resourceFolderName));
    }

    throw UnsupportedError('当前平台不受支持：$_platformName');
  }
}
