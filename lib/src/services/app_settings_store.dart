import 'dart:convert';
import 'dart:io';

import '../game_host/game_host.dart';

enum ThemePreference {
  system,
  light,
  dark;

  static ThemePreference fromName(Object? value) {
    return ThemePreference.values.firstWhere(
      (preference) => preference.name == value,
      orElse: () => ThemePreference.system,
    );
  }
}

enum LanguagePreference {
  system,
  chinese,
  english;

  static LanguagePreference fromName(Object? value) {
    return LanguagePreference.values.firstWhere(
      (preference) => preference.name == value,
      orElse: () => LanguagePreference.system,
    );
  }
}

/// Renders the game at a share of the device's native resolution; a lower
/// share shrinks the game canvas and its GPU memory at the cost of sharpness.
enum RenderResolution {
  full(null),
  medium(0.75),
  low(0.5);

  const RenderResolution(this.scale);

  /// Share of the device pixel ratio the game renders at; null is native.
  final double? scale;

  static RenderResolution fromName(Object? value) {
    return RenderResolution.values.firstWhere(
      (resolution) => resolution.name == value,
      orElse: () => RenderResolution.full,
    );
  }
}

class AppSettings {
  const AppSettings({
    this.watermarkEnabled = true,
    this.quickLaunchEnabled = false,
    this.renderResolution = RenderResolution.full,
    this.screenFit = ScreenFit.balanced,
    this.gestureMode = GestureMode.simulated,
    this.detailedAudioDiagnosticsEnabled = false,
    this.themePreference = ThemePreference.system,
    this.reduceMotion = false,
    this.languagePreference = LanguagePreference.system,
    this.seenAnnouncementId,
    this.toolShedUnlocked = false,
    this.touchDiagnosticsEnabled = false,
    this.gestureHintShown = false,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      watermarkEnabled: json['watermarkEnabled'] as bool? ?? true,
      quickLaunchEnabled: json['quickLaunchEnabled'] as bool? ?? false,
      renderResolution: RenderResolution.fromName(json['renderResolution']),
      screenFit: ScreenFit.fromName(json['screenFit']),
      gestureMode: GestureMode.fromName(json['gestureMode']),
      detailedAudioDiagnosticsEnabled:
          json['detailedAudioDiagnosticsEnabled'] as bool? ?? false,
      themePreference: ThemePreference.fromName(json['themePreference']),
      reduceMotion: json['reduceMotion'] as bool? ?? false,
      languagePreference:
          LanguagePreference.fromName(json['languagePreference']),
      seenAnnouncementId: json['seenAnnouncementId'] as String?,
      toolShedUnlocked: json['toolShedUnlocked'] as bool? ?? false,
      touchDiagnosticsEnabled:
          json['touchDiagnosticsEnabled'] as bool? ?? false,
      gestureHintShown: json['gestureHintShown'] as bool? ?? false,
    );
  }

  final bool watermarkEnabled;

  /// Opens the game directly on a cold start instead of the launcher.
  final bool quickLaunchEnabled;
  final RenderResolution renderResolution;
  final ScreenFit screenFit;

  /// The experimental gesture setting; simulated by default.
  final GestureMode gestureMode;
  final bool detailedAudioDiagnosticsEnabled;
  final ThemePreference themePreference;
  final bool reduceMotion;
  final LanguagePreference languagePreference;

  /// Id of the last announcement shown to the user, so a new one pops up
  /// once and an old one never again.
  final String? seenAnnouncementId;

  /// The tool shed found by tapping the launcher icon seven times.
  final bool toolShedUnlocked;

  /// Records the touch trace on the next launch; only while the tool shed is
  /// unlocked.
  final bool touchDiagnosticsEnabled;

  /// The gesture hint shows over the game once, on the first launch.
  final bool gestureHintShown;

  AppSettings copyWith({
    bool? watermarkEnabled,
    bool? quickLaunchEnabled,
    RenderResolution? renderResolution,
    ScreenFit? screenFit,
    GestureMode? gestureMode,
    bool? detailedAudioDiagnosticsEnabled,
    ThemePreference? themePreference,
    bool? reduceMotion,
    LanguagePreference? languagePreference,
    String? seenAnnouncementId,
    bool? toolShedUnlocked,
    bool? touchDiagnosticsEnabled,
    bool? gestureHintShown,
  }) {
    return AppSettings(
      watermarkEnabled: watermarkEnabled ?? this.watermarkEnabled,
      quickLaunchEnabled: quickLaunchEnabled ?? this.quickLaunchEnabled,
      renderResolution: renderResolution ?? this.renderResolution,
      screenFit: screenFit ?? this.screenFit,
      gestureMode: gestureMode ?? this.gestureMode,
      detailedAudioDiagnosticsEnabled: detailedAudioDiagnosticsEnabled ??
          this.detailedAudioDiagnosticsEnabled,
      themePreference: themePreference ?? this.themePreference,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      languagePreference: languagePreference ?? this.languagePreference,
      seenAnnouncementId: seenAnnouncementId ?? this.seenAnnouncementId,
      toolShedUnlocked: toolShedUnlocked ?? this.toolShedUnlocked,
      touchDiagnosticsEnabled:
          touchDiagnosticsEnabled ?? this.touchDiagnosticsEnabled,
      gestureHintShown: gestureHintShown ?? this.gestureHintShown,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'watermarkEnabled': watermarkEnabled,
        'quickLaunchEnabled': quickLaunchEnabled,
        'renderResolution': renderResolution.name,
        'screenFit': screenFit.name,
        'gestureMode': gestureMode.name,
        'detailedAudioDiagnosticsEnabled': detailedAudioDiagnosticsEnabled,
        'themePreference': themePreference.name,
        'reduceMotion': reduceMotion,
        'languagePreference': languagePreference.name,
        'seenAnnouncementId': seenAnnouncementId,
        'toolShedUnlocked': toolShedUnlocked,
        'touchDiagnosticsEnabled': touchDiagnosticsEnabled,
        'gestureHintShown': gestureHintShown,
      };
}

class AppSettingsStore {
  AppSettingsStore(this._file);

  final File _file;

  File get _temporaryFile => File('${_file.path}.tmp');

  Future<AppSettings> read() async {
    if (!await _file.exists()) {
      return const AppSettings();
    }

    try {
      final json = jsonDecode(await _file.readAsString());
      if (json is Map<String, dynamic>) {
        return AppSettings.fromJson(json);
      }
    } catch (_) {
      // Invalid or outdated settings fall back to the safe default.
    }
    return const AppSettings();
  }

  Future<void> write(AppSettings settings) async {
    await _file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _temporaryFile.writeAsString(
      '${encoder.convert(settings.toJson())}\n',
      flush: true,
    );
    await _temporaryFile.rename(_file.path);
  }
}
