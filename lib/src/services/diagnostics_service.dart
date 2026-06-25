import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../constants.dart';
import '../models.dart';

typedef DiagnosticsAppVersionLoader = Future<String?> Function();

class DiagnosticsService {
  DiagnosticsService({
    String fallbackAppVersion = appVersion,
    DiagnosticsAppVersionLoader? appVersionLoader,
  })  : _fallbackAppVersion = fallbackAppVersion,
        _appVersionLoader = appVersionLoader ?? _loadInstalledVersion,
        _appVersion = _normalizeVersion(fallbackAppVersion);

  final String _fallbackAppVersion;
  final DiagnosticsAppVersionLoader _appVersionLoader;
  String _appVersion;

  Future<void> initialize() async {
    try {
      final installedVersion = await _appVersionLoader();
      if (installedVersion != null && installedVersion.trim().isNotEmpty) {
        _appVersion = _normalizeVersion(installedVersion);
        return;
      }
    } catch (_) {
      // Fall back to the compile-time version when package metadata is
      // unavailable, such as in unsupported test or platform environments.
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
    return DiagnosticSnapshot(
      appVersion: _appVersion,
      platform: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      webViewEngineVersion: webViewEngineVersion ?? 'unavailable',
      resourceRoot: paths.root.path,
      currentValidation: currentValidation,
      importValidation: importValidation,
      lastImportAt: manifest.lastImportAt,
      fileCount: manifest.fileCount,
      totalBytes: manifest.totalBytes,
      detectedTitle: manifest.detectedTitle,
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
