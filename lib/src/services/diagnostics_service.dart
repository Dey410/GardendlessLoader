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
      'Logging session: ${logger.sessionId}',
      'Persistent logging: ${logger.isPersistent}',
      'Active log file: ${logger.activeLogPath ?? 'unavailable'}',
      'Latest runtime error: ${latestError?.errorSummary ?? 'none'}',
      '',
      'Recent structured events:',
      logger.diagnosticsText(limit: 120),
    ].join('\n');
  }

  @override
  String toLogText() {
    final latestError = logger.latestError;
    return <String>[
      super.toLogText(),
      '[INFO] logging.session id=${logger.sessionId} persistent=${logger.isPersistent}',
      '[INFO] logging.file path="${logger.activeLogPath ?? '-'}"',
      if (latestError != null)
        '[ERROR] runtime.latest ${latestError.errorSummary}',
      '',
      '--- recent structured events ---',
      logger.diagnosticsText(limit: 120),
    ].join('\n');
  }
}
