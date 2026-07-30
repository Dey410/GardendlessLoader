import 'dart:io';

enum ResourceStatus { missing, valid, invalid, ready }

enum ResourceBuildProfile { standardWeb, gpNext }

enum ResourceSlot {
  slotA,
  slotB;

  ResourceSlot get other => this == slotA ? slotB : slotA;
}

enum TransactionState {
  idle,
  extracting,
  validating,
  selfChecking,
  readyToActivate,
  cleaningOldSlot,
  migrating,
}

enum ImportPhase {
  idle,
  receiving,
  extracting,
  validating,
  scanning,
  selfChecking,
  completed,
  failed,
}

typedef ImportProgressCallback = void Function(ImportProgress progress);

class AppPaths {
  AppPaths({required this.root, required this.manifestFile});

  final Directory root;
  final File manifestFile;

  File get appSettingsFile =>
      File('${root.path}${Platform.pathSeparator}app_settings.json');

  Directory get slotADir =>
      Directory('${root.path}${Platform.pathSeparator}slot-a');
  Directory get slotBDir =>
      Directory('${root.path}${Platform.pathSeparator}slot-b');

  Directory get gpNextDir =>
      Directory('${root.path}${Platform.pathSeparator}gp-next');
  Directory get gpNextPacksDir =>
      Directory('${gpNextDir.path}${Platform.pathSeparator}packs');
  Directory get gpNextPatchesDir =>
      Directory('${gpNextDir.path}${Platform.pathSeparator}patches');

  Directory get legacyImportDir =>
      Directory('${root.path}${Platform.pathSeparator}import');
  Directory get legacyImportDocsDir =>
      Directory('${legacyImportDir.path}${Platform.pathSeparator}docs');
  Directory get legacyCurrentDir =>
      Directory('${root.path}${Platform.pathSeparator}current');
  Directory get legacyPreviousDir =>
      Directory('${root.path}${Platform.pathSeparator}previous');
  Directory get legacyStagingDir =>
      Directory('${root.path}${Platform.pathSeparator}staging');

  Directory directoryFor(ResourceSlot slot) =>
      slot == ResourceSlot.slotA ? slotADir : slotBDir;
}

class ResourceValidationResult {
  const ResourceValidationResult({
    required this.status,
    required this.errorCode,
    required this.errorMessage,
    this.detectedTitle,
    this.buildProfile = ResourceBuildProfile.standardWeb,
    this.gpNextVersion,
    this.gpNextCompatibilityError,
  });

  factory ResourceValidationResult.valid({
    String? detectedTitle,
    ResourceBuildProfile buildProfile = ResourceBuildProfile.standardWeb,
    String? gpNextVersion,
    String? gpNextCompatibilityError,
  }) {
    return ResourceValidationResult(
      status: ResourceStatus.valid,
      errorCode: null,
      errorMessage: null,
      detectedTitle: detectedTitle,
      buildProfile: buildProfile,
      gpNextVersion: gpNextVersion,
      gpNextCompatibilityError: gpNextCompatibilityError,
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
  final ResourceBuildProfile buildProfile;
  final String? gpNextVersion;
  final String? gpNextCompatibilityError;

  bool get isValid =>
      status == ResourceStatus.valid || status == ResourceStatus.ready;
  bool get hasGpNext => buildProfile == ResourceBuildProfile.gpNext;
  bool get gpNextCompatible => hasGpNext && gpNextCompatibilityError == null;

  ResourceValidationResult asReady() {
    return ResourceValidationResult(
      status: ResourceStatus.ready,
      errorCode: errorCode,
      errorMessage: errorMessage,
      detectedTitle: detectedTitle,
      buildProfile: buildProfile,
      gpNextVersion: gpNextVersion,
      gpNextCompatibilityError: gpNextCompatibilityError,
    );
  }
}

class ResourceStats {
  const ResourceStats({
    required this.fileCount,
    required this.totalBytes,
    required this.detectedTitle,
    this.buildProfile = ResourceBuildProfile.standardWeb,
    this.gpNextVersion,
    this.gpNextCompatibilityError,
  });

  final int fileCount;
  final int totalBytes;
  final String? detectedTitle;
  final ResourceBuildProfile buildProfile;
  final String? gpNextVersion;
  final String? gpNextCompatibilityError;
}

class AnnouncementLink {
  const AnnouncementLink({required this.label, required this.url});

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

class AboutContent {
  const AboutContent({required this.contentVersion, required this.content});

  factory AboutContent.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('about content must be an object');
    }

    final schemaVersion = value['schemaVersion'];
    final contentVersion = value['contentVersion'];
    final content = value['content'];
    if (schemaVersion != 1) {
      throw const FormatException('about content schema is unsupported');
    }
    if (contentVersion is! int || contentVersion < 1) {
      throw const FormatException('about content version is invalid');
    }
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('about content is missing');
    }

    return AboutContent(contentVersion: contentVersion, content: content);
  }

