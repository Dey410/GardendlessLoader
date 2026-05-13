import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../models.dart';

class AppPathsService {
  AppPathsService({Directory? rootOverride}) : _rootOverride = rootOverride;

  final Directory? _rootOverride;

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
    if (Platform.isIOS) {
      final documents = await getApplicationDocumentsDirectory();
      return Directory(p.join(documents.path, resourceFolderName));
    }

    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        return Directory(p.join(external.path, resourceFolderName));
      }
    }

    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, resourceFolderName));
  }
}
