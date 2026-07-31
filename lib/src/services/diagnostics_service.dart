import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../constants.dart';
import '../models.dart';
import 'app_logger.dart';

typedef DiagnosticsAppVersionLoader = Future<String?> Function();

class DiagnosticsService {
  DiagnosticsService({
    String fallbackAppVersion = appVersion,
    DiagnosticsAppVersionLoader? appVersionLoader,
    AppLogger? logger,
  })  : _fallbackAppVersion = fallbackAppVersion,
        _appVersionLoader = appVersionLoader ?? _loadInstalledVersion,
        _logger = logger ?? AppLogger.instance,
        _appVersion = _normalizeVersion(fallbackAppVersion);

  final String _fallbackAppVersion;
  final DiagnosticsAppVersionLoader _appVersionLoader;
  final AppLogger _logger;
  String _appVersion;

  Future<void> initialize() async {
    try {
      final installedVersion = await _appVersionLoader();
      if (installedVersion != null && installedVersion.trim().isNotEmpty) {
        _appVersion = _normalizeVersion(installedVersion);
        _logger.setBaseContext(<String, Object?>{
          'appVersion': _appVersion,
          'operatingSystem': Platform.operatingSystem,
        });
        _logger.info(
          'diagnostics.metadata',
          'Installed application version loaded',
          data: <String, Object?>{'version': _appVersion},
        );
        return;
      }
      _logger.warning(
        'diagnostics.metadata',
        'Installed application version was empty; using compile-time version',
        code: 'app_version_empty',
        data: <String, Object?>{'fallbackVersion': _fallbackAppVersion},
      );
    } catch (error, stackTrace) {
      _logger.warning(
        'diagnostics.metadata',
        'Unable to load installed application version; using compile-time version',
        code: 'app_version_unavailable',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{'fallbackVersion': _fallbackAppVersion},
      );
    }
    _appVersion = _normalizeVersion(_fallbackAppVersion);
    _logger.setBaseContext(<String, Object?>{
      'appVersion': _appVersion,
      'operatingSystem': Platform.operatingSystem,
    });
  }

  DiagnosticSnapshot build({
    required AppPaths paths,
    required ResourceValidationResult currentValidation,
    required ResourceValidationResult importValidation,
    required ResourceManifest manifest,
    required ServerStatus serverStatus,
    String? webViewEngineVersion,
  }) {
    return _LoggedDiagnosticSnapshot(
      logger: _logger,
      appVersion: _appVersion,
      platform: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      webViewEngineVersion: webViewEngineVersion ?? 'unavailable',
      resourceRoot: paths.root.path,
      activeSlot: manifest.activeSlot,
      activeResourcePath: manifest.activeSlot == null
          ? null
          : paths.directoryFor(manifest.activeSlot!).path,
      currentValidation: currentValidation,
      importValidation: importValidation,
      lastImportAt: manifest.lastImportAt,
      fileCount: manifest.fileCount,
      totalBytes: manifest.totalBytes,
      detectedTitle: manifest.detectedTitle,
      buildProfile: manifest.buildProfile,
      gpNextVersion: manifest.gpNextVersion,
      gpNextCompatibilityError: manifest.gpNextCompatibilityError,
      serverHost: localServerHost,
      serverPort: localServerPort,
      serverStatus: serverStatus,
      lastSelfCheckAt: manifest.lastSelfCheckAt,
      lastErrorCode: manifest.lastErrorCode,
      lastErrorMessage: manifest.lastErrorMessage,
      transactionState: manifest.transactionState,
    );
  }

  static Future<String?> _loadInstalledVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  static String _normalizeVersion(String value) {
    final trimmed = value.trim();
    final withoutPrefix = trimmed.startsWith('v') || trimmed.startsWith('V')
        ? trimmed.substring(1)
        : trimmed;
    final withoutBuild = withoutPrefix.split('+').first;
    return withoutBuild.split('-').first;
  }
}

