import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../constants.dart';
import 'app_logger.dart';

const defaultGameTagsApiUrl =
    'https://api.github.com/repos/Gzh0821/pvzg_site/tags?per_page=100';
const defaultGameUpdateCheckTimeout = Duration(seconds: 5);
const defaultGameUpdateCheckMaxBytes = 64 * 1024;

typedef GameUpdateCheckHttpLoader = Future<GameUpdateCheckHttpResponse>
    Function(
  Uri uri,
  Duration timeout,
  int maxBytes,
);

class GameUpdateCheckHttpResponse {
  const GameUpdateCheckHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

class GameUpdateInfo {
  const GameUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tagName,
  });

  final String currentVersion;
  final String latestVersion;
  final String tagName;
}

class GameUpdateCheckResult {
  const GameUpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.update,
    required this.currentIsAhead,
  });

  final String currentVersion;
  final String latestVersion;
  final GameUpdateInfo? update;
  final bool currentIsAhead;
}

class GameUpdateCheckService {
  GameUpdateCheckService({
    String tagsApiUrl = defaultGameTagsApiUrl,
    Duration timeout = defaultGameUpdateCheckTimeout,
    int maxBytes = defaultGameUpdateCheckMaxBytes,
    GameUpdateCheckHttpLoader? loader,
    AppLogger? logger,
  })  : _tagsUri = Uri.parse(tagsApiUrl),
        _timeout = timeout,
        _maxBytes = maxBytes,
        _loader = loader ?? _loadWithHttpClient,
        _logger = logger ?? AppLogger.instance;

  final Uri _tagsUri;
  final Duration _timeout;
  final int _maxBytes;
  final GameUpdateCheckHttpLoader _loader;
  final AppLogger _logger;

  Future<String?> loadCurrentVersion(Directory root) async {
    final operation = _logger.beginOperation(
      'game.version',
      'Local game version detection',
      data: <String, Object?>{'root': root.path},
    );
    try {
      final indexFile = File('${root.path}${Platform.pathSeparator}index.html');
      if (!await indexFile.exists()) {
        operation.complete(
          message: 'Local game version is unavailable',
          data: const <String, Object?>{
            'reason': 'index_missing',
            'version': null,
          },
        );
        return null;
      }

      final html = await indexFile.readAsString();
      final title = RegExp(
        r'<title[^>]*>(.*?)</title>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(html)?.group(1);
      final titleVersion = title == null
          ? null
          : RegExp(
              r'(?:^|[^0-9A-Za-z])v?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)(?![0-9A-Za-z.-])',
              caseSensitive: false,
            ).firstMatch(title)?.group(1);
      if (titleVersion != null) {
        operation.complete(
          data: <String, Object?>{
            'version': titleVersion,
            'source': 'html_title',
          },
        );
        return titleVersion;
      }

      final moduleTag = RegExp(
        r'''<script\b(?=[^>]*\btype\s*=\s*["']module["'])[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>''',
        caseSensitive: false,
      ).firstMatch(html);
      final source = moduleTag?.group(1);
      if (source == null || source.contains('://')) {
        operation.complete(
          message: 'Local game version is unavailable',
          data: <String, Object?>{
            'reason': source == null ? 'module_script_missing' : 'remote_module',
            'version': null,
          },
        );
        return null;
      }
      final relative = (Uri.tryParse(source)?.path ?? source).replaceFirst(
        RegExp(r'^/+'),
        '',
      );
      final module = File(p.join(root.path, relative));
      if (!await module.exists()) {
        operation.complete(
          message: 'Local game version is unavailable',
          data: <String, Object?>{
            'reason': 'module_file_missing',
            'module': relative,
            'version': null,
          },
        );
        return null;
      }
      final entry = await module.readAsString();
      final version = RegExp(
        r'(?:Playing version|Game Version:)\s*v?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)',
        caseSensitive: false,
      ).firstMatch(entry)?.group(1);
      operation.complete(
        data: <String, Object?>{
          'version': version,
          'source': version == null ? 'not_detected' : 'module_entry',
          'module': relative,
        },
      );
      return version;
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'local_game_version_detection_failed',
        level: AppLogLevel.warning,
      );
      rethrow;
    }
  }

