import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'constants.dart';
import 'game_host/game_host.dart';
import 'game_host/game_session_store.dart';
import 'logging/app_logger.dart';
import 'models.dart';
import 'services/about_content_service.dart';
import 'services/announcement_service.dart';
import 'services/app_paths_service.dart';
import 'services/app_settings_store.dart';
import 'services/diagnostics_service.dart';
import 'services/game_update_check_service.dart';
import 'services/import_service.dart';
import 'services/import_progress_meter.dart';
import 'services/manifest_store.dart';
import 'services/resource_validator.dart';
import 'services/resource_picker_service.dart';
import 'services/update_check_service.dart';

typedef ImportAwakeModeSetter = Future<void> Function(bool enabled);
typedef ImportAwakeModeGetter = Future<bool> Function();

//AppController 是整个应用的核心控制器，负责管理应用的状态、处理业务逻辑，并与 UI 进行交互。它使用 ChangeNotifier 来通知 UI 更新。
class AppController extends ChangeNotifier {
  AppController({
    AppPathsService? pathsService,
    ResourceValidator? validator,
    ImportService? importService,
    GameHost? gameHost,
    GameHostPlatform? gameHostPlatform,
    String Function()? gameSessionIdFactory,
    AppLogger? appLogger,
    DiagnosticsService? diagnosticsService,
    AnnouncementService? announcementService,
    AboutContentService? aboutContentService,
    UpdateCheckService? updateCheckService,
    GameUpdateCheckService? gameUpdateCheckService,
    ResourcePickerService? resourcePickerService,
    ImportAwakeModeGetter? importAwakeModeGetter,
    ImportAwakeModeSetter? importAwakeModeSetter,
    Duration importCompletionVisibilityDuration = const Duration(seconds: 2),
    Duration importProgressTickInterval = const Duration(seconds: 1),
  })  : _pathsService = pathsService ?? AppPathsService(),
        _validator = validator ?? ResourceValidator(),
        _gameHost = gameHost ?? GameHostRouter.platformChannel(),
        _gameHostPlatform = gameHostPlatform,
        _gameSessionIdFactory = gameSessionIdFactory ?? _newGameSessionId,
        _appLogger = appLogger,
        _diagnosticsService = diagnosticsService ?? DiagnosticsService(),
        _announcementService = announcementService ?? AnnouncementService(),
        _aboutContentService = aboutContentService ?? AboutContentService(),
        _updateCheckService = updateCheckService ?? UpdateCheckService(),
        _gameUpdateCheckService =
            gameUpdateCheckService ?? GameUpdateCheckService(),
        _resourcePickerService =
            resourcePickerService ?? ResourcePickerService(),
        _importAwakeModeGetter =
            importAwakeModeGetter ?? _defaultImportAwakeModeGetter,
        _importAwakeModeSetter =
            importAwakeModeSetter ?? _defaultImportAwakeModeSetter,
        _importCompletionVisibilityDuration =
            importCompletionVisibilityDuration,
        _importProgressTickInterval = importProgressTickInterval {
    _importService = importService ??
        ImportService(
          validator: _validator,
          gameUpdateCheckService: _gameUpdateCheckService,
        );
  }

  final AppPathsService _pathsService;
  final ResourceValidator _validator;
  final GameHost _gameHost;
  final GameHostPlatform? _gameHostPlatform;
  final String Function() _gameSessionIdFactory;
  final AppLogger? _appLogger;
  final DiagnosticsService _diagnosticsService;
  final AnnouncementService _announcementService;
  final AboutContentService _aboutContentService;
  final UpdateCheckService _updateCheckService;
  final GameUpdateCheckService _gameUpdateCheckService;
  final ResourcePickerService _resourcePickerService;
  final ImportAwakeModeGetter _importAwakeModeGetter;
  final ImportAwakeModeSetter _importAwakeModeSetter;
  final Duration _importCompletionVisibilityDuration;
  final Duration _importProgressTickInterval;
  late final ImportService _importService;
  ImportProgressMeter? _importProgressMeter;
  Timer? _importCompletionTimer;
  Timer? _importProgressTickTimer;
  String? _activeImportOperationId;
  DateTime? _lastImportProgressLogAt;
  Future<void> _appSettingsWrite = Future<void>.value();
  Future<void> _manifestPreferenceWrite = Future<void>.value();