class _LoggedDiagnosticSnapshot extends DiagnosticSnapshot {
  const _LoggedDiagnosticSnapshot({
    required this.logger,
    required super.appVersion,
    required super.platform,
    required super.osVersion,
    required super.webViewEngineVersion,
    required super.resourceRoot,
    required super.activeSlot,
    required super.activeResourcePath,
    required super.currentValidation,
    required super.importValidation,
    required super.lastImportAt,
    required super.fileCount,
    required super.totalBytes,
    required super.detectedTitle,
    required super.buildProfile,
    required super.gpNextVersion,
    required super.gpNextCompatibilityError,
    required super.serverHost,
    required super.serverPort,
    required super.serverStatus,
    required super.lastSelfCheckAt,
    required super.lastErrorCode,
    required super.lastErrorMessage,
    required super.transactionState,
  });

  final AppLogger logger;

  @override
  String toCopyText() {
    final latestError = logger.latestError;
    return <String>[
      super.toCopyText(),
      '',
      ..._plainLoggingSummary(latestError),
      '',
      'Recent structured events:',
      logger.diagnosticsText(limit: 200),
    ].join('\n');
  }

  @override
  String toLogText() {
    final latestError = logger.latestError;
    return <String>[
      super.toLogText(),
      ..._structuredLoggingSummary(latestError),
      '',
      '--- recent structured events ---',
      logger.diagnosticsText(limit: 200),
    ].join('\n');
  }

  List<String> _plainLoggingSummary(AppLogEntry? latestError) {
    final stats = logger.statistics;
    return <String>[
      'Logging session: ${logger.sessionId}',
      'Persistent logging: ${logger.isPersistent}',
      'Log directory: ${logger.logDirectoryPath ?? 'unavailable'}',
      'Active log file: ${logger.activeLogPath ?? 'unavailable'}',
      'Minimum level: ${logger.minimumLevel.label}',
      'Console minimum level: ${logger.consoleMinimumLevel.label}',
      'Console enabled: ${logger.consoleEnabled}',
      'File enabled: ${logger.fileEnabled}',
      'Captured entries: ${stats.totalCaptured}',
      'Entries in memory: ${stats.entriesInMemory}',
      'Pending disk entries: ${stats.pendingDiskEntries}',
      'Dropped entries: ${stats.droppedEntries}',
      'Log sink failures: ${stats.sinkFailures}',
      'Level counts: ${_levelCounts(stats)}',
      'Category count: ${stats.byCategory.length}',
      'Latest runtime error: ${latestError?.errorSummary ?? 'none'}',
    ];
  }

  List<String> _structuredLoggingSummary(AppLogEntry? latestError) {
    final stats = logger.statistics;
    return <String>[
      '[INFO] logging.session id=${logger.sessionId} persistent=${logger.isPersistent}',
      '[INFO] logging.file directory="${logger.logDirectoryPath ?? '-'}" active="${logger.activeLogPath ?? '-'}"',
      '[INFO] logging.configuration minimum=${logger.minimumLevel.label} consoleMinimum=${logger.consoleMinimumLevel.label} consoleEnabled=${logger.consoleEnabled} fileEnabled=${logger.fileEnabled}',
      '[${stats.droppedEntries > 0 ? 'WARN' : 'INFO'}] logging.buffer captured=${stats.totalCaptured} memory=${stats.entriesInMemory} pending=${stats.pendingDiskEntries} dropped=${stats.droppedEntries}',
      '[${stats.sinkFailures > 0 ? 'ERROR' : 'INFO'}] logging.sink failures=${stats.sinkFailures}',
      '[INFO] logging.counts levels="${_levelCounts(stats)}" categories=${stats.byCategory.length}',
      if (latestError != null)
        '[ERROR] runtime.latest ${latestError.errorSummary}',
    ];
  }

  String _levelCounts(AppLogStatistics stats) {
    return AppLogLevel.values
        .map((level) => '${level.label}:${stats.byLevel[level] ?? 0}')
        .join(', ');
  }
}
