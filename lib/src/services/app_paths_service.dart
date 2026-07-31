import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../models.dart';
import 'app_logger.dart';

const _androidMediaIgnoreFileName = '.nomedia';

typedef DirectoryProvider = Future<Directory> Function();
typedef NullableDirectoryProvider = Future<Directory?> Function();

class AppPathsService {
  AppPathsService({
    Directory? rootOverride,
    String? platformName,
    DirectoryProvider? documentsDirectoryProvider,
    NullableDirectoryProvider? externalStorageDirectoryProvider,
    AppLogger? logger,
  })  : _rootOverride = rootOverride,
        _platformName = platformName ?? Platform.operatingSystem,
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
        _externalStorageDirectoryProvider =
            externalStorageDirectoryProvider ?? getExternalStorageDirectory,
        _logger = logger ?? AppLogger.instance;

  final Directory? _rootOverride;
  final String _platformName;
  final DirectoryProvider _documentsDirectoryProvider;
  final NullableDirectoryProvider _externalStorageDirectoryProvider;
  final AppLogger _logger;

  Future<AppPaths> ensureInitialized() async {
    final operationId = _logger.nextOperationId('paths-initialize');
    _logger.info(
      'paths.initialize',
      'Initializing application directories',
      operationId: operationId,
      data: <String, Object?>{
        'platform': _platformName,
        'hasRootOverride': _rootOverride != null,
      },
    );

    if (_rootOverride != null) {
      final paths = _buildPaths(_rootOverride);
      await _createPaths(paths);
      await _initializePersistentLogging(paths);
      _logger.info(
        'paths.initialize',
        'Application directories initialized from override',
        operationId: operationId,
        data: <String, Object?>{'root': paths.root.path},
      );
      return paths;
    }

    Object? lastError;
    StackTrace? lastStackTrace;
    final roots = await _defaultRoots();
    for (final root in roots) {
      final paths = _buildPaths(root);
      try {
        await _createPaths(paths);
        await _initializePersistentLogging(paths);
        _logger.info(
          'paths.initialize',
          'Application directories initialized',
          operationId: operationId,
          data: <String, Object?>{'root': paths.root.path},
        );
        return paths;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        _logger.warning(
          'paths.initialize',
          'Application directory candidate failed',
          operationId: operationId,
          code: 'path_candidate_failed',
          error: error,
          stackTrace: stackTrace,
          data: <String, Object?>{'root': root.path},
        );
      }
    }

    _logger.error(
      'paths.initialize',
      'All application directory candidates failed',
      operationId: operationId,
      code: 'path_initialization_failed',
      error: lastError,
      stackTrace: lastStackTrace,
      data: <String, Object?>{
        'candidateCount': roots.length,
        'platform': _platformName,
      },
    );
    throw StateError('Unable to initialize app directories: $lastError');
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

  Future<void> _initializePersistentLogging(AppPaths paths) {
    return _logger.initialize(
      directory: Directory(p.join(paths.root.path, 'logs')),
    );
  }

  Future<List<Directory>> _defaultRoots() async {
    if (_platformName == 'ios') {
      final documents = await _documentsDirectoryProvider();
      return [Directory(p.join(documents.path, resourceFolderName))];
    }

    if (_platformName == 'ohos') {
      final documents = await _documentsDirectoryProvider();
      return [Directory(p.join(documents.path, resourceFolderName))];
    }

    if (_platformName == 'android') {
      final external = await _externalStorageDirectoryProvider();
      if (external != null) {
        return [Directory(p.join(external.path, resourceFolderName))];
      }
    }

    if (_platformName == 'android') {
      final documents = await _documentsDirectoryProvider();
      return [Directory(p.join(documents.path, resourceFolderName))];
    }

    throw UnsupportedError('当前平台不受支持：$_platformName');
  }
}
