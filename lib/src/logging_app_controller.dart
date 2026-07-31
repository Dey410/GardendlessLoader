import 'dart:async';
import 'dart:io';

import 'app_controller.dart';
import 'models.dart';
import 'services/app_logger.dart';

class LoggingAppController extends AppController {
  LoggingAppController({AppLogger? logger})
      : _logger = logger ?? AppLogger.instance,
        super() {
    _lastImportPhase = importProgress.phase;
    _lastServerStatus = serverStatus;
    _lastMessage = message;
    _lastValidationSignature = _validationSignature(currentValidation);
    addListener(_captureStateChanges);
    _logSubscription = _logger.entries.listen(_scheduleDiagnosticsRefresh);
  }

  final AppLogger _logger;
  StreamSubscription<AppLogEntry>? _logSubscription;
  Timer? _logRefreshTimer;
  late ImportPhase _lastImportPhase;
  late ServerStatus _lastServerStatus;
  String? _lastMessage;
  late String _lastValidationSignature;
  bool _lastBusy = false;
  bool _lastInitialized = false;
  bool _disposed = false;

  AppLogger get logger => _logger;
  AppLogStatistics get logStatistics => _logger.statistics;

  List<AppLogEntry> queryLogs(AppLogQuery query) => _logger.query(query);

  Future<void> clearLogs({bool clearMemory = true}) {
    return _logger.clear(clearMemory: clearMemory);
  }

  Future<File> exportDiagnosticsBundle({String? webViewEngineVersion}) {
    return _logger.createSupportBundle(
      diagnosticsText: diagnostics(
        webViewEngineVersion: webViewEngineVersion,
      ).toCopyText(),
    );
  }

