import 'dart:async';

enum LogLevel { debug, info, warn, error, fatal }

enum LogSource { dart, android, ios, ohos, javascript }

enum LogOutcome {
  started,
  succeeded,
  failed,
  cancelled,
  recovered,
  degraded,
  observed,
}

enum LogContextValueType { text, path, url }

class LogEventSchema {
  const LogEventSchema({required this.contextFields});

  final Map<String, LogContextValueType> contextFields;
}

class LogEventError {
  const LogEventError({
    required this.type,
    required this.message,
    required this.stackTrace,
  });

  final String type;
  final String message;
  final String stackTrace;
}

class LogEvent {
  const LogEvent({
    required this.timestampUtc,
    required this.monotonicMs,
    required this.sequence,
    required this.level,
    required this.source,
    required this.category,
    required this.event,
    required this.outcome,
    required this.appSessionId,
    this.code,
    this.operationId,
    this.durationMs,
    this.context,
    this.error,
  });

  final DateTime timestampUtc;
  final int monotonicMs;
  final int sequence;
  final LogLevel level;
  final LogSource source;
  final String category;
  final String event;
  final LogOutcome outcome;
  final String appSessionId;
  final String? code;
  final String? operationId;
  final int? durationMs;
  final Map<String, Object?>? context;
  final LogEventError? error;
}

abstract interface class LogOperation {
  String get operationId;

  Future<T> run<T>(FutureOr<T> Function() action);
}

abstract interface class AppLogger {
  void emit({
    required LogLevel level,
    required String category,
    required String event,
    required LogOutcome outcome,
    String? code,
    String? operationId,
    int? durationMs,
    Map<String, Object?>? context,
    Object? error,
    StackTrace? stackTrace,
  });

  LogOperation startOperation({
    required String operationId,
    required String category,
    required String startedEvent,
    required String finishedEvent,
    String? failureCode,
  });
}

class InMemoryAppLogger implements AppLogger {
  InMemoryAppLogger({
    required this.appSessionId,
    required this.source,
    this.appRoot,
    this.eventSchemas = const <String, LogEventSchema>{},
    this.recentEventCapacity = 500,
    int Function()? monotonicNowMs,
  }) : assert(recentEventCapacity > 0) {
    _stopwatch.start();
    _monotonicNowMs = monotonicNowMs ?? () => _stopwatch.elapsedMilliseconds;
    _monotonicOriginMs = _monotonicNowMs();
  }

  final String appSessionId;
  final LogSource source;
  final String? appRoot;
  final Map<String, LogEventSchema> eventSchemas;
  final int recentEventCapacity;
  final Stopwatch _stopwatch = Stopwatch();
  late final int Function() _monotonicNowMs;
  late final int _monotonicOriginMs;
  final List<LogEvent> _events = <LogEvent>[];
  int _nextSequence = 1;

  List<LogEvent> get events => List<LogEvent>.unmodifiable(_events);
  int evictedRecentEventCount = 0;
  int get _elapsedMs => _monotonicNowMs() - _monotonicOriginMs;

  @override
  void emit({
    required LogLevel level,
    required String category,
    required String event,
    required LogOutcome outcome,
    String? code,
    String? operationId,
    int? durationMs,
    Map<String, Object?>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _events.add(
      LogEvent(
        timestampUtc: DateTime.now().toUtc(),
        monotonicMs: _elapsedMs,
        sequence: _nextSequence,
        level: level,
        source: source,
        category: category,
        event: event,
        outcome: outcome,
        appSessionId: appSessionId,
        code: code,
        operationId: operationId,
        durationMs: durationMs,
        context: _sanitizeContext(event, context),
        error: error == null
            ? null
            : LogEventError(
                type: error.runtimeType.toString(),
                message: error.toString(),
                stackTrace: stackTrace?.toString() ?? '',
              ),
      ),
    );
    _nextSequence += 1;
    if (_events.length > recentEventCapacity) {
      _events.removeAt(0);
      evictedRecentEventCount += 1;
    }
  }

  @override
  LogOperation startOperation({
    required String operationId,
    required String category,
    required String startedEvent,
    required String finishedEvent,
    String? failureCode,
  }) {
    final startedAtMs = _elapsedMs;
    emit(
      level: LogLevel.info,
      category: category,
      event: startedEvent,
      outcome: LogOutcome.started,
      operationId: operationId,
    );
    return _InMemoryLogOperation(
      logger: this,
      operationId: operationId,
      category: category,
      finishedEvent: finishedEvent,
      failureCode: failureCode,
      startedAtMs: startedAtMs,
    );
  }

  Map<String, Object?>? _sanitizeContext(
    String event,
    Map<String, Object?>? context,
  ) {
    final schema = eventSchemas[event];
    if (schema == null || context == null) {
      return null;
    }
    final sanitized = <String, Object?>{};
    for (final field in schema.contextFields.entries) {
      final value = context[field.key];
      if (value is! String) {
        continue;
      }
      sanitized[field.key] = switch (field.value) {
        LogContextValueType.text => value,
        LogContextValueType.path => _sanitizePath(value),
        LogContextValueType.url => _sanitizeUrl(value),
      };
    }
    return Map<String, Object?>.unmodifiable(sanitized);
  }

  String _sanitizePath(String value) {
    final normalizedPath = value.replaceAll('\\', '/');
    final root = appRoot?.replaceAll('\\', '/');
    if (root == null || root.isEmpty) {
      return '<external-path>';
    }
    final normalizedRoot =
        root.endsWith('/') ? root.substring(0, root.length - 1) : root;
    final lowerPath = normalizedPath.toLowerCase();
    final lowerRoot = normalizedRoot.toLowerCase();
    if (lowerPath == lowerRoot) {
      return '<app-root>';
    }
    if (lowerPath.startsWith('$lowerRoot/')) {
      return '<app-root>${normalizedPath.substring(normalizedRoot.length)}';
    }
    return '<external-path>';
  }

  String _sanitizeUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '<invalid-url>';
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }
}

class _InMemoryLogOperation implements LogOperation {
  const _InMemoryLogOperation({
    required this.logger,
    required this.operationId,
    required this.category,
    required this.finishedEvent,
    required this.failureCode,
    required this.startedAtMs,
  });

  final InMemoryAppLogger logger;

  @override
  final String operationId;

  final String category;
  final String finishedEvent;
  final String? failureCode;
  final int startedAtMs;

  @override
  Future<T> run<T>(FutureOr<T> Function() action) async {
    try {
      final result = await action();
      logger.emit(
        level: LogLevel.info,
        category: category,
        event: finishedEvent,
        outcome: LogOutcome.succeeded,
        operationId: operationId,
        durationMs: logger._elapsedMs - startedAtMs,
      );
      return result;
    } catch (error, stackTrace) {
      logger.emit(
        level: LogLevel.error,
        category: category,
        event: finishedEvent,
        outcome: LogOutcome.failed,
        code: failureCode,
        operationId: operationId,
        durationMs: logger._elapsedMs - startedAtMs,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
