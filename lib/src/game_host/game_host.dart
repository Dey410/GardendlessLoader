import 'dart:io';

import 'package:flutter/services.dart';

enum GameHostPlatform {
  android('android', 'https://appassets.androidplatform.net'),
  ios('ios', 'gardendless-game://localhost'),
  ohos('ohos', 'https://gardendless.invalid');

  const GameHostPlatform(this.wireName, this.origin);

  final String wireName;
  final String origin;

  String get nativeHostName => '$wireName-native';

  static GameHostPlatform current({String? operatingSystem}) {
    final value = operatingSystem ?? Platform.operatingSystem;
    return GameHostPlatform.values.firstWhere(
      (platform) => platform.wireName == value,
      orElse: () => throw UnsupportedError(
        'Gardendless native GameHost does not support $value',
      ),
    );
  }

  static GameHostPlatform fromWireName(Object? value) {
    return GameHostPlatform.values.firstWhere(
      (platform) => platform.wireName == value,
      orElse: () => throw FormatException(
        'Unsupported native GameHost platform: $value',
      ),
    );
  }
}

class GameSession {
  const GameSession({
    required this.sessionId,
    required this.resourceRoot,
    required this.platform,
    required this.entryPath,
    required this.activationGeneration,
    required this.hasGpNext,
    required this.gpNextCompatible,
    required this.gpNextVersion,
    required this.watermarkEnabled,
    this.autoCollectSunEnabled = false,
    required this.allowedRemoteHosts,
    required this.gpNextRoot,
    required this.exportTemporaryRoot,
  });

  factory GameSession.fromJson(Map<String, Object?> json) {
    final entryPath = _requiredString(json, 'entryPath');
    _validateEntryPath(entryPath);
    final allowedRemoteHosts = json['allowedRemoteHosts'];
    if (allowedRemoteHosts is! List ||
        allowedRemoteHosts.any((host) => host is! String)) {
      throw const FormatException('allowedRemoteHosts must be a string list');
    }
    final normalizedRemoteHosts = allowedRemoteHosts
        .cast<String>()
        .map(_normalizeRemoteHost)
        .toList(growable: false);
    final generation = json['activationGeneration'];
    if (generation is! int || generation < 0) {
      throw const FormatException('activationGeneration must be non-negative');
    }
    return GameSession(
      sessionId: _requiredString(json, 'sessionId'),
      resourceRoot: _requiredString(json, 'resourceRoot'),
      platform: GameHostPlatform.fromWireName(json['platform']),
      entryPath: entryPath,
      activationGeneration: generation,
      hasGpNext: _requiredBool(json, 'hasGpNext'),
      gpNextCompatible: _requiredBool(json, 'gpNextCompatible'),
      gpNextVersion: json['gpNextVersion'] as String?,
      watermarkEnabled: _requiredBool(json, 'watermarkEnabled'),
      autoCollectSunEnabled: json['autoCollectSunEnabled'] as bool? ?? false,
      allowedRemoteHosts: normalizedRemoteHosts,
      gpNextRoot: _requiredString(json, 'gpNextRoot'),
      exportTemporaryRoot: _requiredString(json, 'exportTemporaryRoot'),
    );
  }

  static const schemaVersion = 1;

  final String sessionId;
  final String resourceRoot;
  final GameHostPlatform platform;
  final String entryPath;
  final int activationGeneration;
  final bool hasGpNext;
  final bool gpNextCompatible;
  final String? gpNextVersion;
  final bool watermarkEnabled;
  final bool autoCollectSunEnabled;
  final List<String> allowedRemoteHosts;
  final String gpNextRoot;
  final String exportTemporaryRoot;

  String get origin => platform.origin;

  Uri get entryUri {
    final base = Uri.parse('$origin/$entryPath');
    return base.replace(
      queryParameters: {'generation': activationGeneration.toString()},
    );
  }