  @override
  Future<void> initialize() async {
    final operation = _logger.beginOperation(
      'app.initialize',
      'Application initialization',
      data: <String, Object?>{'controller': runtimeType.toString()},
    );
    try {
      await _logger.runWithContext(
        <String, Object?>{'parentOperationId': operation.operationId},
        () => super.initialize(),
      );
      if (initialized) {
        operation.complete(
          data: <String, Object?>{
            'resourceStatus': currentValidation.status.name,
            'serverStatus': serverStatus.name,
            'transactionState': manifest.transactionState.name,
          },
        );
      } else {
        operation.fail(
          StateError(message ?? 'Application initialization did not complete'),
          StackTrace.current,
          code: 'app_initialization_failed',
          level: AppLogLevel.fatal,
          data: <String, Object?>{'userMessage': message},
        );
      }
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'app_initialization_uncaught',
        level: AppLogLevel.fatal,
      );
      rethrow;
    }
  }

  @override
  Future<void> refresh() async {
    final operation = _logger.beginOperation(
      'resource.refresh',
      'Resource state refresh',
      data: <String, Object?>{
        'selectedImportPath': selectedImportSource?.path,
      },
    );
    try {
      await super.refresh();
      operation.complete(
        data: <String, Object?>{
          'activeStatus': currentValidation.status.name,
          'activeErrorCode': currentValidation.errorCode,
          'importStatus': importValidation.status.name,
          'importErrorCode': importValidation.errorCode,
          'gameVersion': currentGameVersion,
          'buildProfile': currentValidation.buildProfile.name,
        },
      );
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'resource_refresh_failed',
      );
      rethrow;
    }
  }

  @override
  Future<void> checkImportDirectory() async {
    final operation = _logger.beginOperation(
      'resource.import_check',
      'Import source validation',
    );
    try {
      await super.checkImportDirectory();
      final valid = importValidation.isValid;
      if (valid) {
        operation.complete(
          data: <String, Object?>{
            'detectedTitle': importValidation.detectedTitle,
            'buildProfile': importValidation.buildProfile.name,
          },
        );
      } else {
        operation.fail(
          StateError(importValidation.errorMessage ?? 'Import source is invalid'),
          StackTrace.current,
          code: importValidation.errorCode ?? 'import_source_invalid',
          level: AppLogLevel.warning,
        );
      }
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'import_source_check_failed',
      );
      rethrow;
    }
  }

  @override
  Future<void> refreshAnnouncement() async {
    final operation = _logger.beginOperation(
      'content.announcement',
      'Announcement refresh',
    );
    try {
      await super.refreshAnnouncement();
      operation.complete(
        data: <String, Object?>{
          'announcementId': announcement?.id,
          'hasAnnouncement': announcement != null,
        },
      );
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'announcement_refresh_failed',
        level: AppLogLevel.warning,
      );
      rethrow;
    }
  }

  @override
  Future<void> refreshAboutContent() async {
    final operation = _logger.beginOperation(
      'content.about',
      'About content refresh',
    );
    try {
      await super.refreshAboutContent();
      operation.complete(
        data: <String, Object?>{
          'contentVersion': aboutContent.contentVersion,
          'contentLength': aboutContent.content.length,
        },
      );
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'about_content_refresh_failed',
        level: AppLogLevel.warning,
      );
      rethrow;
    }
  }

  @override
  Future<void> checkForUpdates({bool silent = false}) async {
    final operation = _logger.beginOperation(
      'update.check',
      'Application and game update check',
      data: <String, Object?>{
        'silent': silent,
        'currentAppVersion': currentAppVersion,
        'currentGameVersion': currentGameVersion,
      },
    );
    try {
      await super.checkForUpdates(silent: silent);
      final resultMessage = message;
      if (resultMessage != null && resultMessage.contains('失败')) {
        operation.fail(
          StateError(resultMessage),
          StackTrace.current,
          code: 'update_check_partial_failure',
          level: AppLogLevel.warning,
          data: <String, Object?>{
            'userMessage': resultMessage,
            'latestGameVersion': latestGameVersion,
          },
        );
      } else {
        operation.complete(
          data: <String, Object?>{
            'availableAppVersion': availableUpdate?.latestVersion,
            'availableGameVersion': availableGameUpdate?.latestVersion,
            'latestGameVersion': latestGameVersion,
          },
        );
      }
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'update_check_failed',
      );
      rethrow;
    }
  }

  @override
  Future<void> importResources() async {
    final operation = _logger.beginOperation(
      'resource.import',
      'Resource import',
      data: <String, Object?>{
        'activeSlot': manifest.activeSlot?.name,
        'transactionState': manifest.transactionState.name,
      },
    );
    try {
      await _logger.runWithContext(
        <String, Object?>{'parentOperationId': operation.operationId},
        () => super.importResources(),
      );
      if (importProgress.phase == ImportPhase.failed) {
        operation.fail(
          StateError(
            manifest.lastErrorMessage ??
                importProgress.message ??
                message ??
                'Resource import failed',
          ),
          StackTrace.current,
          code: manifest.lastErrorCode ?? 'resource_import_failed',
          data: <String, Object?>{
            'phase': importProgress.phase.name,
            'userMessage': message,
          },
        );
      } else if (message == '已取消选择 ZIP') {
        operation.complete(
          message: 'Resource import cancelled',
          data: <String, Object?>{'cancelled': true},
        );
      } else {
        operation.complete(
          data: <String, Object?>{
            'activeSlot': manifest.activeSlot?.name,
            'transactionState': manifest.transactionState.name,
            'fileCount': manifest.fileCount,
            'totalBytes': manifest.totalBytes,
            'detectedTitle': manifest.detectedTitle,
            'gameVersion': manifest.gameVersion,
          },
        );
      }
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'resource_import_uncaught',
      );
      rethrow;
    }
  }

  @override
  Future<void> startGame() async {
    final operation = _logger.beginOperation(
      'game.start',
      'Game startup',
      data: <String, Object?>{
        'resourceStatus': currentValidation.status.name,
        'activeSlot': manifest.activeSlot?.name,
        'gameVersion': currentGameVersion,
      },
    );
    try {
      await super.startGame();
      operation.complete(
        data: <String, Object?>{'serverStatus': serverStatus.name},
      );
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: currentValidation.errorCode ?? 'game_start_failed',
        data: <String, Object?>{
          'validationMessage': currentValidation.errorMessage,
        },
      );
      rethrow;
    }
  }

  @override
  Future<void> stopGame() async {
    final operation = _logger.beginOperation('game.stop', 'Game shutdown');
    try {
      await super.stopGame();
      operation.complete(
        data: <String, Object?>{'serverStatus': serverStatus.name},
      );
    } catch (error, stackTrace) {
      operation.fail(error, stackTrace, code: 'game_stop_failed');
      rethrow;
    }
  }

  @override
  Future<bool> ensureServerAfterResume() async {
    final operation = _logger.beginOperation(
      'game.resume',
      'Server resume check',
      data: <String, Object?>{'serverStatus': serverStatus.name},
    );
    try {
      final restarted = await super.ensureServerAfterResume();
      operation.complete(
        data: <String, Object?>{
          'restarted': restarted,
          'serverStatus': serverStatus.name,
        },
      );
      return restarted;
    } catch (error, stackTrace) {
      operation.fail(error, stackTrace, code: 'server_resume_failed');
      rethrow;
    }
  }

  @override
  Future<void> setWatermarkEnabled(bool enabled) async {
    final operation = _logger.beginOperation(
      'settings.watermark',
      'Watermark setting update',
      data: <String, Object?>{'enabled': enabled},
    );
    try {
      await super.setWatermarkEnabled(enabled);
      operation.complete();
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'watermark_setting_write_failed',
      );
      rethrow;
    }
  }

  void _captureStateChanges() {
    if (_disposed) {
      return;
    }

    final phase = importProgress.phase;
    if (phase != _lastImportPhase) {
      final previous = _lastImportPhase;
      _lastImportPhase = phase;
      final level = switch (phase) {
        ImportPhase.failed => AppLogLevel.error,
        ImportPhase.completed => AppLogLevel.info,
        _ => AppLogLevel.debug,
      };
      _logger.log(
        level,
        'resource.import.progress',
        'Import phase changed',
        code: phase == ImportPhase.failed ? 'import_phase_failed' : null,
        data: <String, Object?>{
          'from': previous.name,
          'to': phase.name,
          'copiedFiles': importProgress.copiedFiles,
          'copiedBytes': importProgress.copiedBytes,
          'totalFiles': importProgress.totalFiles,
          'totalBytes': importProgress.totalBytes,
          'elapsedMs': importProgress.elapsed.inMilliseconds,
          'bytesPerSecond': importProgress.bytesPerSecond.round(),
          'progressMessage': importProgress.message,
        },
      );
    }

    final currentServerStatus = serverStatus;
    if (currentServerStatus != _lastServerStatus) {
      final previous = _lastServerStatus;
      _lastServerStatus = currentServerStatus;
      _logger.log(
        currentServerStatus == ServerStatus.failed
            ? AppLogLevel.error
            : AppLogLevel.info,
        'server.state',
        'Local server state changed',
        code: currentServerStatus == ServerStatus.failed
            ? 'server_state_failed'
            : null,
        data: <String, Object?>{
          'from': previous.name,
          'to': currentServerStatus.name,
        },
      );
    }

    final currentMessage = message;
    if (currentMessage != _lastMessage) {
      _lastMessage = currentMessage;
      if (currentMessage != null && currentMessage.trim().isNotEmpty) {
        _logger.log(
          _messageLevel(currentMessage),
          'ui.message',
          'User-facing status message updated',
          data: <String, Object?>{'message': currentMessage},
        );
      }
    }

    final validationSignature = _validationSignature(currentValidation);
    if (validationSignature != _lastValidationSignature) {
      _lastValidationSignature = validationSignature;
      _logger.log(
        currentValidation.status == ResourceStatus.invalid
            ? AppLogLevel.error
            : currentValidation.status == ResourceStatus.missing
                ? AppLogLevel.warning
                : AppLogLevel.info,
        'resource.validation',
        'Active resource validation changed',
        code: currentValidation.errorCode,
        data: <String, Object?>{
          'status': currentValidation.status.name,
          'message': currentValidation.errorMessage,
          'detectedTitle': currentValidation.detectedTitle,
          'buildProfile': currentValidation.buildProfile.name,
          'gpNextVersion': currentValidation.gpNextVersion,
          'gpNextCompatibilityError':
              currentValidation.gpNextCompatibilityError,
        },
      );
    }

    if (busy != _lastBusy) {
      _lastBusy = busy;
      _logger.debug(
        'app.state',
        'Controller busy state changed',
        data: <String, Object?>{'busy': busy},
      );
    }
    if (initialized != _lastInitialized) {
      _lastInitialized = initialized;
      _logger.info(
        'app.state',
        'Controller initialization state changed',
        data: <String, Object?>{'initialized': initialized},
      );
    }
  }

  void _scheduleDiagnosticsRefresh(AppLogEntry _) {
    if (_disposed || _logRefreshTimer?.isActive == true) {
      return;
    }
    _logRefreshTimer = Timer(const Duration(milliseconds: 120), () {
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  AppLogLevel _messageLevel(String value) {
    if (value.contains('失败') || value.contains('错误')) {
      return AppLogLevel.error;
    }
    if (value.contains('无效') ||
        value.contains('中断') ||
        value.contains('重试') ||
        value.contains('未知')) {
      return AppLogLevel.warning;
    }
    return AppLogLevel.info;
  }

  static String _validationSignature(ResourceValidationResult validation) {
    return <Object?>[
      validation.status.name,
      validation.errorCode,
      validation.errorMessage,
      validation.detectedTitle,
      validation.buildProfile.name,
      validation.gpNextVersion,
      validation.gpNextCompatibilityError,
    ].join('|');
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    removeListener(_captureStateChanges);
    _logRefreshTimer?.cancel();
    unawaited(_logSubscription?.cancel());
    _logger.info(
      'app.lifecycle',
      'Logging application controller disposed',
    );
    super.dispose();
  }
}
