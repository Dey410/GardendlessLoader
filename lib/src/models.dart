import 'dart:io';

enum ResourceStatus { missing, valid, invalid, ready }

enum TransactionState { idle, staging, switching, selfChecking }

enum ServerStatus { stopped, starting, running, failed }

enum ImportPhase {
  idle,
  validating,
  scanning,
  copying,
  switching,
  selfChecking,
  completed,
  failed,
}

class AppPaths {
  AppPaths({
    required this.root,
    required this.manifestFile,
    required this.importDir,
    required this.importDocsDir,
    required this.currentDir,
    required this.previousDir,
    required this.stagingDir,
  });

  final Directory root;
  final File manifestFile;
  final Directory importDir;
  final Directory importDocsDir;
  final Directory currentDir;
  final Directory previousDir;
  final Directory stagingDir;
}

class ResourceValidationResult {
  const ResourceValidationResult({
    required this.status,
    required this.errorCode,
    required this.errorMessage,
    this.detectedTitle,
  });

  factory ResourceValidationResult.valid({String? detectedTitle}) {
    return ResourceValidationResult(
      status: ResourceStatus.valid,
      errorCode: null,
      errorMessage: null,
      detectedTitle: detectedTitle,
    );
  }

  factory ResourceValidationResult.missing(String message) {
    return ResourceValidationResult(
      status: ResourceStatus.missing,
      errorCode: 'resource_missing',
      errorMessage: message,
    );
  }

  factory ResourceValidationResult.invalid(String code, String message) {
    return ResourceValidationResult(
      status: ResourceStatus.invalid,
      errorCode: code,
      errorMessage: message,
    );
  }

  final ResourceStatus status;
  final String? errorCode;
  final String? errorMessage;
  final String? detectedTitle;

  bool get isValid => status == ResourceStatus.valid || status == ResourceStatus.ready;

  ResourceValidationResult asReady() {
    return ResourceValidationResult(
      status: ResourceStatus.ready,
      errorCode: errorCode,
      errorMessage: errorMessage,
      detectedTitle: detectedTitle,
    );
  }
}

class ResourceStats {
  const ResourceStats({
    required this.fileCount,
    required this.totalBytes,
    required this.detectedTitle,
  });

  final int fileCount;
  final int totalBytes;
  final String? detectedTitle;
}

class ImportProgress {
  const ImportProgress({
    required this.phase,
    this.copiedFiles = 0,
    this.copiedBytes = 0,
    this.totalFiles = 0,
    this.totalBytes = 0,
    this.message,
  });

  final ImportPhase phase;
  final int copiedFiles;
  final int copiedBytes;
  final int totalFiles;
  final int totalBytes;
  final String? message;

  static const idle = ImportProgress(phase: ImportPhase.idle);

  ImportProgress copyWith({
    ImportPhase? phase,
    int? copiedFiles,
    int? copiedBytes,
    int? totalFiles,
    int? totalBytes,
    String? message,
  }) {
    return ImportProgress(
      phase: phase ?? this.phase,
      copiedFiles: copiedFiles ?? this.copiedFiles,
      copiedBytes: copiedBytes ?? this.copiedBytes,
      totalFiles: totalFiles ?? this.totalFiles,
      totalBytes: totalBytes ?? this.totalBytes,
      message: message ?? this.message,
    );
  }
}

class ResourceManifest {
  const ResourceManifest({
    required this.schemaVersion,
    required this.lastImportAt,
    required this.fileCount,
    required this.totalBytes,
    required this.detectedTitle,
    required this.resourceStatus,
    required this.lastSelfCheckAt,
    required this.lastErrorCode,
    required this.lastErrorMessage,
    required this.transactionState,
  });

  factory ResourceManifest.initial() {
    return const ResourceManifest(
      schemaVersion: 1,
      lastImportAt: null,
      fileCount: 0,
      totalBytes: 0,
      detectedTitle: null,
      resourceStatus: ResourceStatus.missing,
      lastSelfCheckAt: null,
      lastErrorCode: null,
      lastErrorMessage: null,
      transactionState: TransactionState.idle,
    );
  }