  final int contentVersion;
  final String content;

  Map<String, Object> toJson() {
    return {
      'schemaVersion': 1,
      'contentVersion': contentVersion,
      'content': content,
    };
  }
}

class ImportProgress {
  const ImportProgress({
    required this.phase,
    this.copiedFiles = 0,
    this.copiedBytes = 0,
    this.totalFiles = 0,
    this.totalBytes = 0,
    this.elapsed = Duration.zero,
    this.bytesPerSecond = 0,
    this.message,
  });

  final ImportPhase phase;
  final int copiedFiles;
  final int copiedBytes;
  final int totalFiles;
  final int totalBytes;
  final Duration elapsed;
  final double bytesPerSecond;
  final String? message;

  static const idle = ImportProgress(phase: ImportPhase.idle);

  int get stepCount => 4;

  int get stepIndex => switch (phase) {
        ImportPhase.receiving => 1,
        ImportPhase.extracting => 2,
        ImportPhase.validating || ImportPhase.scanning => 3,
        ImportPhase.selfChecking || ImportPhase.completed => 4,
        ImportPhase.idle || ImportPhase.failed => 0,
      };

  double? get value {
    if (phase == ImportPhase.completed) {
      return 1;
    }
    if (totalBytes > 0) {
      return (copiedBytes / totalBytes).clamp(0.0, 1.0);
    }
    if (totalFiles > 0) {
      return (copiedFiles / totalFiles).clamp(0.0, 1.0);
    }
    return null;
  }

  ImportProgress copyWith({
    ImportPhase? phase,
    int? copiedFiles,
    int? copiedBytes,
    int? totalFiles,
    int? totalBytes,
    Duration? elapsed,
    double? bytesPerSecond,
    String? message,
  }) {
    return ImportProgress(
      phase: phase ?? this.phase,
      copiedFiles: copiedFiles ?? this.copiedFiles,
      copiedBytes: copiedBytes ?? this.copiedBytes,
      totalFiles: totalFiles ?? this.totalFiles,
      totalBytes: totalBytes ?? this.totalBytes,
      elapsed: elapsed ?? this.elapsed,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      message: message ?? this.message,
    );
  }
}

class ResourceManifest {
  const ResourceManifest({
    required this.schemaVersion,
    required this.generation,
    required this.activeSlot,
    required this.transactionSlot,
    required this.gameVersion,
    required this.lastImportAt,
    required this.fileCount,
    required this.totalBytes,
    required this.detectedTitle,
    required this.resourceStatus,
    required this.lastSelfCheckAt,
    required this.lastErrorCode,
    required this.lastErrorMessage,
    required this.transactionState,
    this.buildProfile = ResourceBuildProfile.standardWeb,
    this.gpNextVersion,
    this.gpNextCompatibilityError,
    this.autoCollectSunEnabled = false,
  });

  factory ResourceManifest.initial() {
    return const ResourceManifest(
      schemaVersion: 4,
      generation: 0,
      activeSlot: null,
      transactionSlot: null,
      gameVersion: null,
      lastImportAt: null,
      fileCount: 0,
      totalBytes: 0,
      detectedTitle: null,
      resourceStatus: ResourceStatus.missing,
      lastSelfCheckAt: null,
      lastErrorCode: null,
      lastErrorMessage: null,
      transactionState: TransactionState.idle,
      buildProfile: ResourceBuildProfile.standardWeb,
      gpNextVersion: null,
      gpNextCompatibilityError: null,
      autoCollectSunEnabled: false,
    );
  }

