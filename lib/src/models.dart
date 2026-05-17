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

  bool get isValid =>
      status == ResourceStatus.valid || status == ResourceStatus.ready;

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

class AnnouncementLink {
  const AnnouncementLink({
    required this.label,
    required this.url,
  });

  factory AnnouncementLink.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('announcement link must be an object');
    }

    final label = value['label'];
    final url = value['url'];
    if (label is! String || label.trim().isEmpty) {
      throw const FormatException('announcement link label is missing');
    }
    if (url is! String || !_isAllowedHttpsUrl(url)) {
      throw const FormatException('announcement link url must be https');
    }

    return AnnouncementLink(label: label.trim(), url: url.trim());
  }

  final String label;
  final String url;

  static bool _isAllowedHttpsUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.message,
    this.links = const [],
  });

  factory Announcement.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('announcement must be an object');
    }

    final id = value['id'];
    final title = value['title'];
    final message = value['message'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('announcement id is missing');
    }
    if (title is! String || title.trim().isEmpty) {
      throw const FormatException('announcement title is missing');
    }
    if (message is! String || message.trim().isEmpty) {
      throw const FormatException('announcement message is missing');
    }

    final rawLinks = value['links'];
    final links = rawLinks == null
        ? const <AnnouncementLink>[]
        : (rawLinks as List)
            .map<AnnouncementLink>(AnnouncementLink.fromJson)
            .toList(growable: false);

    return Announcement(
      id: id.trim(),
      title: title.trim(),
      message: message.trim(),
      links: links,
    );
  }

  final String id;
  final String title;
  final String message;
  final List<AnnouncementLink> links;
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
    this.dismissedAnnouncementId,
    this.dismissedAnnouncementLocalDate,
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
  final String? dismissedAnnouncementId;
  final String? dismissedAnnouncementLocalDate;

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
    String? dismissedAnnouncementId,
    String? dismissedAnnouncementLocalDate,
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
      lastErrorMessage:
          clearError ? null : lastErrorMessage ?? this.lastErrorMessage,
      transactionState: transactionState ?? this.transactionState,
      dismissedAnnouncementId:
          dismissedAnnouncementId ?? this.dismissedAnnouncementId,
      dismissedAnnouncementLocalDate:
          dismissedAnnouncementLocalDate ?? this.dismissedAnnouncementLocalDate,
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
      'announcement': {
        'dismissedId': dismissedAnnouncementId,
        'dismissedLocalDate': dismissedAnnouncementLocalDate,
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