  final int schemaVersion;
  final DateTime? lastImportAt;
  final int fileCount;
  final int totalBytes;
  final String? detectedTitle;
  final ResourceStatus resourceStatus;
  final DateTime? lastSelfCheckAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final TransactionState transactionState;

  ResourceManifest copyWith({
    DateTime? lastImportAt,
    int? fileCount,
    int? totalBytes,
    String? detectedTitle,
    ResourceStatus? resourceStatus,
    DateTime? lastSelfCheckAt,
    String? lastErrorCode,
    String? lastErrorMessage,
    TransactionState? transactionState,
    bool clearError = false,
  }) {
    return ResourceManifest(
      schemaVersion: schemaVersion,
      lastImportAt: lastImportAt ?? this.lastImportAt,
      fileCount: fileCount ?? this.fileCount,
      totalBytes: totalBytes ?? this.totalBytes,
      detectedTitle: detectedTitle ?? this.detectedTitle,
      resourceStatus: resourceStatus ?? this.resourceStatus,
      lastSelfCheckAt: lastSelfCheckAt ?? this.lastSelfCheckAt,
      lastErrorCode: clearError ? null : lastErrorCode ?? this.lastErrorCode,
      lastErrorMessage: clearError ? null : lastErrorMessage ?? this.lastErrorMessage,
      transactionState: transactionState ?? this.transactionState,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'lastImportAt': lastImportAt?.toIso8601String(),
      'fileCount': fileCount,
      'totalBytes': totalBytes,
      'detectedTitle': detectedTitle,
      'resourceStatus': resourceStatus.name,
      'lastSelfCheckAt': lastSelfCheckAt?.toIso8601String(),
      'lastErrorCode': lastErrorCode,
      'lastErrorMessage': lastErrorMessage,
      'transaction': {
        'state': transactionState.name,
      },
    };
  }
}

class DiagnosticSnapshot {
  const DiagnosticSnapshot({
    required this.appVersion,
    required this.platform,
    required this.osVersion,
    required this.webViewEngineVersion,
    required this.resourceRoot,
    required this.currentValidation,
    required this.importValidation,
    required this.lastImportAt,
    required this.fileCount,
    required this.totalBytes,
    required this.detectedTitle,
    required this.serverHost,
    required this.serverPort,
    required this.serverStatus,
    required this.lastSelfCheckAt,
    required this.lastErrorCode,
    required this.lastErrorMessage,
    required this.transactionState,
  });

  final String appVersion;
  final String platform;
  final String osVersion;
  final String webViewEngineVersion;
  final String resourceRoot;
  final ResourceValidationResult currentValidation;
  final ResourceValidationResult importValidation;
  final DateTime? lastImportAt;
  final int fileCount;
  final int totalBytes;
  final String? detectedTitle;
  final String serverHost;
  final int serverPort;
  final ServerStatus serverStatus;
  final DateTime? lastSelfCheckAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final TransactionState transactionState;

  String toCopyText() {
    return [
      'App version: $appVersion',
      'Platform: $platform',
      'OS version: $osVersion',
      'WebView engine version: $webViewEngineVersion',
      'resourceRoot: $resourceRoot',
      'current validation: ${currentValidation.status.name}'
          '${currentValidation.errorCode == null ? '' : ' (${currentValidation.errorCode}: ${currentValidation.errorMessage})'}',
      'import/docs validation: ${importValidation.status.name}'
          '${importValidation.errorCode == null ? '' : ' (${importValidation.errorCode}: ${importValidation.errorMessage})'}',
      'lastImportAt: ${lastImportAt?.toIso8601String()}',
      'fileCount: $fileCount',
      'totalBytes: $totalBytes',
      'detectedTitle: $detectedTitle',
      'serverHost: $serverHost',
      'serverPort: $serverPort',
      'serverStatus: ${serverStatus.name}',
      'lastSelfCheckAt: ${lastSelfCheckAt?.toIso8601String()}',
      'lastErrorCode: $lastErrorCode',
      'lastErrorMessage: $lastErrorMessage',
      'transaction.state: ${transactionState.name}',
    ].join('\n');
  }
}