  AppPaths? _paths;
  AppSettingsStore? _appSettingsStore;
  ManifestStore? _manifestStore;
  GameSessionStore? _gameSessionStore;
  ResourceManifest _manifest = ResourceManifest.initial();
  ResourceValidationResult _currentValidation =
      ResourceValidationResult.missing('尚未检查激活槽');
  ResourceValidationResult _importValidation = ResourceValidationResult.missing(
    '尚未选择 ZIP',
  );
  ImportProgress _importProgress = ImportProgress.idle;
  Directory? _selectedImportSource;
  Announcement? _announcement;
  AboutContent _aboutContent = localFallbackAboutContent;
  UpdateInfo? _availableUpdate;
  GameUpdateInfo? _availableGameUpdate;
  String? _deferredUpdateTagName;
  String? _deferredGameUpdateTagName;
  String _currentAppVersion = appVersion;
  String? _currentGameVersion;
  String? _latestGameVersion;
  bool _currentGameVersionIsAhead = false;
  bool _appUpdateDetected = false;
  bool _gameUpdateDetected = false;
  bool _updateCheckInProgress = false;
  bool _watermarkEnabled = true;
  bool _initialized = false;
  bool _busy = false;
  String? _message;
  AppLogSnapshot? _logSnapshot;
  bool _logSnapshotLoading = false;

  bool get initialized => _initialized;
  bool get busy => _busy;
  String? get message => _message;
  AppLogSnapshot? get logSnapshot => _logSnapshot;
  bool get logSnapshotLoading => _logSnapshotLoading;
  AppPaths? get paths => _paths;
  ResourceManifest get manifest => _manifest;
  ResourceValidationResult get currentValidation => _currentValidation;
  ResourceValidationResult get importValidation => _importValidation;
  ImportProgress get importProgress => _importProgress;
  Directory? get selectedImportSource => _selectedImportSource;
  Announcement? get announcement => _announcement;
  AboutContent get aboutContent => _aboutContent;
  UpdateInfo? get availableUpdate => _availableUpdate;
  GameUpdateInfo? get availableGameUpdate => _availableGameUpdate;
  String get currentAppVersion => _currentAppVersion;
  String? get currentGameVersion => _currentGameVersion;
  String? get latestGameVersion => _latestGameVersion;
  bool get updateCheckInProgress => _updateCheckInProgress;
  bool get watermarkEnabled => _watermarkEnabled;
  bool get autoCollectSunEnabled => _manifest.autoCollectSunEnabled;
  GameHostPlatform get gameHostPlatform {
    final configured = _gameHostPlatform;
    if (configured != null) {
      return configured;
    }
    try {
      return GameHostPlatform.current();
    } on UnsupportedError {
      GameHostPlatform? testFallback;
      assert(() {
        testFallback = GameHostPlatform.android;
        return true;
      }());
      if (testFallback != null) {
        return testFallback!;
      }
      rethrow;
    }
  }

