import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../constants.dart';
import 'app_logger.dart';

const defaultLatestReleaseApiUrl =
    'https://api.github.com/repos/Dey410/GardendlessLoader/releases/latest';
const defaultUpdateCheckTimeout = Duration(seconds: 5);
const defaultUpdateCheckMaxBytes = 64 * 1024;

typedef UpdateCheckHttpLoader = Future<UpdateCheckHttpResponse> Function(
  Uri uri,
  Duration timeout,
  int maxBytes,
);

typedef InstalledVersionLoader = Future<String?> Function();

class UpdateCheckHttpResponse {
  const UpdateCheckHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tagName,
    required this.releaseUrl,
    required this.releaseName,
    required this.releaseNotes,
    required this.publishedAt,
  });

  final String currentVersion;
  final String latestVersion;
  final String tagName;
  final String releaseUrl;
  final String releaseName;
  final String releaseNotes;
  final DateTime? publishedAt;
}

class UpdateCheckService {
  UpdateCheckService({
    String latestReleaseApiUrl = defaultLatestReleaseApiUrl,
    String currentVersion = appVersion,
    Duration timeout = defaultUpdateCheckTimeout,
    int maxBytes = defaultUpdateCheckMaxBytes,
    UpdateCheckHttpLoader? loader,
    InstalledVersionLoader? installedVersionLoader,
    AppLogger? logger,
  })  : _latestReleaseUri = Uri.parse(latestReleaseApiUrl),
        _currentVersion = currentVersion,
        _timeout = timeout,
        _maxBytes = maxBytes,
        _loader = loader ?? _loadWithHttpClient,
        _installedVersionLoader =
            installedVersionLoader ?? _loadInstalledVersion,
        _logger = logger ?? AppLogger.instance;

  final Uri _latestReleaseUri;
  final String _currentVersion;
  final Duration _timeout;
  final int _maxBytes;
  final UpdateCheckHttpLoader _loader;
  final InstalledVersionLoader _installedVersionLoader;
  final AppLogger _logger;

  Future<String> loadCurrentVersion() => _loadCurrentVersion();

  Future<UpdateInfo?> checkForUpdate() async {
    final operation = _logger.beginOperation(
      'network.app_update',
      'Application update check',
      data: <String, Object?>{
        'uri': _latestReleaseUri,
        'timeoutMs': _timeout.inMilliseconds,
        'maxBytes': _maxBytes,
      },
    );
    try {
      final response = await _loader(
        _latestReleaseUri,
        _timeout,
        _maxBytes,
      ).timeout(_timeout);
      operation.step(
        'Release response received',
        data: <String, Object?>{
          'statusCode': response.statusCode,
          'bodyBytes': utf8.encode(response.body).length,
        },
      );
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateCheckException(
          'GitHub release request failed with HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const UpdateCheckException(
          'GitHub release response is invalid',
        );
      }

      final tagName = _requiredString(decoded['tag_name']);
      final latestVersion = _normalizeVersion(tagName);
      final releaseUrl = _requiredHttpsUrl(decoded['html_url']);
      final releaseName = _optionalString(decoded['name']) ?? tagName;
      final releaseNotes = _optionalString(decoded['body']) ?? '';
      final publishedAt = DateTime.tryParse(
        _optionalString(decoded['published_at']) ?? '',
      );
      final currentVersion = await _loadCurrentVersion();
      final comparison = _compareVersions(latestVersion, currentVersion);

      if (comparison <= 0) {
        operation.complete(
          message: 'Application is up to date',
          data: <String, Object?>{
            'currentVersion': currentVersion,
            'latestVersion': latestVersion,
            'currentIsAhead': comparison < 0,
          },
        );
        return null;
      }

      final update = UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        tagName: tagName,
        releaseUrl: releaseUrl,
        releaseName: releaseName,
        releaseNotes: releaseNotes,
        publishedAt: publishedAt,
      );
      operation.complete(
        message: 'Application update is available',
        data: <String, Object?>{
          'currentVersion': currentVersion,
          'latestVersion': latestVersion,
          'tagName': tagName,
          'publishedAt': publishedAt,
        },
      );
      return update;
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'app_update_check_failed',
      );
      rethrow;
    }
  }

  static Future<UpdateCheckHttpResponse> _loadWithHttpClient(
    Uri uri,
    Duration timeout,
    int maxBytes,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, appDisplayName);
      final response = await request.close().timeout(timeout);
      final contentLength = response.contentLength;
      if (contentLength > maxBytes) {
        throw const FormatException('update check response is too large');
      }

      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) {
          final nextLength = buffer.length + chunk.length;
          if (nextLength > maxBytes) {
            throw const FormatException('update check response is too large');
          }
          buffer.addAll(chunk);
          return buffer;
        },
      ).timeout(timeout);

      return UpdateCheckHttpResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _loadCurrentVersion() async {
    try {
      final installedVersion = await _installedVersionLoader();
      if (installedVersion != null && installedVersion.trim().isNotEmpty) {
        final normalized = _normalizeVersion(installedVersion);
        _logger.debug(
          'app.metadata',
          'Installed application version loaded',
          data: <String, Object?>{'version': normalized},
        );
        return normalized;
      }
      _logger.warning(
        'app.metadata',
        'Installed application version was empty; compile-time fallback selected',
        code: 'installed_version_empty',
        data: <String, Object?>{'fallbackVersion': _currentVersion},
      );
    } catch (error, stackTrace) {
      _logger.warning(
        'app.metadata',
        'Installed application version was unavailable; compile-time fallback selected',
        code: 'installed_version_unavailable',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{'fallbackVersion': _currentVersion},
      );
    }
    return _normalizeVersion(_currentVersion);
  }

  static Future<String?> _loadInstalledVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  static String _requiredString(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw const UpdateCheckException('GitHub release response is invalid');
  }

  static String? _optionalString(Object? value) {
    if (value is String) {
      return value.trim();
    }
    return null;
  }

  static String _requiredHttpsUrl(Object? value) {
    final url = _requiredString(value);
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const UpdateCheckException('GitHub release url is invalid');
    }
    return url;
  }

  static String _normalizeVersion(String value) {
    final trimmed = value.trim();
    final withoutPrefix = trimmed.startsWith('v') || trimmed.startsWith('V')
        ? trimmed.substring(1)
        : trimmed;
    final withoutBuild = withoutPrefix.split('+').first;
    return withoutBuild.split('-').first;
  }

  static int _compareVersions(String left, String right) {
    final leftParts = _parseVersionParts(left);
    final rightParts = _parseVersionParts(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var i = 0; i < maxLength; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;
      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }
    return 0;
  }

  static List<int> _parseVersionParts(String version) {
    return version
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}