  Map<String, Object?> toJson() {
    final normalizedRemoteHosts =
        allowedRemoteHosts.map(_normalizeRemoteHost).toList(growable: false);
    return {
      'schemaVersion': schemaVersion,
      'sessionId': sessionId,
      'state': 'prepared',
      'resourceRoot': resourceRoot,
      'platform': platform.wireName,
      'origin': origin,
      'entryPath': entryPath,
      'entryUrl': entryUri.toString(),
      'activationGeneration': activationGeneration,
      'hasGpNext': hasGpNext,
      'gpNextCompatible': gpNextCompatible,
      'gpNextVersion': gpNextVersion,
      'watermarkEnabled': watermarkEnabled,
      'autoCollectSunEnabled': autoCollectSunEnabled,
      'allowedRemoteHosts': normalizedRemoteHosts,
      'gpNextRoot': gpNextRoot,
      'exportTemporaryRoot': exportTemporaryRoot,
    };
  }

  GameSession copyWith({int? activationGeneration}) {
    return GameSession(
      sessionId: sessionId,
      resourceRoot: resourceRoot,
      platform: platform,
      entryPath: entryPath,
      activationGeneration: activationGeneration ?? this.activationGeneration,
      hasGpNext: hasGpNext,
      gpNextCompatible: gpNextCompatible,
      gpNextVersion: gpNextVersion,
      watermarkEnabled: watermarkEnabled,
      autoCollectSunEnabled: autoCollectSunEnabled,
      allowedRemoteHosts: allowedRemoteHosts,
      gpNextRoot: gpNextRoot,
      exportTemporaryRoot: exportTemporaryRoot,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GameSession &&
        other.sessionId == sessionId &&
        other.resourceRoot == resourceRoot &&
        other.platform == platform &&
        other.entryPath == entryPath &&
        other.activationGeneration == activationGeneration &&
        other.hasGpNext == hasGpNext &&
        other.gpNextCompatible == gpNextCompatible &&
        other.gpNextVersion == gpNextVersion &&
        other.watermarkEnabled == watermarkEnabled &&
        other.autoCollectSunEnabled == autoCollectSunEnabled &&
        _listEquals(other.allowedRemoteHosts, allowedRemoteHosts) &&
        other.gpNextRoot == gpNextRoot &&
        other.exportTemporaryRoot == exportTemporaryRoot;
  }

  @override
  int get hashCode => Object.hash(
        sessionId,
        resourceRoot,
        platform,
        entryPath,
        activationGeneration,
        hasGpNext,
        gpNextCompatible,
        gpNextVersion,
        watermarkEnabled,
        autoCollectSunEnabled,
        Object.hashAll(allowedRemoteHosts),
        gpNextRoot,
        exportTemporaryRoot,
      );
}

abstract interface class GameHost {
  Future<void> launch(GameSession session);
}

class GameHostRouter implements GameHost {
  const GameHostRouter({required Map<GameHostPlatform, GameHost> hosts})
      : _hosts = hosts;

  factory GameHostRouter.platformChannel({
    MethodChannel channel = const MethodChannel(
      'io.github.dey410.gardendlessloader/game_host',
    ),
  }) {
    final host = MethodChannelGameHost(channel: channel);
    return GameHostRouter(
      hosts: {
        for (final platform in GameHostPlatform.values) platform: host,
      },
    );
  }

  final Map<GameHostPlatform, GameHost> _hosts;

  @override
  Future<void> launch(GameSession session) async {
    final host = _hosts[session.platform];
    if (host == null) {
      throw UnsupportedError(
        'No native GameHost is registered for ${session.platform.wireName}',
      );
    }
    await host.launch(session);
  }
}

class MethodChannelGameHost implements GameHost {
  const MethodChannelGameHost({required MethodChannel channel})
      : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> launch(GameSession session) async {
    await _channel.invokeMethod<void>('launch', session.toJson());
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('$key must be a bool');
  }
  return value;
}

String _normalizeRemoteHost(String value) {
  final host = value.trim().toLowerCase();
  final labels = host.split('.');
  final valid = host.isNotEmpty &&
      host.length <= 253 &&
      labels.every(
        (label) =>
            label.isNotEmpty &&
            label.length <= 63 &&
            RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
      );
  if (!valid) {
    throw FormatException('Invalid allowed remote host: $value');
  }
  return host;
}

void _validateEntryPath(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      value.startsWith('/') ||
      value.contains('\\') ||
      uri.pathSegments.any((segment) => segment == '.' || segment == '..')) {
    throw const FormatException('entryPath must stay inside the resource root');
  }
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
