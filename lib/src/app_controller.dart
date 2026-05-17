import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'constants.dart';
import 'models.dart';
import 'services/announcement_service.dart';
import 'services/app_paths_service.dart';
import 'services/diagnostics_service.dart';
import 'services/import_service.dart';
import 'services/local_game_server.dart';
import 'services/manifest_store.dart';
import 'services/resource_validator.dart';

class AppController extends ChangeNotifier {
  AppController({
    AppPathsService? pathsService,
    ResourceValidator? validator,
    LocalGameServer? server,
    ImportService? importService,
    DiagnosticsService? diagnosticsService,
    AnnouncementService? announcementService,
    DateTime Function()? now,
  })  : _pathsService = pathsService ?? AppPathsService(),
        _validator = validator ?? ResourceValidator(),
        _server = server ?? LocalGameServer(),
        _diagnosticsService = diagnosticsService ?? DiagnosticsService(),
        _announcementService = announcementService ?? AnnouncementService(),
        _now = now ?? DateTime.now {
    _importService = importService ??
        ImportService(
          validator: _validator,
          server: _server,
        );
  }

  final AppPathsService _pathsService;
  final ResourceValidator _validator;
  final LocalGameServer _server;
  final DiagnosticsService _diagnosticsService;
  final AnnouncementService _announcementService;
  final DateTime Function() _now;
  late final ImportService _importService;

  AppPaths? _paths;
  ManifestStore? _manifestStore;
  ResourceManifest _manifest = ResourceManifest.initial();
  ResourceValidationResult _currentValidation =
      ResourceValidationResult.missing('尚未检查 current');
  ResourceValidationResult _importValidation =
      ResourceValidationResult.missing('尚未检查 import/docs');
  ImportProgress _importProgress = ImportProgress.idle;
  Announcement? _pendingAnnouncement;
  bool _initialized = false;
  bool _busy = false;
  String? _message;

  bool get initialized => _initialized;
  bool get busy => _busy;
  String? get message => _message;
  AppPaths? get paths => _paths;
  ResourceManifest get manifest => _manifest;
  ResourceValidationResult get currentValidation => _currentValidation;
  ResourceValidationResult get importValidation => _importValidation;
  ImportProgress get importProgress => _importProgress;
  Announcement? get pendingAnnouncement => _pendingAnnouncement;
  ServerStatus get serverStatus => _server.status;
  bool get isImporting =>
      _importProgress.phase != ImportPhase.idle &&
      _importProgress.phase != ImportPhase.completed &&
      _importProgress.phase != ImportPhase.failed;
  bool get hasCurrentResource => _currentValidation.isValid;
  bool get hasValidImportSource => _importValidation.isValid;
  bool get canStartGame => hasCurrentResource;
  String get detectedTitle =>
      _currentValidation.detectedTitle ?? _manifest.detectedTitle ?? '未检测到标题';

  String get userVisibleRoot {
    final root = _paths?.root;
    if (root == null) {
      return resourceFolderName;
    }
    return '${root.parent.path}${Platform.pathSeparator}${p.basename(root.path)}';
  }

  Future<void> initialize() async {
    _busy = true;
    notifyListeners();
    try {
      _paths = await _pathsService.ensureInitialized();
      _manifestStore = ManifestStore(_paths!.manifestFile);
      _manifest = await _manifestStore!.read();
      _manifest = await _importService.recoverStartupTransaction(
        paths: _paths!,
        manifestStore: _manifestStore!,
      );
      await refresh();
      _initialized = true;
    } catch (error) {
      _message = '启动失败：$error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final paths = _requirePaths();
    final manifestStore = _requireManifestStore();
    _manifest = await manifestStore.read();
    _currentValidation = await _validator.validate(paths.currentDir);
    _importValidation = await _validator.validate(paths.importDocsDir);

    if (_currentValidation.isValid &&
        _manifest.resourceStatus == ResourceStatus.ready) {
      _currentValidation = _currentValidation.asReady();
    }

    notifyListeners();
  }

  Future<void> checkImportDirectory() async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      await refresh();
      if (_importValidation.isValid) {
        _message = '发现可导入资源：${_importValidation.detectedTitle}';
      } else {
        _message = _importValidation.errorMessage ?? 'import/docs 无效';
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshAnnouncement() async {
    final manifestStore = _requireManifestStore();
    final announcement = await _announcementService.fetchCurrentAnnouncement();
    _manifest = await manifestStore.read();

    if (announcement == null || _isAnnouncementDismissedToday(announcement)) {
      _pendingAnnouncement = null;
    } else {
      _pendingAnnouncement = announcement;
    }

    notifyListeners();
  }

  Future<void> dismissAnnouncement(Announcement announcement) async {
    final manifestStore = _requireManifestStore();
    _manifest = await manifestStore.read();
    _manifest = _manifest.copyWith(
      dismissedAnnouncementId: announcement.id,
      dismissedAnnouncementLocalDate: _todayLocalDate(),
    );
    await manifestStore.write(_manifest);
    if (_pendingAnnouncement?.id == announcement.id) {
      _pendingAnnouncement = null;
    }
    notifyListeners();
  }

  Future<void> importResources() async {
    final paths = _requirePaths();
    final manifestStore = _requireManifestStore();
    _message = null;
    _importProgress = const ImportProgress(phase: ImportPhase.validating);
    notifyListeners();

    try {
      _manifest = await _importService.importResources(
        paths: paths,
        manifestStore: manifestStore,
        onProgress: (progress) {
          _importProgress = progress;
          notifyListeners();
        },
      );
      _message = '导入成功，可自行删除 import/docs 节省空间';
      await refresh();
    } on ImportFailure catch (failure) {
      _message = failure.message;
      await refresh();
    } catch (error) {
      _message = '导入失败：$error';
      await refresh();
    }
  }

  Future<void> startGame() async {
    final paths = _requirePaths();
    _message = null;
    _currentValidation = await _validator.validate(paths.currentDir);
    if (!_currentValidation.isValid) {
      _message = _currentValidation.errorMessage ?? 'current 资源无效';
      notifyListeners();
      throw StateError(_message!);
    }
    await _server.start(root: paths.currentDir);
    notifyListeners();
  }

  Future<void> stopGame() async {
    await _server.stop();
    notifyListeners();
  }

  Future<bool> ensureServerAfterResume() async {
    if (_server.isRunning) {
      return false;
    }
    if (!canStartGame) {
      return false;
    }
    await _server.start(root: _requirePaths().currentDir);
    notifyListeners();
    return true;
  }

  DiagnosticSnapshot diagnostics({String? webViewEngineVersion}) {
    return _diagnosticsService.build(
      paths: _requirePaths(),
      currentValidation: _currentValidation,
      importValidation: _importValidation,
      manifest: _manifest,
      serverStatus: _server.status,
      webViewEngineVersion: webViewEngineVersion,
    );
  }

  void clearMessage() {
    _message = null;
    notifyListeners();
  }

  bool _isAnnouncementDismissedToday(Announcement announcement) {
    return _manifest.dismissedAnnouncementId == announcement.id &&
        _manifest.dismissedAnnouncementLocalDate == _todayLocalDate();
  }

  String _todayLocalDate() {
    final now = _now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  AppPaths _requirePaths() {
    final paths = _paths;
    if (paths == null) {
      throw StateError('AppPaths 尚未初始化');
    }
    return paths;
  }

  ManifestStore _requireManifestStore() {
    final manifestStore = _manifestStore;
    if (manifestStore == null) {
      throw StateError('ManifestStore 尚未初始化');
    }
    return manifestStore;
  }
}
