import 'logging_app_controller.dart';
import 'services/app_logger.dart';
import 'services/app_settings_store.dart';

class PersistentLoggingAppController extends LoggingAppController {
  PersistentLoggingAppController({AppLogger? logger})
      : _logger = logger ?? AppLogger.instance,
        super(logger: logger ?? AppLogger.instance);

  final AppLogger _logger;
  AppSettingsStore? _settingsStore;

  @override
  Future<void> initialize() async {
    await super.initialize();
    final resolvedPaths = paths;
    if (!initialized || resolvedPaths == null) {
      return;
    }

    final operation = _logger.beginOperation(
      'logging.configuration',
      'Persistent logging configuration load',
      data: <String, Object?>{
        'settingsPath': resolvedPaths.appSettingsFile.path,
      },
    );
    try {
      final store = AppSettingsStore(
        resolvedPaths.appSettingsFile,
        logger: _logger,
      );
      _settingsStore = store;
      final settings = await store.read();
      _logger.configure(
        minimumLevel: settings.loggingMinimumLevel,
        consoleMinimumLevel: settings.consoleMinimumLevel,
        consoleEnabled: settings.consoleEnabled,
        fileEnabled: settings.fileEnabled,
      );
      operation.complete(
        data: <String, Object?>{
          'minimumLevel': settings.loggingMinimumLevel.label,
          'consoleMinimumLevel': settings.consoleMinimumLevel.label,
          'consoleEnabled': settings.consoleEnabled,
          'fileEnabled': settings.fileEnabled,
        },
      );
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'logging_configuration_load_failed',
        level: AppLogLevel.warning,
      );
    }
  }

  Future<void> setLoggingConfiguration({
    required AppLogLevel minimumLevel,
    required AppLogLevel consoleMinimumLevel,
    required bool consoleEnabled,
    required bool fileEnabled,
  }) async {
    final store = _settingsStore;
    if (store == null) {
      throw StateError('Logging settings store is not initialized');
    }
    final operation = _logger.beginOperation(
      'logging.configuration',
      'Persistent logging configuration update',
      data: <String, Object?>{
        'minimumLevel': minimumLevel.label,
        'consoleMinimumLevel': consoleMinimumLevel.label,
        'consoleEnabled': consoleEnabled,
        'fileEnabled': fileEnabled,
      },
    );
    try {
      await store.writeLoggingConfiguration(
        minimumLevel: minimumLevel,
        consoleMinimumLevel: consoleMinimumLevel,
        consoleEnabled: consoleEnabled,
        fileEnabled: fileEnabled,
      );
      _logger.configure(
        minimumLevel: minimumLevel,
        consoleMinimumLevel: consoleMinimumLevel,
        consoleEnabled: consoleEnabled,
        fileEnabled: fileEnabled,
      );
      operation.complete();
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'logging_configuration_update_failed',
      );
      rethrow;
    }
  }
}
