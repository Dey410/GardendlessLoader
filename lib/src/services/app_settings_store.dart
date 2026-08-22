import 'dart:convert';
import 'dart:io';

class AppSettings {
  const AppSettings({
    this.watermarkEnabled = true,
    this.detailedAudioDiagnosticsEnabled = false,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      watermarkEnabled: json['watermarkEnabled'] as bool? ?? true,
      detailedAudioDiagnosticsEnabled:
          json['detailedAudioDiagnosticsEnabled'] as bool? ?? false,
    );
  }

  final bool watermarkEnabled;
  final bool detailedAudioDiagnosticsEnabled;

  Map<String, Object?> toJson() => <String, Object?>{
        'watermarkEnabled': watermarkEnabled,
        'detailedAudioDiagnosticsEnabled': detailedAudioDiagnosticsEnabled,
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
