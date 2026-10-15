import 'dart:convert';
import 'dart:io';

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

class AppSettings {
  const AppSettings({
    this.watermarkEnabled = true,
    this.quickLaunchEnabled = false,
    this.detailedAudioDiagnosticsEnabled = false,
    this.themePreference = ThemePreference.system,
    this.reduceMotion = false,
    this.seenAnnouncementId,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      watermarkEnabled: json['watermarkEnabled'] as bool? ?? true,
      quickLaunchEnabled: json['quickLaunchEnabled'] as bool? ?? false,
      detailedAudioDiagnosticsEnabled:
          json['detailedAudioDiagnosticsEnabled'] as bool? ?? false,
      themePreference: ThemePreference.fromName(json['themePreference']),
      reduceMotion: json['reduceMotion'] as bool? ?? false,
      seenAnnouncementId: json['seenAnnouncementId'] as String?,
    );
  }

  final bool watermarkEnabled;

  /// Opens the game directly on a cold start instead of the launcher.
  final bool quickLaunchEnabled;
  final bool detailedAudioDiagnosticsEnabled;
  final ThemePreference themePreference;
  final bool reduceMotion;

  /// Id of the last announcement shown to the user, so a new one pops up
  /// once and an old one never again.
  final String? seenAnnouncementId;

  AppSettings copyWith({
    bool? watermarkEnabled,
    bool? quickLaunchEnabled,
    bool? detailedAudioDiagnosticsEnabled,
    ThemePreference? themePreference,
    bool? reduceMotion,
    String? seenAnnouncementId,
  }) {
    return AppSettings(
      watermarkEnabled: watermarkEnabled ?? this.watermarkEnabled,
      quickLaunchEnabled: quickLaunchEnabled ?? this.quickLaunchEnabled,
      detailedAudioDiagnosticsEnabled: detailedAudioDiagnosticsEnabled ??
          this.detailedAudioDiagnosticsEnabled,
      themePreference: themePreference ?? this.themePreference,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      seenAnnouncementId: seenAnnouncementId ?? this.seenAnnouncementId,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'watermarkEnabled': watermarkEnabled,
        'quickLaunchEnabled': quickLaunchEnabled,
        'detailedAudioDiagnosticsEnabled': detailedAudioDiagnosticsEnabled,
        'themePreference': themePreference.name,
        'reduceMotion': reduceMotion,
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
