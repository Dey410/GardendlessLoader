import 'dart:io';

import '../constants.dart';
import '../models.dart';

class DiagnosticsService {
  DiagnosticSnapshot build({
    required AppPaths paths,
    required ResourceValidationResult currentValidation,
    required ResourceValidationResult importValidation,
    required ResourceManifest manifest,
    required ServerStatus serverStatus,
    String? webViewEngineVersion,
  }) {
    return DiagnosticSnapshot(
      appVersion: appVersion,
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
}