  final int schemaVersion;
  final int generation;
  final ResourceSlot? activeSlot;
  final ResourceSlot? transactionSlot;
  final String? gameVersion;
  final DateTime? lastImportAt;
  final int fileCount;
  final int totalBytes;
  final String? detectedTitle;
  final ResourceStatus resourceStatus;
  final DateTime? lastSelfCheckAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final TransactionState transactionState;
  final ResourceBuildProfile buildProfile;
  final String? gpNextVersion;
  final String? gpNextCompatibilityError;
  final bool autoCollectSunEnabled;

  bool get hasGpNext => buildProfile == ResourceBuildProfile.gpNext;
  bool get gpNextCompatible => hasGpNext && gpNextCompatibilityError == null;

  ResourceManifest copyWith({
    int? generation,
    ResourceSlot? activeSlot,
    ResourceSlot? transactionSlot,
    String? gameVersion,
    DateTime? lastImportAt,
    int? fileCount,
    int? totalBytes,
    String? detectedTitle,
    ResourceStatus? resourceStatus,
    DateTime? lastSelfCheckAt,
    String? lastErrorCode,
    String? lastErrorMessage,
    TransactionState? transactionState,
    ResourceBuildProfile? buildProfile,
    String? gpNextVersion,
    String? gpNextCompatibilityError,
    bool? autoCollectSunEnabled,
    bool clearError = false,
    bool clearGameVersion = false,
    bool clearActiveSlot = false,
    bool clearTransactionSlot = false,
    bool clearGpNextVersion = false,
    bool clearGpNextCompatibilityError = false,
  }) {
    return ResourceManifest(
      schemaVersion: schemaVersion,
      generation: generation ?? this.generation,
      activeSlot: clearActiveSlot ? null : activeSlot ?? this.activeSlot,
      transactionSlot:
          clearTransactionSlot ? null : transactionSlot ?? this.transactionSlot,
      gameVersion: clearGameVersion ? null : gameVersion ?? this.gameVersion,
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
      buildProfile: buildProfile ?? this.buildProfile,
      gpNextVersion:
          clearGpNextVersion ? null : gpNextVersion ?? this.gpNextVersion,
      gpNextCompatibilityError: clearGpNextCompatibilityError
          ? null
          : gpNextCompatibilityError ?? this.gpNextCompatibilityError,
      autoCollectSunEnabled:
          autoCollectSunEnabled ?? this.autoCollectSunEnabled,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'generation': generation,
      'activeSlot': activeSlot?.name,
      'gameVersion': gameVersion,
      'lastImportAt': lastImportAt?.toIso8601String(),
      'fileCount': fileCount,
      'totalBytes': totalBytes,
      'detectedTitle': detectedTitle,
      'buildProfile': buildProfile.name,
      'gpNextVersion': gpNextVersion,
      'gpNextCompatibilityError': gpNextCompatibilityError,
      'autoCollectSunEnabled': autoCollectSunEnabled,
      'resourceStatus': resourceStatus.name,
      'lastSelfCheckAt': lastSelfCheckAt?.toIso8601String(),
      'lastErrorCode': lastErrorCode,
      'lastErrorMessage': lastErrorMessage,
      'transaction': {
        'state': transactionState.name,
        'slot': transactionSlot?.name,
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
    required this.activeSlot,
    required this.activeResourcePath,
    required this.currentValidation,
    required this.importValidation,
    required this.lastImportAt,
    required this.fileCount,
    required this.totalBytes,
    required this.detectedTitle,
    required this.buildProfile,
    required this.gpNextVersion,
    required this.gpNextCompatibilityError,
    required this.gameHost,
    required this.resourceServer,
    required this.origin,
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
  final ResourceSlot? activeSlot;
  final String? activeResourcePath;
  final ResourceValidationResult currentValidation;
  final ResourceValidationResult importValidation;
  final DateTime? lastImportAt;
  final int fileCount;
  final int totalBytes;
  final String? detectedTitle;
  final ResourceBuildProfile buildProfile;
  final String? gpNextVersion;
  final String? gpNextCompatibilityError;
  final String gameHost;
  final String resourceServer;
  final String origin;
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
      'activeSlot: ${activeSlot?.name}',
      'activeResourcePath: $activeResourcePath',
      'active slot validation: ${currentValidation.status.name}'
          '${currentValidation.errorCode == null ? '' : ' (${currentValidation.errorCode}: ${currentValidation.errorMessage})'}',
      'selected import validation: ${importValidation.status.name}'
          '${importValidation.errorCode == null ? '' : ' (${importValidation.errorCode}: ${importValidation.errorMessage})'}',
      'lastImportAt: ${lastImportAt?.toIso8601String()}',
      'fileCount: $fileCount',
      'totalBytes: $totalBytes',
      'detectedTitle: $detectedTitle',
      'buildProfile: ${buildProfile.name}',
      'gpNextVersion: $gpNextVersion',
      'gpNextCompatibilityError: $gpNextCompatibilityError',
      'gameHost: $gameHost',
      'resourceServer: $resourceServer',
      'origin: $origin',
      'lastSelfCheckAt: ${lastSelfCheckAt?.toIso8601String()}',
      'lastErrorCode: $lastErrorCode',
      'lastErrorMessage: $lastErrorMessage',
      'transaction.state: ${transactionState.name}',
    ].join('\n');
  }

  String toLogText() {
    return [
      _logLine(
        'INFO',
        'app',
        'version="${_logValue(appVersion)}" '
            'platform="${_logValue(platform)}" '
            'os="${_logValue(osVersion)}" '
            'webview="${_logValue(webViewEngineVersion)}"',
      ),
      _logLine('INFO', 'resource.root', 'path="${_logValue(resourceRoot)}"'),
      _logLine(
        'INFO',
        'resource.active',
        'slot=${activeSlot?.name ?? 'none'} '
            'path="${_logValue(activeResourcePath)}"',
      ),
      _validationLogLine('active.slot.validation', currentValidation),
      _validationLogLine('selected.import.validation', importValidation),
      _logLine(
        'INFO',
        'manifest',
        'lastImportAt=${_iso(lastImportAt)} '
            'fileCount=$fileCount '
            'totalBytes=$totalBytes '
            'detectedTitle="${_logValue(detectedTitle)}" '
            'buildProfile=${buildProfile.name} '
            'gpNextVersion="${_logValue(gpNextVersion)}" '
            'gpNextCompatibilityError="${_logValue(gpNextCompatibilityError)}"',
      ),
      _logLine(
        'INFO',
        'game.host',
        'implementation=$gameHost resourceServer=$resourceServer '
            'origin="$origin"',
      ),
      _logLine(
        currentValidation.isValid && lastSelfCheckAt == null ? 'WARN' : 'INFO',
        'self.check',
        'lastAt=${_iso(lastSelfCheckAt)}',
      ),
      _logLine(
        transactionState == TransactionState.idle ? 'INFO' : 'WARN',
        'transaction',
        'state=${transactionState.name}',
      ),
      if (lastErrorMessage == null)
        _logLine('INFO', 'last.error', 'none')
      else
        _logLine(
          'ERROR',
          'last.error',
          'code="${_logValue(lastErrorCode)}" '
              'message="${_logValue(lastErrorMessage)}"',
        ),
    ].join('\n');
  }

  String _validationLogLine(
    String target,
    ResourceValidationResult validation,
  ) {
    final fields = [
      'status=${validation.status.name}',
      if (validation.errorCode != null)
        'code="${_logValue(validation.errorCode)}"',
      if (validation.errorMessage != null)
        'message="${_logValue(validation.errorMessage)}"',
      if (validation.detectedTitle != null)
        'detectedTitle="${_logValue(validation.detectedTitle)}"',
    ];
    return _logLine(_validationLogLevel(validation), target, fields.join(' '));
  }

  String _validationLogLevel(ResourceValidationResult validation) {
    return switch (validation.status) {
      ResourceStatus.invalid => 'ERROR',
      ResourceStatus.missing => 'WARN',
      ResourceStatus.valid || ResourceStatus.ready => 'INFO',
    };
  }

  String _logLine(String level, String target, String message) {
    return '[$level] $target $message';
  }

  String _iso(DateTime? value) => value?.toIso8601String() ?? '-';

  String _logValue(Object? value) {
    final text = value?.toString();
    if (text == null || text.trim().isEmpty) {
      return '-';
    }
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('"', r'\"');
  }
}
