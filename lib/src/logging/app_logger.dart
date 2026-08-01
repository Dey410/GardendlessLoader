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

enum LogContextValueType { text, path, url, integer, boolean }

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

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'message': message,
        'stackTrace': stackTrace,
      };
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
    this.message,
    this.gameSessionId,
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
  final String? message;
  final String? gameSessionId;
  final String? operationId;
  final int? durationMs;
  final Map<String, Object?>? context;
  final LogEventError? error;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 1,
        'timestampUtc': timestampUtc.toIso8601String(),
        'monotonicMs': monotonicMs,
        'sequence': sequence,
        'level': level.name.toUpperCase(),
        'source': source.name,
        'category': category,
        'event': event,
        'outcome': outcome.name,
        'appSessionId': appSessionId,
        if (code != null) 'code': code,
        if (message != null) 'message': message,
        if (gameSessionId != null) 'gameSessionId': gameSessionId,
        if (operationId != null) 'operationId': operationId,
        if (durationMs != null) 'durationMs': durationMs,
        if (context != null) 'context': context,
        if (error != null) 'error': error!.toJson(),
      };
}

class AppLogSnapshot {
  const AppLogSnapshot({
    required this.appSessionId,
    required this.persisting,
    required this.degraded,
    required this.logDirectory,
    required this.totalBytes,
    required this.writeFailureCount,
    required this.droppedByLevel,
    required this.events,
  });

