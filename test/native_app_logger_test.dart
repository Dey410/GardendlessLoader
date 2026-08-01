import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/logging/app_logger.dart';
import 'package:gardendless_loader/src/logging/native_app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forwards sanitized structured events to the native owner', () async {
    const channel = MethodChannel('test/native-app-logger');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') {
        return <String, Object?>{'appSessionId': 'native-session-1'};
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final logger = await NativeAppLogger.initialize(
      channel: channel,
      appRoot: r'C:\Users\Alice\GardendlessLoader',
      eventSchemas: const <String, LogEventSchema>{
        'resource_validation_failed': LogEventSchema(
          contextFields: <String, LogContextValueType>{
            'path': LogContextValueType.path,
          },
        ),
      },
    );

    logger.emit(
      level: LogLevel.error,
      category: 'resource.import',
      event: 'resource_validation_failed',
      outcome: LogOutcome.failed,
      code: 'resource_missing_import_map',
      context: <String, Object?>{
        'path': r'C:\Users\Alice\GardendlessLoader\slot-b\src\import-map.json',
        'token': 'secret',
      },
    );
    await Future<void>.delayed(Duration.zero);

    final payload = calls.last.arguments as Map<Object?, Object?>;
    expect(
      <String, Object?>{
        'method': calls.last.method,
        'appSessionId': logger.appSessionId,
        'level': payload['level'],
        'event': payload['event'],
        'code': payload['code'],
        'context': payload['context'],
      },
      <String, Object?>{
        'method': 'emit',
        'appSessionId': 'native-session-1',
        'level': 'ERROR',
        'event': 'resource_validation_failed',
        'code': 'resource_missing_import_map',
        'context': <String, Object?>{
          'path': '<app-root>/slot-b/src/import-map.json',
        },
      },
    );
  });

  test('falls back to an in-memory snapshot when native logging is absent',
      () async {
    const channel = MethodChannel('test/missing-native-app-logger');
    final logger = await NativeAppLogger.initialize(channel: channel);

    logger.emit(
      level: LogLevel.warn,
      category: 'app.lifecycle',
      event: 'fallback_observed',
      outcome: LogOutcome.degraded,
    );
    final snapshot = await logger.loadSnapshot();

    expect(
      <String, Object?>{
        'degraded': snapshot.degraded,
        'persisting': snapshot.persisting,
        'event': snapshot.events.single['event'],
      },
      <String, Object?>{
        'degraded': true,
        'persisting': false,
        'event': 'fallback_observed',
      },
    );
  });
}
