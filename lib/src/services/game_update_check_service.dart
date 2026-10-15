import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'http_text.dart';

const defaultGameTagsApiUrl =
    'https://api.github.com/repos/Gzh0821/pvzg_site/tags?per_page=100';
const defaultGameUpdateCheckTimeout = Duration(seconds: 5);
const defaultGameUpdateCheckMaxBytes = 64 * 1024;

typedef GameUpdateCheckHttpLoader = HttpTextLoader;

typedef GameUpdateCheckHttpResponse = HttpTextResponse;

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
  })  : _tagsUri = Uri.parse(tagsApiUrl),
        _timeout = timeout,
        _maxBytes = maxBytes,
        _loader = loader ?? loadHttpText;

  final Uri _tagsUri;
  final Duration _timeout;
  final int _maxBytes;
  final GameUpdateCheckHttpLoader _loader;

  Future<GameUpdateCheckResult> check({
    required String currentVersion,
    String? latestVersion,
  }) async {
    final resolvedLatestVersion = latestVersion ?? await loadLatestVersion();
    final comparison = _compareVersions(resolvedLatestVersion, currentVersion);
    if (comparison <= 0) {
      return GameUpdateCheckResult(
        currentVersion: currentVersion,
        latestVersion: resolvedLatestVersion,
        update: null,
        currentIsAhead: comparison < 0,
      );
    }

    final update = GameUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: resolvedLatestVersion,
      tagName: resolvedLatestVersion,
    );
    return GameUpdateCheckResult(
      currentVersion: currentVersion,
      latestVersion: resolvedLatestVersion,
      update: update,
      currentIsAhead: false,
    );
  }

  Future<String> loadLatestVersion() async {
    final response = await _loader(
      _tagsUri,
      _timeout,
      _maxBytes,
    ).timeout(_timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw const GameUpdateCheckException('GitHub tags request failed');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const GameUpdateCheckException('GitHub tags response is invalid');
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
    return stableVersions.last;
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
}

class GameUpdateCheckException implements Exception {
  const GameUpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}
