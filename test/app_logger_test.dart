import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/logging/app_logger.dart';

void main() {
  test('records structured events in submission order', () {
    final logger = InMemoryAppLogger(
      appSessionId: 'app-session-1',
      source: LogSource.dart,
    );

    logger.emit(
      level: LogLevel.info,
      category: 'resource.import',
      event: 'resource_import_started',
      outcome: LogOutcome.started,
      operationId: 'resource-import-12',
    );
    logger.emit(
      level: LogLevel.info,
      category: 'resource.import',
      event: 'resource_import_finished',
      outcome: LogOutcome.succeeded,
      operationId: 'resource-import-12',
      durationMs: 1360,
    );

    expect(
      logger.events
          .map(
            (event) => <String, Object?>{
              'sequence': event.sequence,
              'source': event.source.name,
              'level': event.level.name,
              'category': event.category,
              'event': event.event,
              'outcome': event.outcome.name,
              'appSessionId': event.appSessionId,
              'operationId': event.operationId,
              'durationMs': event.durationMs,
            },
          )
          .toList(),
      <Map<String, Object?>>[
        {
          'sequence': 1,
          'source': 'dart',
          'level': 'info',
          'category': 'resource.import',
          'event': 'resource_import_started',
          'outcome': 'started',
          'appSessionId': 'app-session-1',
          'operationId': 'resource-import-12',
          'durationMs': null,
        },
        {
          'sequence': 2,
          'source': 'dart',
          'level': 'info',
          'category': 'resource.import',
          'event': 'resource_import_finished',
          'outcome': 'succeeded',
          'appSessionId': 'app-session-1',
          'operationId': 'resource-import-12',
          'durationMs': 1360,
        },
      ],
    );
  });

  test('keeps only allowed context fields and sanitizes their values', () {
    final logger = InMemoryAppLogger(
      appSessionId: 'app-session-1',
      source: LogSource.dart,
      appRoot: r'C:\Users\Alice\GardendlessLoader',
      eventSchemas: {
        'resource_validation_failed': LogEventSchema(
          contextFields: {
            'path': LogContextValueType.path,
            'url': LogContextValueType.url,
            'stage': LogContextValueType.text,
          },
        ),
      },
    );

    logger.emit(
      level: LogLevel.error,
      category: 'resource.import',
      event: 'resource_validation_failed',
      outcome: LogOutcome.failed,
      context: {
        'path': r'C:\Users\Alice\GardendlessLoader\slot-b\src\import-map.json',
        'url': 'https://example.com/update?token=secret#result',
        'stage': 'validating',
        'authorization': 'Bearer secret',
      },
    );

    expect(
      logger.events.single.context,
      <String, Object?>{
        'path': '<app-root>/slot-b/src/import-map.json',
        'url': 'https://example.com/update',
        'stage': 'validating',
      },
    );
  });

  test('operation records start and success with monotonic duration', () async {
    var monotonicNowMs = 500;
    final logger = InMemoryAppLogger(
      appSessionId: 'app-session-1',
      source: LogSource.dart,
      monotonicNowMs: () => monotonicNowMs,
    );
    final operation = logger.startOperation(
      operationId: 'resource-import-12',
      category: 'resource.import',
      startedEvent: 'resource_import_started',
      finishedEvent: 'resource_import_finished',
    );

    monotonicNowMs = 1860;
    final result = await operation.run(() async => 'imported');

    expect(
      <String, Object?>{
        'result': result,
        'events': logger.events
            .map(
              (event) => <String, Object?>{
                'event': event.event,
                'outcome': event.outcome.name,
                'operationId': event.operationId,
                'monotonicMs': event.monotonicMs,
                'durationMs': event.durationMs,
              },
            )
            .toList(),
      },
      <String, Object?>{
        'result': 'imported',
        'events': <Map<String, Object?>>[
          {
            'event': 'resource_import_started',
            'outcome': 'started',
            'operationId': 'resource-import-12',
            'monotonicMs': 0,
            'durationMs': null,
          },
          {
            'event': 'resource_import_finished',
            'outcome': 'succeeded',
            'operationId': 'resource-import-12',
            'monotonicMs': 1360,
            'durationMs': 1360,
          },
        ],
      },
    );
  });

  test('operation records failure without replacing the exception', () async {
    var monotonicNowMs = 100;
    final logger = InMemoryAppLogger(
      appSessionId: 'app-session-1',
      source: LogSource.dart,
      monotonicNowMs: () => monotonicNowMs,
    );
    final operation = logger.startOperation(
      operationId: 'resource-import-12',
      category: 'resource.import',
      startedEvent: 'resource_import_started',
      finishedEvent: 'resource_import_finished',
      failureCode: 'resource_missing_import_map',
    );
    final failure = StateError('missing import map');

    monotonicNowMs = 420;
    Object? caught;
    try {
      await operation.run<void>(() => throw failure);
    } catch (error) {
      caught = error;
    }

    final failedEvent = logger.events.last;
    expect(
      <String, Object?>{
        'sameException': identical(caught, failure),
        'event': failedEvent.event,
        'outcome': failedEvent.outcome.name,
        'code': failedEvent.code,
        'errorType': failedEvent.error?.type,
        'durationMs': failedEvent.durationMs,
      },
      <String, Object?>{
        'sameException': true,
        'event': 'resource_import_finished',
        'outcome': 'failed',
        'code': 'resource_missing_import_map',
        'errorType': 'StateError',
        'durationMs': 320,
      },
    );
  });

  test('recent event buffer keeps the newest events within its capacity', () {
    final logger = InMemoryAppLogger(
      appSessionId: 'app-session-1',
      source: LogSource.dart,
      recentEventCapacity: 2,
    );

    for (final event in <String>[
      'first_event',
      'second_event',
      'third_event'
    ]) {
      logger.emit(
        level: LogLevel.info,
        category: 'app.lifecycle',
        event: event,
        outcome: LogOutcome.observed,
      );
    }

    expect(
      <String, Object?>{
        'events': logger.events
            .map((event) => '${event.sequence}:${event.event}')
            .toList(),
        'evicted': logger.evictedRecentEventCount,
      },
      <String, Object?>{
        'events': <String>['2:second_event', '3:third_event'],
        'evicted': 1,
      },
    );
  });

  test('snapshot limit returns the newest events', () async {
    final logger = InMemoryAppLogger(
      appSessionId: 'session-1',
      source: LogSource.dart,
    );
    for (var index = 0; index < 4; index += 1) {
      logger.emit(
        level: LogLevel.info,
        category: 'test',
        event: 'event_$index',
        outcome: LogOutcome.observed,
      );
    }

    final snapshot = await logger.loadSnapshot(limit: 2);

    expect(
      snapshot.events.map((event) => event['event']),
      <String>['event_2', 'event_3'],
    );
  });
}
