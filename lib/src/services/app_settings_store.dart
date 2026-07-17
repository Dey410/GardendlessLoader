import 'dart:convert';
import 'dart:io';

class AppSettingsStore {
  AppSettingsStore(this._file);

  final File _file;

  File get _temporaryFile => File('${_file.path}.tmp');

  Future<bool> readWatermarkEnabled() async {
    if (!await _file.exists()) {
      return true;
    }

    try {
      final json = jsonDecode(await _file.readAsString());
      if (json is Map<String, dynamic>) {
        return json['watermarkEnabled'] as bool? ?? true;
      }
    } catch (_) {
      // Invalid or outdated settings fall back to the safe default.
    }
    return true;
  }

  Future<void> writeWatermarkEnabled(bool enabled) async {
    await _file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _temporaryFile.writeAsString(
      '${encoder.convert({'watermarkEnabled': enabled})}\n',
      flush: true,
    );
    await _temporaryFile.rename(_file.path);
  }
}
