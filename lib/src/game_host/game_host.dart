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

  static GameHostPlatform current() {
    final value = Platform.operatingSystem;
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

/// How the game viewport fits the screen. The game shows 16:10 to 17:9 without
/// distortion and its whole picture at 17:9. The names are the native session
/// wire values.
enum ScreenFit {
  /// Clamps the viewport to 16:10–17:9: trims some of the picture for
  /// smaller black bars.
  balanced,

  /// Keeps the viewport at 17:9 so the whole picture shows, with larger
  /// black bars.
  showAll,

  /// Stretches the balanced viewport over the whole screen.
  stretch;

  static ScreenFit fromName(Object? value) {
    return ScreenFit.values.firstWhere(
      (fit) => fit.name == value,
      orElse: () => ScreenFit.balanced,
    );
  }
}

/// How touches drive the game. The names are the native session wire values.
enum GestureMode {
  /// Maps one finger to the mouse and clicks the release point of a drag so
  /// it plants; two fingers give the right button and the wheel.
  simulated,

  /// Experimental. Maps one finger to the mouse one to one and teaches the
  /// game drag and drop; two fingers tap, swipe or pinch.
  native;

  static GestureMode fromName(Object? value) {
    return GestureMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => GestureMode.simulated,
    );
  }
}

class GameSession {
  const GameSession({
    required this.sessionId,
    this.packageId,
    required this.resourceRoot,
    required this.platform,
    required this.entryPath,
    required this.activationGeneration,
    required this.hasGpNext,
    required this.gpNextCompatible,
    required this.gpNextVersion,
    required this.watermarkEnabled,
    this.autoCollectSunEnabled = false,
    this.detailedAudioDiagnosticsEnabled = false,
    this.renderScale,
    this.screenFit = ScreenFit.balanced,
    this.gestureMode = GestureMode.simulated,
    this.touchDiagnosticsEnabled = false,
    this.gestureHint,
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
    final renderScale = json['renderScale'];
    if (renderScale != null && (renderScale is! num || renderScale <= 0)) {
      throw const FormatException('renderScale must be positive');
    }
    final gestureHint = json['gestureHint'];
    if (gestureHint != null &&
        (gestureHint is! List || gestureHint.any((line) => line is! String))) {
      throw const FormatException('gestureHint must be a string list');
    }
    return GameSession(
      sessionId: _requiredString(json, 'sessionId'),
      packageId: json['packageId'] as String?,
      resourceRoot: _requiredString(json, 'resourceRoot'),
      platform: GameHostPlatform.fromWireName(json['platform']),
      entryPath: entryPath,
      activationGeneration: generation,
      hasGpNext: _requiredBool(json, 'hasGpNext'),
      gpNextCompatible: _requiredBool(json, 'gpNextCompatible'),
      gpNextVersion: json['gpNextVersion'] as String?,
      watermarkEnabled: _requiredBool(json, 'watermarkEnabled'),
      autoCollectSunEnabled: json['autoCollectSunEnabled'] as bool? ?? false,
      detailedAudioDiagnosticsEnabled:
          json['detailedAudioDiagnosticsEnabled'] as bool? ?? false,
      renderScale: (renderScale as num?)?.toDouble(),
      screenFit: ScreenFit.fromName(json['screenFit']),
      gestureMode: GestureMode.fromName(json['touchGestureMode']),
      touchDiagnosticsEnabled:
          json['touchDiagnosticsEnabled'] as bool? ?? false,
      gestureHint: (gestureHint as List?)?.cast<String>(),
      allowedRemoteHosts: normalizedRemoteHosts,
      gpNextRoot: _requiredString(json, 'gpNextRoot'),
      exportTemporaryRoot: _requiredString(json, 'exportTemporaryRoot'),
    );
  }

  static const schemaVersion = 1;

  final String sessionId;
  final String? packageId;
  final String resourceRoot;
  final GameHostPlatform platform;
  final String entryPath;
  final int activationGeneration;
  final bool hasGpNext;
  final bool gpNextCompatible;
  final String? gpNextVersion;
  final bool watermarkEnabled;
  final bool autoCollectSunEnabled;
  final bool detailedAudioDiagnosticsEnabled;

  /// Share of the device pixel ratio the game canvas renders at; null renders
  /// at the device's own ratio.
  final double? renderScale;
  final ScreenFit screenFit;
  final GestureMode gestureMode;

  /// Records the touch adapter's trace into the logs (tool shed).
  final bool touchDiagnosticsEnabled;

  /// Lines of the one-time gesture hint shown over the game; null shows none.
  final List<String>? gestureHint;
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
      'packageId': packageId,
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
      'detailedAudioDiagnosticsEnabled': detailedAudioDiagnosticsEnabled,
      'renderScale': renderScale,
      'screenFit': screenFit.name,
      'touchGestureMode': gestureMode.name,
      'touchDiagnosticsEnabled': touchDiagnosticsEnabled,
      'gestureHint': gestureHint,
      'allowedRemoteHosts': normalizedRemoteHosts,
      'gpNextRoot': gpNextRoot,
      'exportTemporaryRoot': exportTemporaryRoot,
    };
  }
}

class MethodChannelGameHost {
  const MethodChannelGameHost();

  static const MethodChannel _channel = MethodChannel(
    'io.github.dey410.gardendlessloader/game_host',
  );

  Future<void> launch(GameSession session) async {
    await _channel.invokeMethod<void>('launch', session.toJson());
  }

  Future<HostDevice> device() async {
    final map = await _channel.invokeMapMethod<String, Object?>('device');
    return HostDevice(
      model: map?['model'] as String?,
      webViewVersion: map?['webViewVersion'] as String?,
      memoryBytes: (map?['memoryBytes'] as num?)?.toInt(),
    );
  }
}

/// The device and web engine the game host runs on, for diagnostics.
class HostDevice {
  const HostDevice({this.model, this.webViewVersion, this.memoryBytes});

  final String? model;
  final String? webViewVersion;

  /// Physical memory of the device.
  final int? memoryBytes;
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
