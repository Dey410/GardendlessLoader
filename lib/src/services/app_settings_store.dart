import 'dart:convert';
import 'dart:io';

import 'app_logger.dart';

class AppSettings {
  const AppSettings({
    this.watermarkEnabled = true,
    this.loggingMinimumLevel = AppLogLevel.trace,
    this.consoleMinimumLevel = AppLogLevel.warning,
    this.consoleEnabled = true,
    this.fileEnabled = true,
  });

  final bool watermarkEnabled;
  final AppLogLevel loggingMinimumLevel;
  final AppLogLevel consoleMinimumLevel;
  final bool consoleEnabled;
  final bool fileEnabled;

  AppSettings copyWith({
    bool? watermarkEnabled,
    AppLogLevel? loggingMinimumLevel,
    AppLogLevel? consoleMinimumLevel,
    bool? consoleEnabled,
    bool? fileEnabled,
  }) {
    return AppSettings(
      watermarkEnabled: watermarkEnabled ?? this.watermarkEnabled,
      loggingMinimumLevel:
          loggingMinimumLevel ?? this.loggingMinimumLevel,
      consoleMinimumLevel:
          consoleMinimumLevel ?? this.consoleMinimumLevel,
      consoleEnabled: consoleEnabled ?? this.consoleEnabled,
      fileEnabled: fileEnabled ?? this.fileEnabled,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 2,
        'watermarkEnabled': watermarkEnabled,
        'logging': <String, Object?>{
          'minimumLevel': loggingMinimumLevel.label,
          'consoleMinimumLevel': consoleMinimumLevel.label,
          'consoleEnabled': consoleEnabled,
          'fileEnabled': fileEnabled,
        },
      };

  static AppSettings fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('settings root must be an object');
    }
    final logging = value['logging'];
    final loggingMap = logging is Map<String, dynamic>
        ? logging
        : const <String, dynamic>{};
    return AppSettings(
      watermarkEnabled: value['watermarkEnabled'] as bool? ?? true,
      loggingMinimumLevel:
          AppLogLevel.tryParse(loggingMap['minimumLevel']) ??
              AppLogLevel.trace,
      consoleMinimumLevel:
          AppLogLevel.tryParse(loggingMap['consoleMinimumLevel']) ??
              AppLogLevel.warning,
      consoleEnabled: loggingMap['consoleEnabled'] as bool? ?? true,
      fileEnabled: loggingMap['fileEnabled'] as bool? ?? true,
    );
  }
}

class AppSettingsStore {
  AppSettingsStore(this._file, {AppLogger? logger})
      : _logger = logger ?? AppLogger.instance;

  final File _file;
  final AppLogger _logger;

  File get _temporaryFile => File('${_file.path}.tmp');

  Future<AppSettings> read() async {
    final mainExists = await _file.exists();
    final temporaryExists = await _temporaryFile.exists();
    if (!mainExists && !temporaryExists) {
      _logger.traceLog(
        'settings.storage',
        'Settings file does not exist; defaults selected',
        data: <String, Object?>{'path': _file.path},
      );
      return const AppSettings();
    }

    final main = mainExists ? await _tryRead(_file, temporary: false) : null;
    final temporary = temporaryExists
        ? await _tryRead(_temporaryFile, temporary: true)
        : null;
    if (main != null) {
      if (temporaryExists) {
        try {
          await _temporaryFile.delete();
          _logger.warning(
            'settings.storage',
            'Stale settings temporary file removed',
            code: 'settings_stale_temp_removed',
            data: <String, Object?>{'path': _temporaryFile.path},
          );
        } catch (error, stackTrace) {
          _logger.warning(
            'settings.storage',
            'Unable to remove stale settings temporary file',
            code: 'settings_stale_temp_delete_failed',
            error: error,
            stackTrace: stackTrace,
            data: <String, Object?>{'path': _temporaryFile.path},
          );
        }
      }
      return main;
    }
    if (temporary != null) {
      try {
        if (await _file.exists()) {
          await _file.delete();
        }
        await _temporaryFile.rename(_file.path);
        _logger.warning(
          'settings.storage',
          'Settings recovered from temporary file',
          code: 'settings_recovered_from_temp',
          data: <String, Object?>{'path': _file.path},
        );
      } catch (error, stackTrace) {
        _logger.warning(
          'settings.storage',
          'Settings temporary file was valid but could not be promoted',
          code: 'settings_temp_promotion_failed',
          error: error,
          stackTrace: stackTrace,
          data: <String, Object?>{'path': _temporaryFile.path},
        );
      }
      return temporary;
    }

    _logger.error(
      'settings.storage',
      'All settings files were unreadable; defaults selected',
      code: 'settings_unreadable',
      data: <String, Object?>{
        'mainPath': _file.path,
        'temporaryPath': _temporaryFile.path,
      },
    );
    return const AppSettings();
  }

  Future<void> write(AppSettings settings) async {
    final operation = _logger.beginOperation(
      'settings.storage',
      'Settings write',
      data: <String, Object?>{'path': _file.path},
    );
    try {
      await _file.parent.create(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      await _temporaryFile.writeAsString(
        '${encoder.convert(settings.toJson())}\n',
        flush: true,
      );
      if (await _file.exists()) {
        await _file.delete();
      }
      await _temporaryFile.rename(_file.path);
      operation.complete(
        data: <String, Object?>{
          'watermarkEnabled': settings.watermarkEnabled,
          'loggingMinimumLevel': settings.loggingMinimumLevel.label,
          'consoleMinimumLevel': settings.consoleMinimumLevel.label,
          'consoleEnabled': settings.consoleEnabled,
          'fileEnabled': settings.fileEnabled,
        },
      );
    } catch (error, stackTrace) {
      operation.fail(error, stackTrace, code: 'settings_write_failed');
      rethrow;
    }
  }

  Future<bool> readWatermarkEnabled() async {
    return (await read()).watermarkEnabled;
  }

  Future<void> writeWatermarkEnabled(bool enabled) async {
    final current = await read();
    await write(current.copyWith(watermarkEnabled: enabled));
  }

  Future<void> writeLoggingConfiguration({
    required AppLogLevel minimumLevel,
    required AppLogLevel consoleMinimumLevel,
    required bool consoleEnabled,
    required bool fileEnabled,
  }) async {
    final current = await read();
    await write(
      current.copyWith(
        loggingMinimumLevel: minimumLevel,
        consoleMinimumLevel: consoleMinimumLevel,
        consoleEnabled: consoleEnabled,
        fileEnabled: fileEnabled,
      ),
    );
  }

  Future<AppSettings?> _tryRead(File file, {required bool temporary}) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      final settings = AppSettings.fromJson(decoded);
      _logger.debug(
        'settings.storage',
        'Settings file loaded',
        data: <String, Object?>{
          'path': file.path,
          'temporary': temporary,
          'loggingMinimumLevel': settings.loggingMinimumLevel.label,
          'fileEnabled': settings.fileEnabled,
        },
      );
      return settings;
    } catch (error, stackTrace) {
      _logger.warning(
        'settings.storage',
        'Settings file was unreadable',
        code: temporary
            ? 'settings_temp_unreadable'
            : 'settings_main_unreadable',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{
          'path': file.path,
          'temporary': temporary,
        },
      );
      return null;
    }
  }
}