  bool get isImporting =>
      _importProgress.phase != ImportPhase.idle &&
      _importProgress.phase != ImportPhase.completed &&
      _importProgress.phase != ImportPhase.failed;
  bool get hasCurrentResource => _currentValidation.isValid;
  bool get hasGpNext =>
      hasCurrentResource &&
      (_currentValidation.isValid
          ? _currentValidation.hasGpNext
          : _manifest.hasGpNext);
  bool get gpNextCompatible =>
      hasGpNext &&
      (_currentValidation.isValid
          ? _currentValidation.gpNextCompatible
          : _manifest.gpNextCompatible);
  String? get gpNextVersion =>
      _currentValidation.gpNextVersion ?? _manifest.gpNextVersion;
  String? get gpNextCompatibilityError =>
      _currentValidation.gpNextCompatibilityError ??
      _manifest.gpNextCompatibilityError;
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
      Future<void> initializeCore() async {
        _emitInitializationStage('paths');
        _paths = await _pathsService.ensureInitialized();
        _emitInitializationStage('game_session_recovery');
        _gameSessionStore = GameSessionStore(_paths!.root);
        final exitResult = await _gameSessionStore!.consumeExitResult();
        _emitInitializationStage('settings');
        _appSettingsStore = AppSettingsStore(_paths!.appSettingsFile);
        _watermarkEnabled = await _appSettingsStore!.readWatermarkEnabled();
        _emitInitializationStage('manifest');
        _manifestStore = ManifestStore(_paths!.manifestFile);
        _manifest = await _manifestStore!.read();
        final interruptedTransaction =
            _manifest.transactionState != TransactionState.idle;
        final recoveryOperationId =
            interruptedTransaction ? _newOperationId('import-recovery') : null;
        if (interruptedTransaction) {
          _appLogger?.emit(
            level: LogLevel.warn,
            category: 'resource.import',
            event: 'import_transaction_recovery_started',
            outcome: LogOutcome.started,
            operationId: recoveryOperationId,
            context: <String, Object?>{
              'transactionState': _manifest.transactionState.name,
              'targetSlot': _manifest.transactionSlot?.name ?? 'none',
            },
          );
        }
        try {
          _manifest = await _importService.recoverStartupTransaction(
            paths: _paths!,
            manifestStore: _manifestStore!,
          );
          if (interruptedTransaction) {
            _appLogger?.emit(
              level: LogLevel.info,
              category: 'resource.import',
              event: 'import_transaction_recovery_finished',
              outcome: LogOutcome.succeeded,
              operationId: recoveryOperationId,
              context: <String, Object?>{
                'recoveryAction': _manifest.transactionState ==
                        TransactionState.cleaningOldSlot
                    ? 'cleanup_deferred'
                    : 'transaction_reconciled',
                'activeSlot': _manifest.activeSlot?.name ?? 'none',
                'currentResourceUsable': _manifest.activeSlot != null,
              },
            );
          }
        } catch (error, stackTrace) {
          _appLogger?.emit(
            level: LogLevel.error,
            category: 'resource.import',
            event: 'import_transaction_recovery_finished',
            outcome: LogOutcome.failed,
            code: 'import_transaction_recovery_failed',
            operationId: recoveryOperationId,
            error: error,
            stackTrace: stackTrace,
          );
          rethrow;
        }
        _emitInitializationStage('diagnostics');
        await _diagnosticsService.initialize();
        await _loadCurrentAppVersion();
        _emitInitializationStage('resource_validation');
        await refresh();
        if (_manifest.transactionState == TransactionState.cleaningOldSlot) {
          _message = '游戏资源可用，旧槽清理将在下次启动重试';
        } else if (interruptedTransaction) {
          _message = '上次导入意外中断，已清理未完成文件';
        } else if (exitResult?.reason == GameExitReason.rendererGone) {
          _message = exitResult?.message ?? '游戏渲染进程已退出';
        } else if (exitResult?.reason == GameExitReason.launchFailed) {
          _message = exitResult?.message ?? '原生游戏宿主启动失败';
        }
        _initialized = true;
      }

