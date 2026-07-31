import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/app_logger.dart';

void main() {
  group('AppLogger', () {
    test('retains only the configured number of recent entries', () {
      final logger = AppLogger(
        memoryCapacity: 2,
        clock: () => DateTime.utc(2026, 7, 31),
        random: Random(1),
      );

      logger.info('test', 'first');
      logger.warning('test', 'second');
      logger.error('test', 'third');

      final entries = logger.recentEntries();
      expect(entries, hasLength(2));
      expect(entries.first.message, 'second');
      expect(entries.last.message, 'third');
    });

    test('redacts sensitive structured fields', () {
      final logger = AppLogger(
        clock: () => DateTime.utc(2026, 7, 31),
        random: Random(1),
      );

      logger.info(
        'network',
        'request prepared',
        data: <String, Object?>{
          'authorization': 'Bearer secret',
          'apiToken': 'secret-token',
          'statusCode': 200,
        },
      );

      final entry = logger.recentEntries().single;
      expect(entry.data['authorization'], '<redacted>');
      expect(entry.data['apiToken'], '<redacted>');
      expect(entry.data['statusCode'], 200);
    });

    test('records error context and stack trace', () {
      final logger = AppLogger(
        clock: () => DateTime.utc(2026, 7, 31),
        random: Random(1),
      );
      final stackTrace = StackTrace.current;

      logger.error(
        'import',
        'Import failed',
        operationId: 'import-1',
        code: 'import_failed',
        error: StateError('broken archive'),
        stackTrace: stackTrace,
      );

      final entry = logger.latestError;
      expect(entry, isNotNull);
      expect(entry!.operationId, 'import-1');
      expect(entry.code, 'import_failed');
      expect(entry.error, contains('broken archive'));
      expect(entry.stackTrace, isNotEmpty);
      expect(logger.diagnosticsText(), contains('[code=import_failed]'));
    });

    test('persists JSONL entries and exposes active log path', () async {
      final root = await Directory.systemTemp.createTemp('app_logger_test_');
      addTearDown(() => root.delete(recursive: true));
      final logger = AppLogger(
        clock: () => DateTime.utc(2026, 7, 31),
        random: Random(1),
      );

      logger.info('startup', 'buffered before initialization');
      await logger.initialize(directory: root);
      logger.warning(
        'network',
        'Remote content unavailable',
        code: 'remote_unavailable',
        data: <String, Object?>{'fallback': true},
      );
      await logger.flush();

      expect(logger.isPersistent, isTrue);
      expect(logger.activeLogPath, isNotNull);
      final file = File(logger.activeLogPath!);
      expect(await file.exists(), isTrue);
      final lines = await file.readAsLines();
      expect(lines.length, greaterThanOrEqualTo(3));
      final decoded = lines.map(jsonDecode).cast<Map<String, dynamic>>().toList();
      expect(
        decoded.any((entry) => entry['message'] == 'buffered before initialization'),
        isTrue,
      );
      expect(
        decoded.any((entry) => entry['code'] == 'remote_unavailable'),
        isTrue,
      );
    });
  });
}