  factory AppLogSnapshot.fromMap(Map<Object?, Object?> map) {
    final rawEvents = map['events'];
    final rawDropped = map['droppedByLevel'];
    return AppLogSnapshot(
      appSessionId: map['appSessionId'] as String? ?? 'unavailable',
      persisting: map['persisting'] as bool? ?? false,
      degraded: map['degraded'] as bool? ?? true,
      logDirectory: map['logDirectory'] as String?,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      writeFailureCount: (map['writeFailureCount'] as num?)?.toInt() ?? 0,
      droppedByLevel: rawDropped is Map
          ? rawDropped.map(
              (key, value) => MapEntry(
                key.toString(),
                (value as num?)?.toInt() ?? 0,
              ),
            )
          : const <String, int>{},
      events: rawEvents is List
          ? rawEvents
              .whereType<Map>()
              .map(
                (event) => Map<String, Object?>.unmodifiable(
                  event.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList(growable: false)
          : const <Map<String, Object?>>[],
    );
  }

  final String appSessionId;
  final bool persisting;
  final bool degraded;
  final String? logDirectory;
  final int totalBytes;
  final int writeFailureCount;
  final Map<String, int> droppedByLevel;
  final List<Map<String, Object?>> events;
}

abstract interface class LogOperation {
  String get operationId;

  Future<T> run<T>(FutureOr<T> Function() action);
}

abstract interface class AppLogger {
  String get appSessionId;

  void emit({
    required LogLevel level,
    required String category,
    required String event,
    required LogOutcome outcome,
    String? code,
    String? message,
    String? gameSessionId,
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
    String? gameSessionId,
  });

  Future<AppLogSnapshot> loadSnapshot({int limit = 500});

  Future<void> flush({Duration timeout = const Duration(milliseconds: 500)});

  Future<void> deleteHistory();
}

class InMemoryAppLogger implements AppLogger {
  InMemoryAppLogger({
    required this.appSessionId,
    required this.source,
    this.appRoot,
    this.eventSchemas = const <String, LogEventSchema>{},
    this.recentEventCapacity = 500,
    this.onEvent,
    int Function()? monotonicNowMs,
  }) : assert(recentEventCapacity > 0) {
    _stopwatch.start();
    _monotonicNowMs = monotonicNowMs ?? () => _stopwatch.elapsedMilliseconds;
    _monotonicOriginMs = _monotonicNowMs();
  }

  @override
  final String appSessionId;
  final LogSource source;
  final String? appRoot;
  final Map<String, LogEventSchema> eventSchemas;
  final int recentEventCapacity;
  final void Function(LogEvent event)? onEvent;
  final Stopwatch _stopwatch = Stopwatch();
  late final int Function() _monotonicNowMs;
  late final int _monotonicOriginMs;
  final List<LogEvent> _events = <LogEvent>[];
  int _nextSequence = 1;

  List<LogEvent> get events => List<LogEvent>.unmodifiable(_events);
  int evictedRecentEventCount = 0;
  int get _elapsedMs => _monotonicNowMs() - _monotonicOriginMs;

  @override
  Future<AppLogSnapshot> loadSnapshot({int limit = 500}) async {
    final safeLimit = limit.clamp(1, recentEventCapacity);
    final first = (_events.length - safeLimit).clamp(0, _events.length);
    return AppLogSnapshot(
      appSessionId: appSessionId,
      persisting: false,
      degraded: false,
      logDirectory: null,
      totalBytes: 0,
      writeFailureCount: 0,
      droppedByLevel: const <String, int>{},
      events: _events
          .skip(first)
          .map((event) => event.toJson())
          .toList(growable: false),
    );
  }

  @override
  Future<void> flush(
      {Duration timeout = const Duration(milliseconds: 500)}) async {}

  @override
  Future<void> deleteHistory() async {
    _events.clear();
  }

  @override
  void emit({
    required LogLevel level,
    required String category,
    required String event,
    required LogOutcome outcome,
    String? code,
    String? message,
    String? gameSessionId,
    String? operationId,
    int? durationMs,
    Map<String, Object?>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final logEvent = LogEvent(
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
      message: message == null ? null : _sanitizeText(message, 2048),
      gameSessionId: gameSessionId,
      operationId: operationId,
      durationMs: durationMs,
      context: _sanitizeContext(event, context),
      error: error == null
          ? null
          : LogEventError(
              type: error.runtimeType.toString(),
              message: _sanitizeText(error.toString(), 4096),
              stackTrace: _sanitizeText(stackTrace?.toString() ?? '', 8192),
            ),
    );
    _events.add(logEvent);
    _nextSequence += 1;
    if (_events.length > recentEventCapacity) {
      _events.removeAt(0);
      evictedRecentEventCount += 1;
    }
    onEvent?.call(logEvent);
  }

  @override
  LogOperation startOperation({
    required String operationId,
    required String category,
    required String startedEvent,
    required String finishedEvent,
    String? failureCode,
    String? gameSessionId,
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
      gameSessionId: gameSessionId,
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
      final sanitizedValue = switch (field.value) {
        LogContextValueType.text when value is String =>
          _sanitizeText(value, 2048),
        LogContextValueType.path when value is String => _sanitizePath(value),
        LogContextValueType.url when value is String => _sanitizeUrl(value),
        LogContextValueType.integer when value is int => value,
        LogContextValueType.boolean when value is bool => value,
        _ => null,
      };
      if (sanitizedValue != null) {
        sanitized[field.key] = sanitizedValue;
      }
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

  String _sanitizeText(String value, int maxLength) {
    var sanitized = value
        .replaceAllMapped(
          RegExp(
            r'(token|authorization|cookie|password|passwd|secret|apiKey)\s*[:=]\s*[^\s,;]+',
            caseSensitive: false,
          ),
          (match) => '${match.group(1)}=<redacted>',
        )
        .replaceAll(RegExp(r'[A-Za-z]:\\Users\\[^\\\s]+'), '<user-home>')
        .replaceAll(RegExp(r'/(Users|home)/[^/\s]+'), '/<user-home>');
    if (sanitized.length > maxLength) {
      sanitized = '${sanitized.substring(0, maxLength)}...[truncated]';
    }
    return sanitized;
  }
}

class _InMemoryLogOperation implements LogOperation {
  const _InMemoryLogOperation({
    required this.logger,
    required this.operationId,
    required this.category,
    required this.finishedEvent,
    required this.failureCode,
    required this.gameSessionId,
    required this.startedAtMs,
  });

  final InMemoryAppLogger logger;

  @override
  final String operationId;

  final String category;
  final String finishedEvent;
  final String? failureCode;
  final String? gameSessionId;
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
        gameSessionId: gameSessionId,
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
        gameSessionId: gameSessionId,
        operationId: operationId,
        durationMs: logger._elapsedMs - startedAtMs,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
