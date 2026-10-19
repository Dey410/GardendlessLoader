import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'http_text.dart';

const defaultGameTagsApiUrl =
    'https://api.github.com/repos/Gzh0821/pvzg_site/tags?per_page=100';
const defaultGameUpdateCheckTimeout = Duration(seconds: 5);
const defaultGameUpdateCheckMaxBytes = 64 * 1024;

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
  static final Uri _tagsUri = Uri.parse(defaultGameTagsApiUrl);

  Future<GameUpdateCheckResult> check({
    required String currentVersion,
    String? latestVersion,
  }) async {
    final resolvedLatestVersion = latestVersion ?? await loadLatestVersion();
    final comparison =
        compareGameVersions(resolvedLatestVersion, currentVersion);
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
    final response = await loadHttpText(
      _tagsUri,
      defaultGameUpdateCheckTimeout,
      defaultGameUpdateCheckMaxBytes,
    ).timeout(defaultGameUpdateCheckTimeout);
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
    stableVersions.sort(compareGameVersions);
    return stableVersions.last;
  }
}

/// Orders game versions such as `0.15.0` and `0.15.1-beta`; a pre-release
/// sorts before its release.
int compareGameVersions(String left, String right) {
  final leftParts = left.split('-').first.split('.').map(int.parse).toList();
  final rightParts = right.split('-').first.split('.').map(int.parse).toList();
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

/// Versions [compareGameVersions] understands.
final gameVersionPattern = RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$');

class GameUpdateCheckException implements Exception {
  const GameUpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}