  Future<GameUpdateCheckResult> check({
    required String currentVersion,
    String? latestVersion,
  }) async {
    final operation = _logger.beginOperation(
      'network.game_update',
      'Game update check',
      data: <String, Object?>{
        'currentVersion': currentVersion,
        'reusedLatestVersion': latestVersion,
      },
    );
    try {
      final resolvedLatestVersion = latestVersion ?? await loadLatestVersion();
      final comparison = _compareVersions(resolvedLatestVersion, currentVersion);
      if (comparison <= 0) {
        final result = GameUpdateCheckResult(
          currentVersion: currentVersion,
          latestVersion: resolvedLatestVersion,
          update: null,
          currentIsAhead: comparison < 0,
        );
        operation.complete(
          message: 'Game is up to date',
          data: <String, Object?>{
            'latestVersion': resolvedLatestVersion,
            'currentIsAhead': result.currentIsAhead,
          },
        );
        return result;
      }

      final update = GameUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: resolvedLatestVersion,
        tagName: resolvedLatestVersion,
      );
      final result = GameUpdateCheckResult(
        currentVersion: currentVersion,
        latestVersion: resolvedLatestVersion,
        update: update,
        currentIsAhead: false,
      );
      operation.complete(
        message: 'Game update is available',
        data: <String, Object?>{
          'latestVersion': resolvedLatestVersion,
        },
      );
      return result;
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'game_update_check_failed',
      );
      rethrow;
    }
  }

  Future<String> loadLatestVersion() async {
    final operation = _logger.beginOperation(
      'network.game_tags',
      'Stable game tag request',
      data: <String, Object?>{
        'uri': _tagsUri,
        'timeoutMs': _timeout.inMilliseconds,
        'maxBytes': _maxBytes,
      },
    );
    try {
      final response = await _loader(
        _tagsUri,
        _timeout,
        _maxBytes,
      ).timeout(_timeout);
      operation.step(
        'Game tag response received',
        data: <String, Object?>{
          'statusCode': response.statusCode,
          'bodyBytes': utf8.encode(response.body).length,
        },
      );
      if (response.statusCode != HttpStatus.ok) {
        throw GameUpdateCheckException(
          'GitHub tags request failed with HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const GameUpdateCheckException(
          'GitHub tags response is invalid',
        );
      }

      final stableVersions = decoded
          .whereType<Map>()
          .map((tag) => tag['name'])
          .whereType<String>()
          .where((tag) => RegExp(r'^\d+\.\d+\.\d+$').hasMatch(tag))
          .toList();
      if (stableVersions.isEmpty) {
        throw const GameUpdateCheckException('No stable game tag found');
      }
      stableVersions.sort(_compareVersions);
      final latest = stableVersions.last;
      operation.complete(
        data: <String, Object?>{
          'latestVersion': latest,
          'stableTagCount': stableVersions.length,
        },
      );
      return latest;
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'game_tags_request_failed',
      );
      rethrow;
    }
  }

  static int _compareVersions(String left, String right) {
    final leftParts = left.split('-').first.split('.').map(int.parse).toList();
    final rightParts =
        right.split('-').first.split('.').map(int.parse).toList();
    for (var index = 0; index < 3; index++) {
      final comparison = leftParts[index].compareTo(rightParts[index]);
      if (comparison != 0) {
        return comparison;
      }
    }
    final leftIsPrerelease = left.contains('-');
    final rightIsPrerelease = right.contains('-');
    if (leftIsPrerelease == rightIsPrerelease) {
      return 0;
    }
    return leftIsPrerelease ? -1 : 1;
  }

  static Future<GameUpdateCheckHttpResponse> _loadWithHttpClient(
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
      if (response.contentLength > maxBytes) {
        throw const FormatException('game update response is too large');
      }
      final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
        if (buffer.length + chunk.length > maxBytes) {
          throw const FormatException('game update response is too large');
        }
        buffer.addAll(chunk);
        return buffer;
      }).timeout(timeout);
      return GameUpdateCheckHttpResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
      );
    } finally {
      client.close(force: true);
    }
  }
}

class GameUpdateCheckException implements Exception {
  const GameUpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}
