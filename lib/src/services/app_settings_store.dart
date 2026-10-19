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

/// Caps the device pixel ratio the game renders at; a lower cap shrinks the
/// game canvas and its GPU memory at the cost of sharpness.
enum RenderResolution {
  full(null),
  medium(1.5),
  low(1);

  const RenderResolution(this.pixelRatioCap);

  final double? pixelRatioCap;

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
    this.screenFit = ScreenFit.keepAspect,
    this.detailedAudioDiagnosticsEnabled = false,
    this.themePreference = ThemePreference.system,
    this.reduceMotion = false,
    this.languagePreference = LanguagePreference.system,
    this.seenAnnouncementId,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      watermarkEnabled: json['watermarkEnabled'] as bool? ?? true,
      quickLaunchEnabled: json['quickLaunchEnabled'] as bool? ?? false,
      renderResolution: RenderResolution.fromName(json['renderResolution']),
      screenFit: ScreenFit.fromName(json['screenFit']),
      detailedAudioDiagnosticsEnabled:
          json['detailedAudioDiagnosticsEnabled'] as bool? ?? false,
      themePreference: ThemePreference.fromName(json['themePreference']),
      reduceMotion: json['reduceMotion'] as bool? ?? false,
      languagePreference:
          LanguagePreference.fromName(json['languagePreference']),
      seenAnnouncementId: json['seenAnnouncementId'] as String?,
    );
  }

  final bool watermarkEnabled;

  /// Opens the game directly on a cold start instead of the launcher.
  final bool quickLaunchEnabled;
  final RenderResolution renderResolution;
  final ScreenFit screenFit;
  final bool detailedAudioDiagnosticsEnabled;
  final ThemePreference themePreference;
  final bool reduceMotion;
  final LanguagePreference languagePreference;

  /// Id of the last announcement shown to the user, so a new one pops up
  /// once and an old one never again.
  final String? seenAnnouncementId;

  AppSettings copyWith({
    bool? watermarkEnabled,
    bool? quickLaunchEnabled,
    RenderResolution? renderResolution,
    ScreenFit? screenFit,
    bool? detailedAudioDiagnosticsEnabled,
    ThemePreference? themePreference,
    bool? reduceMotion,
    LanguagePreference? languagePreference,
    String? seenAnnouncementId,
  }) {
    return AppSettings(
      watermarkEnabled: watermarkEnabled ?? this.watermarkEnabled,
      quickLaunchEnabled: quickLaunchEnabled ?? this.quickLaunchEnabled,
      renderResolution: renderResolution ?? this.renderResolution,
      screenFit: screenFit ?? this.screenFit,
      detailedAudioDiagnosticsEnabled: detailedAudioDiagnosticsEnabled ??
          this.detailedAudioDiagnosticsEnabled,
      themePreference: themePreference ?? this.themePreference,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      languagePreference: languagePreference ?? this.languagePreference,
      seenAnnouncementId: seenAnnouncementId ?? this.seenAnnouncementId,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'watermarkEnabled': watermarkEnabled,
        'quickLaunchEnabled': quickLaunchEnabled,
        'renderResolution': renderResolution.name,
        'screenFit': screenFit.name,
        'detailedAudioDiagnosticsEnabled': detailedAudioDiagnosticsEnabled,
        'themePreference': themePreference.name,
        'reduceMotion': reduceMotion,
        'languagePreference': languagePreference.name,
        'seenAnnouncementId': seenAnnouncementId,
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