      final operation = _appLogger?.startOperation(
        operationId: 'app-initialize',
        category: 'app.lifecycle',
        startedEvent: 'app_initialization_started',
        finishedEvent: 'app_initialization_finished',
        failureCode: 'app_initialization_failed',
      );
      if (operation == null) {
        await initializeCore();
      } else {
        await operation.run(initializeCore);
      }
    } catch (error) {
      _message = '启动失败：$error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // 统一从 manifest 指向的激活槽刷新资源状态和游戏版本。
  Future<void> refresh() async {
    final paths = _requirePaths();
    final manifestStore = _requireManifestStore();
    _manifest = await manifestStore.read();
    final activeDirectory = _importService.activeDirectory(paths, _manifest);
    _currentValidation = activeDirectory == null
        ? ResourceValidationResult.missing('尚未导入游戏资源')
        : await _validator.validate(activeDirectory);
    final selectedImportSource = _selectedImportSource;
    _importValidation = selectedImportSource == null
        ? ResourceValidationResult.missing('尚未选择 ZIP')
        : await _validator.validate(selectedImportSource);

    if (_currentValidation.isValid &&
        _manifest.resourceStatus == ResourceStatus.ready) {
      _currentValidation = _currentValidation.asReady();
    }

    _currentGameVersion = _currentValidation.isValid
        ? await _gameUpdateCheckService.loadCurrentVersion(activeDirectory!)
        : null;
    if (_currentGameVersion == null) {
      _availableGameUpdate = null;
      _currentGameVersionIsAhead = false;
      _gameUpdateDetected = false;
    }
    final compatibilityMetadataChanged = _currentValidation.isValid &&
        (_manifest.buildProfile != _currentValidation.buildProfile ||
            _manifest.gpNextVersion != _currentValidation.gpNextVersion ||
            _manifest.gpNextCompatibilityError !=
                _currentValidation.gpNextCompatibilityError);
    if (_manifest.gameVersion != _currentGameVersion ||
        compatibilityMetadataChanged) {
      _manifest = _manifest.copyWith(
        gameVersion: _currentGameVersion,
        clearGameVersion: _currentGameVersion == null,
        buildProfile: _currentValidation.isValid
            ? _currentValidation.buildProfile
            : _manifest.buildProfile,
        gpNextVersion: _currentValidation.gpNextVersion,
        gpNextCompatibilityError: _currentValidation.gpNextCompatibilityError,
        clearGpNextVersion: _currentValidation.isValid &&
            _currentValidation.gpNextVersion == null,
        clearGpNextCompatibilityError: _currentValidation.isValid &&
            _currentValidation.gpNextCompatibilityError == null,
      );
      await manifestStore.write(_manifest);
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
      final results = await Future.wait([
        _checkAppForUpdate(),
        _checkGameForUpdate(),
      ]);
      if (!silent) {
        final appSucceeded = results[0];
        final gameSucceeded = results[1];
        if (!appSucceeded && !gameSucceeded) {
          _message = '加载器和游戏更新检查失败，请稍后重试';
        } else if (!appSucceeded) {
          _message = '加载器更新检查失败，请稍后重试';
        } else if (!gameSucceeded) {
          _message = '游戏更新检查失败，请稍后重试';
        } else if (!_appUpdateDetected && !_gameUpdateDetected) {
          final currentGameVersion = _currentGameVersion;
          if (currentGameVersion == null) {
            final gameState = hasCurrentResource ? '游戏版本未知' : '游戏资源尚未导入';
            _message = '加载器 v$_currentAppVersion 已是最新；'
                '$gameState，当前稳定版 $_latestGameVersion';
          } else if (_currentGameVersionIsAhead) {
            _message = '加载器 v$_currentAppVersion 已是最新；本地游戏 '
                '$currentGameVersion 高于公开稳定版 $_latestGameVersion';
          } else {
            _message = '加载器 v$_currentAppVersion 与游戏 '
                '$currentGameVersion 均为最新版';
          }
        }
      }
    } finally {
      _updateCheckInProgress = false;
      notifyListeners();
    }
  }

  Future<bool> _checkAppForUpdate() async {
    try {
      final update = await _updateCheckService.checkForUpdate();
      if (update != null) {
        _currentAppVersion = update.currentVersion;
      }
      _appUpdateDetected = update != null;
      _availableUpdate =
          update?.tagName == _deferredUpdateTagName ? null : update;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkGameForUpdate({bool reuseLatestVersion = false}) async {
    final currentGameVersion = _currentGameVersion;
    if (currentGameVersion == null) {
      try {
        _latestGameVersion = await _gameUpdateCheckService.loadLatestVersion();
        _availableGameUpdate = null;
        _gameUpdateDetected = false;
        return true;
      } catch (_) {
        return false;
      }
    }
    try {
      final result = await _gameUpdateCheckService.check(
        currentVersion: currentGameVersion,
        latestVersion: reuseLatestVersion ? _latestGameVersion : null,
      );
      final update = result.update;
      _latestGameVersion = result.latestVersion;
      _currentGameVersionIsAhead = result.currentIsAhead;
      _gameUpdateDetected = update != null;
      _availableGameUpdate =
          update?.tagName == _deferredGameUpdateTagName ? null : update;
      return true;
    } catch (_) {
      return false;
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

  void deferGameUpdate(GameUpdateInfo update) {
    _deferredGameUpdateTagName = update.tagName;
    if (_availableGameUpdate?.tagName == update.tagName) {
      _availableGameUpdate = null;
    }
    notifyListeners();
  }

  Future<void> importResources() async {
    final paths = _requirePaths();
    final manifestStore = _requireManifestStore();
    _message = null;
    _busy = true;
    _importCompletionTimer?.cancel();
    _importProgress = ImportProgress.idle;
    _importProgressMeter = ImportProgressMeter();
    _startImportProgressTicker();
    notifyListeners();

    final operationId = _newOperationId('resource-import');
    _activeImportOperationId = operationId;
    _lastImportProgressLogAt = null;
    final importStopwatch = Stopwatch()..start();
    _appLogger?.emit(
      level: LogLevel.info,
      category: 'resource.import',
      event: 'resource_import_started',
      outcome: LogOutcome.started,
      operationId: operationId,
    );

    var restoreAwakeModeAfterImport = false;
    ImportTarget? importTarget;
    try {
      restoreAwakeModeAfterImport = await _keepScreenAwakeForImport();
      importTarget = await _importService.beginImport(
        paths: paths,
        manifestStore: manifestStore,
      );
      _appLogger?.emit(
        level: LogLevel.info,
        category: 'resource.import',
        event: 'resource_import_target_prepared',
        outcome: LogOutcome.succeeded,
        operationId: operationId,
        context: <String, Object?>{'targetSlot': importTarget.slot.name},
      );
      _message = '正在打开系统文件选择器';
      notifyListeners();
      _appLogger?.emit(
        level: LogLevel.info,
        category: 'resource.import',
        event: 'resource_import_picker_started',
        outcome: LogOutcome.started,
        operationId: operationId,
      );
      final selectedSource = await _resourcePickerService.pickAndExtractDocsZip(
        targetDirectory: importTarget.directory,
        onProgress: _updateImportProgress,
      );
      if (selectedSource == null) {
        _appLogger?.emit(
          level: LogLevel.info,
          category: 'resource.import',
          event: 'resource_import_picker_finished',
          outcome: LogOutcome.cancelled,
          operationId: operationId,
          context: const <String, Object?>{'stage': 'cancelled'},
        );
        _manifest = await _importService.abortImport(
          paths: paths,
          manifestStore: manifestStore,
        );
        importTarget = null;
        _message = '已取消选择 ZIP';
        _appLogger?.emit(
          level: LogLevel.info,
          category: 'resource.import',
          event: 'resource_import_finished',
          outcome: LogOutcome.cancelled,
          operationId: operationId,
          durationMs: importStopwatch.elapsedMilliseconds,
          context: const <String, Object?>{'stage': 'picking'},
        );
        return;
      }

      _appLogger?.emit(
        level: LogLevel.info,
        category: 'resource.import',
        event: 'resource_import_picker_finished',
        outcome: LogOutcome.succeeded,
        operationId: operationId,
        context: const <String, Object?>{'stage': 'extracted'},
      );

      _selectedImportSource = selectedSource;
      _importValidation = ResourceValidationResult.missing('正在校验 docs');
      _updateImportProgress(
        const ImportProgress(phase: ImportPhase.validating, message: '正在校验资源'),
      );
      _appLogger?.emit(
        level: LogLevel.info,
        category: 'resource.validation',
        event: 'resource_validation_started',
        outcome: LogOutcome.started,
        operationId: operationId,
      );

      _manifest = await _importService.completeImport(
        paths: paths,
        manifestStore: manifestStore,
        target: importTarget,
        onProgress: _updateImportProgress,
      );
      importTarget = null;
      _appLogger?.emit(
        level: LogLevel.info,
        category: 'resource.validation',
        event: 'resource_validation_finished',
        outcome: LogOutcome.succeeded,
        operationId: operationId,
        context: <String, Object?>{
          'fileCount': _manifest.fileCount,
          'totalBytes': _manifest.totalBytes,
          'buildProfile': _manifest.buildProfile.name,
          'gpNextVersion': _manifest.gpNextVersion ?? 'none',
        },
      );
      _appLogger?.emit(
        level: LogLevel.info,
        category: 'resource.import',
        event: 'resource_slot_activated',
        outcome: LogOutcome.succeeded,
        operationId: operationId,
        context: <String, Object?>{
          'activeSlot': _manifest.activeSlot?.name ?? 'none',
          'cleanupDeferred':
              _manifest.transactionState == TransactionState.cleaningOldSlot,
        },
      );
      _message = _manifest.transactionState == TransactionState.cleaningOldSlot
          ? '导入成功，旧槽清理将在下次启动重试'
          : '导入成功';
      _importProgressTickTimer?.cancel();
      _scheduleCompletedProgressReset();
      if (restoreAwakeModeAfterImport) {
        await _setImportAwakeMode(false);
        restoreAwakeModeAfterImport = false;
      }
      await refresh();
      await _checkGameForUpdate(reuseLatestVersion: true);
      _appLogger?.emit(
        level: LogLevel.info,
        category: 'resource.import',
        event: 'resource_import_finished',
        outcome: LogOutcome.succeeded,
        operationId: operationId,
        durationMs: importStopwatch.elapsedMilliseconds,
        context: <String, Object?>{
          'stage': 'completed',
          'activeSlot': _manifest.activeSlot?.name ?? 'none',
          'fileCount': _manifest.fileCount,
          'totalBytes': _manifest.totalBytes,
        },
      );
    } on ResourcePickerFailure catch (failure) {
      _appLogger?.emit(
        level: LogLevel.error,
        category: 'resource.import',
        event: 'resource_import_picker_finished',
        outcome: LogOutcome.failed,
        code: failure.code,
        operationId: operationId,
        error: failure,
        stackTrace: StackTrace.current,
      );
      if (importTarget != null) {
        _manifest = await _importService.abortImport(
          paths: paths,
          manifestStore: manifestStore,
        );
        importTarget = null;
      }
      _message = failure.message;
      _updateImportProgress(
        ImportProgress(phase: ImportPhase.failed, message: failure.message),
      );
      _appLogger?.emit(
        level: LogLevel.error,
        category: 'resource.import',
        event: 'resource_import_finished',
        outcome: LogOutcome.failed,
        code: failure.code,
        operationId: operationId,
        durationMs: importStopwatch.elapsedMilliseconds,
        error: failure,
        stackTrace: StackTrace.current,
      );
    } on ImportFailure catch (failure) {
      _message = failure.message;
      await refresh();
      _appLogger?.emit(
        level: LogLevel.error,
        category: 'resource.validation',
        event: 'resource_validation_finished',
        outcome: LogOutcome.failed,
        code: failure.code,
        operationId: operationId,
        context: <String, Object?>{'stage': _importProgress.phase.name},
        error: failure,
        stackTrace: StackTrace.current,
      );
      _appLogger?.emit(
        level: LogLevel.error,
        category: 'resource.import',
        event: 'resource_import_finished',
        outcome: LogOutcome.failed,
        code: failure.code,
        operationId: operationId,
        durationMs: importStopwatch.elapsedMilliseconds,
        error: failure,
        stackTrace: StackTrace.current,
      );
    } catch (error) {
      if (importTarget != null) {
        _manifest = await _importService.abortImport(
          paths: paths,
          manifestStore: manifestStore,
        );
        importTarget = null;
      }
      _message = '导入失败：$error';
      _updateImportProgress(
        ImportProgress(phase: ImportPhase.failed, message: _message),
      );
      await refresh();
      _appLogger?.emit(
        level: LogLevel.error,
        category: 'resource.import',
        event: 'resource_import_finished',
        outcome: LogOutcome.failed,
        code: 'import_extract_failed',
        operationId: operationId,
        durationMs: importStopwatch.elapsedMilliseconds,
        error: error,
        stackTrace: StackTrace.current,
      );
    } finally {
      _importProgressTickTimer?.cancel();
      if (restoreAwakeModeAfterImport) {
        await _setImportAwakeMode(false);
      }
      _busy = false;
      _activeImportOperationId = null;
      notifyListeners();
    }
  }

  void _updateImportProgress(ImportProgress progress) {
    final meter = _importProgressMeter ??= ImportProgressMeter();
    _importProgress = meter.measure(progress);
    final now = DateTime.now();
    final lastLogAt = _lastImportProgressLogAt;
    if (lastLogAt == null ||
        now.difference(lastLogAt) >= const Duration(seconds: 1)) {
      _lastImportProgressLogAt = now;
      _appLogger?.emit(
        level: LogLevel.debug,
        category: 'resource.import',
        event: 'resource_import_progress',
        outcome: LogOutcome.observed,
        operationId: _activeImportOperationId,
        context: <String, Object?>{
          'stage': progress.phase.name,
          'processedBytes': progress.copiedBytes,
          'totalBytes': progress.totalBytes,
          'processedFiles': progress.copiedFiles,
          'totalFiles': progress.totalFiles,
        },
      );
    }
    notifyListeners();
  }

  void _startImportProgressTicker() {
    _importProgressTickTimer?.cancel();
    _importProgressTickTimer = Timer.periodic(_importProgressTickInterval, (_) {
      if (isImporting) {
        _updateImportProgress(_importProgress);
      }
    });
  }

  void dismissImportProgress() {
    if (isImporting || _importProgress.phase == ImportPhase.idle) {
      return;
    }
    _importCompletionTimer?.cancel();
    _importProgress = ImportProgress.idle;
    notifyListeners();
  }

  Future<void> _setImportAwakeMode(bool enabled) async {
    try {
      await _importAwakeModeSetter(enabled);
    } catch (_) {
      // Import progress remains functional when a platform cannot toggle wakelock.
    }
  }

  Future<bool> _keepScreenAwakeForImport() async {
    var alreadyEnabled = false;
    try {
      alreadyEnabled = await _importAwakeModeGetter();
    } catch (_) {
      // Query failures fall back to the normal enable/disable import lifecycle.
    }
    if (alreadyEnabled) {
      return false;
    }
    await _setImportAwakeMode(true);
    return true;
  }

  static Future<bool> _defaultImportAwakeModeGetter() {
    return WakelockPlus.enabled;
  }

  static Future<void> _defaultImportAwakeModeSetter(bool enabled) {
    return enabled ? WakelockPlus.enable() : WakelockPlus.disable();
  }

  void _scheduleCompletedProgressReset() {
    _importCompletionTimer?.cancel();
    _importCompletionTimer = Timer(_importCompletionVisibilityDuration, () {
      if (_importProgress.phase != ImportPhase.completed) {
        return;
      }
      _importProgress = ImportProgress.idle;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _importCompletionTimer?.cancel();
    _importProgressTickTimer?.cancel();
    super.dispose();
  }

  Future<void> startGame() async {
    final paths = _requirePaths();
    _message = null;
    final activeDirectory = _importService.activeDirectory(paths, _manifest);
    _currentValidation = activeDirectory == null
        ? ResourceValidationResult.missing('尚未导入游戏资源')
        : await _validator.validate(activeDirectory);
    if (!_currentValidation.isValid) {
      _message = _currentValidation.errorMessage ?? '激活槽资源无效';
      notifyListeners();
      _appLogger?.emit(
        level: LogLevel.error,
        category: 'game.host',
        event: 'game_host_launch_finished',
        outcome: LogOutcome.failed,
        code: 'resource_validation_failed',
        message: _message,
      );
      throw StateError(_message!);
    }
    final exportRoot = Directory(p.join(paths.gpNextDir.path, '.exports'));
    await exportRoot.create(recursive: true);
    final session = GameSession(
      sessionId: _gameSessionIdFactory(),
      resourceRoot: activeDirectory!.path,
      platform: gameHostPlatform,
      entryPath: 'index.html',
      activationGeneration: _manifest.generation,
      hasGpNext: hasGpNext,
      gpNextCompatible: gpNextCompatible,
      gpNextVersion: gpNextVersion,
      watermarkEnabled: _watermarkEnabled,
      autoCollectSunEnabled: _manifest.autoCollectSunEnabled,
      allowedRemoteHosts: hasGpNext
          ? const ['pvzge.com', 'github.com', 'discord.gg']
          : const [],
      gpNextRoot: paths.gpNextDir.path,
      exportTemporaryRoot: exportRoot.path,
    );
    final store = _gameSessionStore ??= GameSessionStore(paths.root);
    Future<void> launch() async {
      await store.prepare(session);
      _importCompletionTimer?.cancel();
      _importProgressTickTimer?.cancel();
      await _gameHost.launch(session);
    }

    final operation = _appLogger?.startOperation(
      operationId: _newOperationId('game-launch'),
      category: 'game.host',
      startedEvent: 'game_host_launch_started',
      finishedEvent: 'game_host_launch_finished',
      failureCode: 'game_host_launch_failed',
      gameSessionId: session.sessionId,
    );
    if (operation == null) {
      await launch();
    } else {
      await operation.run(launch);
    }
  }

  static String _newOperationId(String prefix) =>
      '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}';

  void _emitInitializationStage(String stage) {
    _appLogger?.emit(
      level: LogLevel.debug,
      category: 'app.lifecycle',
      event: 'app_initialization_stage_changed',
      outcome: LogOutcome.observed,
      operationId: 'app-initialize',
      context: <String, Object?>{'stage': stage},
    );
  }

  DiagnosticSnapshot diagnostics({String? webViewEngineVersion}) {
    return _diagnosticsService.build(
      paths: _requirePaths(),
      currentValidation: _currentValidation,
      importValidation: _importValidation,
      manifest: _manifest,
      gameHostPlatform: gameHostPlatform,
      webViewEngineVersion: webViewEngineVersion,
    );
  }

  Future<void> refreshLogs() async {
    final logger = _appLogger;
    if (logger == null || _logSnapshotLoading) {
      return;
    }
    _logSnapshotLoading = true;
    notifyListeners();
    try {
      _logSnapshot = await logger.loadSnapshot();
    } finally {
      _logSnapshotLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteLogHistory() async {
    final logger = _appLogger;
    if (logger == null) {
      return;
    }
    await logger.deleteHistory();
    await refreshLogs();
  }

  String buildLogText({String minimumLevel = 'INFO', bool errorsOnly = false}) {
    final snapshot = _logSnapshot;
    final buffer = StringBuffer(diagnostics().toLogText());
    if (snapshot == null) {
      buffer.writeln('\nstructuredLogs: unavailable');
      return buffer.toString();
    }
    buffer
      ..writeln('\nappSessionId: ${snapshot.appSessionId}')
      ..writeln('logPersisting: ${snapshot.persisting}')
      ..writeln('logDegraded: ${snapshot.degraded}')
      ..writeln('logDirectory: ${snapshot.logDirectory ?? 'unavailable'}')
      ..writeln('logBytes: ${snapshot.totalBytes}')
      ..writeln('logWriteFailures: ${snapshot.writeFailureCount}')
      ..writeln('logDropped: ${jsonEncode(snapshot.droppedByLevel)}')
      ..writeln('\nrecent events:');
    const ranks = <String, int>{
      'DEBUG': 0,
      'INFO': 1,
      'WARN': 2,
      'ERROR': 3,
      'FATAL': 4,
    };
    final minimumRank = ranks[minimumLevel] ?? 1;
    for (final event in snapshot.events) {
      final level = event['level']?.toString().toUpperCase() ?? 'INFO';
      if ((ranks[level] ?? 1) < minimumRank) {
        continue;
      }
      if (errorsOnly && level != 'ERROR' && level != 'FATAL') {
        continue;
      }
      buffer.writeln(jsonEncode(event));
    }
    return buffer.toString();
  }

  String buildDiagnosticSummary() {
    final buffer = StringBuffer(diagnostics().toCopyText());
    final snapshot = _logSnapshot;
    if (snapshot == null) {
      return buffer.toString();
    }
    buffer
      ..writeln()
      ..writeln('Structured logs:')
      ..writeln('appSessionId: ${snapshot.appSessionId}')
      ..writeln('persisting: ${snapshot.persisting}')
      ..writeln('degraded: ${snapshot.degraded}')
      ..writeln('writeFailures: ${snapshot.writeFailureCount}');
    for (final event in snapshot.events) {
      buffer.writeln(jsonEncode(event));
    }
    return buffer.toString();
  }

  void clearMessage() {
    _message = null;
    notifyListeners();
  }

  Future<void> setWatermarkEnabled(bool enabled) async {
    if (_watermarkEnabled == enabled) {
      return;
    }
    final appSettingsStore = _appSettingsStore;
    if (appSettingsStore == null) {
      throw StateError('AppSettingsStore 尚未初始化');
    }

    _watermarkEnabled = enabled;
    notifyListeners();
    final previousWrite = _appSettingsWrite;
    final currentWrite = () async {
      try {
        await previousWrite;
      } catch (_) {
        // A later choice must still be persisted after an earlier write fails.
      }
      await appSettingsStore.writeWatermarkEnabled(enabled);
    }();
    _appSettingsWrite = currentWrite;
    await currentWrite;
  }

  Future<void> setAutoCollectSunEnabled(bool enabled) async {
    if (_manifest.autoCollectSunEnabled == enabled) {
      return;
    }
    final manifestStore = _requireManifestStore();
    _manifest = _manifest.copyWith(autoCollectSunEnabled: enabled);
    final manifest = _manifest;
    notifyListeners();
    final previousWrite = _manifestPreferenceWrite;
    final currentWrite = () async {
      try {
        await previousWrite;
      } catch (_) {
        // A later choice must still be persisted after an earlier write fails.
      }
      await manifestStore.write(manifest);
    }();
    _manifestPreferenceWrite = currentWrite;
    await currentWrite;
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

String _newGameSessionId() {
  return '${DateTime.now().toUtc().microsecondsSinceEpoch}-${pid.toRadixString(16)}';
}
