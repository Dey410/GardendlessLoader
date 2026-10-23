import 'dart:io';

import '../game_host/game_host.dart';
import '../models.dart';

DiagnosticSnapshot buildDiagnosticSnapshot({
  required String appVersion,
  required AppPaths paths,
  required ResourceValidationResult currentValidation,
  required ResourceValidationResult importValidation,
  required ResourceManifest manifest,
  required GameHostPlatform gameHostPlatform,
  required HostDevice? hostDevice,
}) {
  return DiagnosticSnapshot(
    appVersion: appVersion,
    platform: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion,
    deviceModel: hostDevice?.model ?? 'unavailable',
    memoryBytes: hostDevice?.memoryBytes,
    webViewEngineVersion: hostDevice?.webViewVersion ?? 'unavailable',
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
    gameHost: gameHostPlatform.nativeHostName,
    resourceServer: 'none',
    origin: gameHostPlatform.origin,
    lastSelfCheckAt: manifest.lastSelfCheckAt,
    lastErrorCode: manifest.lastErrorCode,
    lastErrorMessage: manifest.lastErrorMessage,
    transactionState: manifest.transactionState,
  );
}
