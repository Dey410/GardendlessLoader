import 'dart:io';

import 'constants.dart';

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

  File get journalFile =>
      File('${root.path}${Platform.pathSeparator}journal.json');

  Directory get slotADir =>
      Directory('${root.path}${Platform.pathSeparator}slot-a');
  Directory get slotBDir =>
      Directory('${root.path}${Platform.pathSeparator}slot-b');

  Directory get gpNextDir =>
      Directory('${root.path}${Platform.pathSeparator}gp-next');

  Directory get legacyImportDir =>
      Directory('${root.path}${Platform.pathSeparator}import');
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
    this.stats = const ResourceStats(fileCount: 0, totalBytes: 0),
    this.detectedTitle,
    this.gameVersion,
    this.packageId,
    this.buildProfile = ResourceBuildProfile.standardWeb,
    this.gpNextVersion,
    this.gpNextCompatibilityError,
  });

  factory ResourceValidationResult.valid({
    required ResourceStats stats,
    String? detectedTitle,
    String? gameVersion,
    String? packageId,
    ResourceBuildProfile buildProfile = ResourceBuildProfile.standardWeb,
    String? gpNextVersion,
    String? gpNextCompatibilityError,
  }) {
    return ResourceValidationResult(
      status: ResourceStatus.valid,
      stats: stats,
      errorCode: null,
      errorMessage: null,
      detectedTitle: detectedTitle,
      gameVersion: gameVersion,
      packageId: packageId,
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

  final ResourceStats stats;
  final ResourceStatus status;
  final String? errorCode;
  final String? errorMessage;
  final String? detectedTitle;
  final String? gameVersion;
  final String? packageId;
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
      stats: stats,
      errorCode: errorCode,
      errorMessage: errorMessage,
      detectedTitle: detectedTitle,
      gameVersion: gameVersion,
      packageId: packageId,
      buildProfile: buildProfile,
      gpNextVersion: gpNextVersion,
      gpNextCompatibilityError: gpNextCompatibilityError,
    );
  }
}

class ResourceStats {
  const ResourceStats({required this.fileCount, required this.totalBytes});

  final int fileCount;
  final int totalBytes;
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

/// The links the launcher opens. A link fetched under `urls` in the remote
/// announcement replaces the built-in one for good, so a dead link needs no
/// app release.
class LauncherLinks {
  const LauncherLinks({
    this.loaderGithub = appGithubUrl,
    this.gameGithub = githubUrl,
    this.loaderCloudDrive = cloudDriveUrl,
    this.gameCloudDrive = cloudDriveUrl,
    this.bilibili = bilibiliHomeUrl,
    this.gameReleaseNotes = gameReleaseNotesUrl,
  });

  /// These links with each valid https entry of [urls] written over its
  /// link; a missing or invalid entry leaves the link as it is.
  LauncherLinks merge(Object? urls) {
    if (urls is! Map<String, dynamic>) return this;
    String pick(String key, String current) {
      final url = urls[key];
      return url is String && AnnouncementLink._isAllowedHttpsUrl(url)
          ? url.trim()
          : current;
    }

    final releaseNotes = pick('gameReleaseNotes', gameReleaseNotes);
    return LauncherLinks(
      loaderGithub: pick('loaderGithub', loaderGithub),
      gameGithub: pick('gameGithub', gameGithub),
      loaderCloudDrive: pick('loaderCloudDrive', loaderCloudDrive),
      gameCloudDrive: pick('gameCloudDrive', gameCloudDrive),
      bilibili: pick('bilibili', bilibili),
      gameReleaseNotes:
          releaseNotes.contains('{version}') ? releaseNotes : gameReleaseNotes,
    );
  }

  Map<String, String> toJson() => {
        'loaderGithub': loaderGithub,
        'gameGithub': gameGithub,
        'loaderCloudDrive': loaderCloudDrive,
        'gameCloudDrive': gameCloudDrive,
        'bilibili': bilibili,
        'gameReleaseNotes': gameReleaseNotes,
      };

  final String loaderGithub;
  final String gameGithub;
  final String loaderCloudDrive;
  final String gameCloudDrive;
  final String bilibili;

  /// Contains `{version}`, which [gameReleaseNotesFor] fills in.
  final String gameReleaseNotes;

  String gameReleaseNotesFor(String version) =>
      gameReleaseNotes.replaceAll('{version}', version);
}

class AboutContent {
  const AboutContent({
    required this.contentVersion,
    required this.content,
    this.contentEn,
  });

  factory AboutContent.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('about content must be an object');
    }

    final schemaVersion = value['schemaVersion'];
    final contentVersion = value['contentVersion'];
    final content = value['content'];
    final contentEn = value['contentEn'];
    if (schemaVersion != 1) {
      throw const FormatException('about content schema is unsupported');
    }
    if (contentVersion is! int || contentVersion < 1) {
      throw const FormatException('about content version is invalid');
    }
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('about content is missing');
    }
    if (contentEn != null &&
        (contentEn is! String || contentEn.trim().isEmpty)) {
      throw const FormatException('about content English text is invalid');
    }

    return AboutContent(
      contentVersion: contentVersion,
      content: content,
      contentEn: contentEn as String?,
    );
  }

  final int contentVersion;
  final String content;

  /// English text for the English launcher; absent in older payloads.
  final String? contentEn;

  Map<String, Object> toJson() {
    return {
      'schemaVersion': 1,
      'contentVersion': contentVersion,
      'content': content,
      if (contentEn != null) 'contentEn': contentEn!,
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
    this.errorCode,
  });

  final ImportPhase phase;
  final int copiedFiles;
  final int copiedBytes;
  final int totalFiles;
  final int totalBytes;
  final Duration elapsed;
  final double bytesPerSecond;
  final String? message;

  /// Code of the failure that ended a [ImportPhase.failed] import.
  final String? errorCode;

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
      errorCode: errorCode,
    );
  }
}

/// A launcher notice; an error notice carries the code that selects its fix hint.
class LauncherMessage {
  const LauncherMessage(this.text, [this.code]);

  final String text;
  final String? code;

  @override
  bool operator ==(Object other) =>
      other is LauncherMessage && other.text == text && other.code == code;

  @override
  int get hashCode => Object.hash(text, code);
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
    this.packageId,
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
  final String? packageId;
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
    String? packageId,
    String? gpNextCompatibilityError,
    bool? autoCollectSunEnabled,
    bool clearError = false,
    bool clearGameVersion = false,
    bool clearActiveSlot = false,
    bool clearTransactionSlot = false,
    bool clearGpNextVersion = false,
    bool clearPackageId = false,
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
      packageId: clearPackageId ? null : packageId ?? this.packageId,
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
      'packageId': packageId,
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
    required this.deviceModel,
    required this.memoryBytes,
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
  final String deviceModel;
  final int? memoryBytes;
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
      'Device: $deviceModel',
      'Memory: ${memoryBytes ?? 'unavailable'}',
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
            'device="${_logValue(deviceModel)}" '
            'memoryBytes=${memoryBytes ?? 'unavailable'} '
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
