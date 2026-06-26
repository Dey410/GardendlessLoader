import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'constants.dart';
import 'models.dart';
import 'services/about_content_service.dart';
import 'services/announcement_service.dart';
import 'services/app_paths_service.dart';
import 'services/diagnostics_service.dart';
import 'services/import_service.dart';
import 'services/local_game_server.dart';
import 'services/manifest_store.dart';
import 'services/resource_validator.dart';
import 'services/resource_picker_service.dart';
import 'services/update_check_service.dart';

//AppController 是整个应用的核心控制器，负责管理应用的状态、处理业务逻辑，并与 UI 进行交互。它使用 ChangeNotifier 来通知 UI 更新。
class AppController extends ChangeNotifier {
  AppController({
    AppPathsService? pathsService,
    ResourceValidator? validator,
    LocalGameServer? server,
    ImportService? importService,
    DiagnosticsService? diagnosticsService,
    AnnouncementService? announcementService,
    AboutContentService? aboutContentService,
    UpdateCheckService? updateCheckService,
    ResourcePickerService? resourcePickerService,
  })  : _pathsService = pathsService ?? AppPathsService(),
        _validator = validator ?? ResourceValidator(),
        _server = server ?? LocalGameServer(),
        _diagnosticsService = diagnosticsService ?? DiagnosticsService(),
        _announcementService = announcementService ?? AnnouncementService(),
        _aboutContentService = aboutContentService ?? AboutContentService(),
        _updateCheckService = updateCheckService ?? UpdateCheckService(),
        _resourcePickerService =
            resourcePickerService ?? ResourcePickerService() {
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
  final AboutContentService _aboutContentService;
  final UpdateCheckService _updateCheckService;
  final ResourcePickerService _resourcePickerService;
  late final ImportService _importService;

  AppPaths? _paths;
  ManifestStore? _manifestStore;
  ResourceManifest _manifest = ResourceManifest.initial();
  ResourceValidationResult _currentValidation =
      ResourceValidationResult.missing('尚未检查 current');
  ResourceValidationResult _importValidation =
      ResourceValidationResult.missing('尚未选择 ZIP');
  ImportProgress _importProgress = ImportProgress.idle;
  Directory? _selectedImportSource;
  Announcement? _announcement;
  AboutContent _aboutContent = localFallbackAboutContent;
  UpdateInfo? _availableUpdate;
  String? _deferredUpdateTagName;
  String _currentAppVersion = appVersion;
  bool _updateCheckInProgress = false;
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
  Directory? get selectedImportSource => _selectedImportSource;
  Announcement? get announcement => _announcement;
  AboutContent get aboutContent => _aboutContent;
  UpdateInfo? get availableUpdate => _availableUpdate;
  String get currentAppVersion => _currentAppVersion;
  bool get updateCheckInProgress => _updateCheckInProgress;
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
//返回一个适合在 UI 中显示的资源根目录名称。如果路径信息不可用，则返回一个默认的资源文件夹名称。
  String get userVisibleRoot {
    final root = _paths?.root;
    if (root == null) {
      return resourceFolderName;
    }
    return '${root.parent.path}${Platform.pathSeparator}${p.basename(root.path)}';
  }

  String get userVisibleImportDocs {
    final selected = _selectedImportSource;
    if (selected != null) {
      return selected.path;
    }
    return '尚未选择 ZIP';
  }

//initialize 方法负责初始化应用的核心状态，包括加载路径信息、读取资源清单、恢复未完成的导入事务，并刷新公告信息。它会在整个过程中更新 busy 状态和 message，以便 UI 可以显示加载状态和错误信息。
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
      await _diagnosticsService.initialize();
      await _loadCurrentAppVersion();
      await refresh();
      _initialized = true;
    } catch (error) {
      _message = '启动失败：$error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

//refresh 方法负责刷新应用的状态，主要是重新验证资源目录的有效性，并更新公告信息。它会更新 currentValidation 和 importValidation 的结果，以便 UI 可以显示当前资源和导入资源的状态。
  Future<void> refresh() async {
    final paths = _requirePaths();
    final manifestStore = _requireManifestStore();
    _manifest = await manifestStore.read();
    _currentValidation = await _validator.validate(paths.currentDir);
    final selectedImportSource = _selectedImportSource;
    _importValidation = selectedImportSource == null
        ? ResourceValidationResult.missing('尚未选择 ZIP')
        : await _validator.validate(selectedImportSource);

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
      _message = _importValidation.isValid
          ? '发现可导入资源：${_importValidation.detectedTitle}'
          : _importValidation.errorMessage ?? 'docs 无效';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshAnnouncement() async {
    _announcement = await _announcementService.fetchCurrentAnnouncement();
    notifyListeners();
  }

  Future<void> refreshAboutContent() async {
    final paths = _requirePaths();
    _aboutContent = await _aboutContentService.refreshContent(
      cacheFile: File(p.join(paths.root.path, 'about_content.json')),
    );
    notifyListeners();
  }

  Future<void> checkForUpdates({bool silent = false}) async {
    _updateCheckInProgress = true;
    if (!silent) {
      _message = null;
    }
    notifyListeners();

    try {
      await _loadCurrentAppVersion();
      notifyListeners();
      final update = await _updateCheckService.checkForUpdate();
      if (update != null) {
        _currentAppVersion = update.currentVersion;
      }
      _availableUpdate =
          update?.tagName == _deferredUpdateTagName ? null : update;
      if (!silent && update == null) {
        _message = 'v$_currentAppVersion';
      }
    } catch (_) {
      _availableUpdate = null;
      if (!silent) {
        _message = '检查更新失败，请稍后重试';
      }
    } finally {
      _updateCheckInProgress = false;
      notifyListeners();
    }
  }

  Future<void> _loadCurrentAppVersion() async {
    _currentAppVersion = await _updateCheckService.loadCurrentVersion();
  }

  void deferUpdate(UpdateInfo update) {
    _deferredUpdateTagName = update.tagName;
    if (_availableUpdate?.tagName == update.tagName) {
      _availableUpdate = null;
    }
    notifyListeners();
  }

  Future<void> importResources() async {
    final paths = _requirePaths();
    final manifestStore = _requireManifestStore();
    _message = null;
    _busy = true;
    notifyListeners();

    try {
      final selectedSource = await _resourcePickerService.pickAndExtractDocsZip(
        initialDirectory: paths.importDir,
        localImportDocsDir: paths.importDocsDir,
      );
      if (selectedSource == null) {
        _message = '已取消选择 ZIP';
        return;
      }

      _selectedImportSource = selectedSource;
      _importValidation = ResourceValidationResult.missing('正在校验 docs');
      _importProgress = const ImportProgress(phase: ImportPhase.validating);
      notifyListeners();

      _manifest = await _importService.importResources(
        paths: paths,
        manifestStore: manifestStore,
        sourceDocsDir: selectedSource,
        onProgress: (progress) {
          _importProgress = progress;
          notifyListeners();
        },
      );
      _message = '导入成功';
      await refresh();
    } on ResourcePickerFailure catch (failure) {
      _message = failure.message;
    } on ImportFailure catch (failure) {
      _message = failure.message;
      await refresh();
    } catch (error) {
      _message = '导入失败：$error';
      await refresh();
    } finally {
      _busy = false;
      notifyListeners();
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
