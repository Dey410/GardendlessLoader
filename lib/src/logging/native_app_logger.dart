import 'dart:async';

import 'package:flutter/services.dart';

import 'app_logger.dart';

class NativeAppLogger implements AppLogger {
  NativeAppLogger._({
    required MethodChannel channel,
    required this.appSessionId,
    required String? appRoot,
    required Map<String, LogEventSchema> eventSchemas,
    required bool degraded,
  })  : _channel = channel,
        _degraded = degraded {
    _mirror = InMemoryAppLogger(
      appSessionId: appSessionId,
      source: LogSource.dart,
      appRoot: appRoot,
      eventSchemas: eventSchemas,
      onEvent: _forward,
    );
  }

  static const channelName = 'io.github.dey410.gardendlessloader/app_logger';

  static Future<NativeAppLogger> initialize({
    MethodChannel channel = const MethodChannel(channelName),
    String? appRoot,
    Map<String, LogEventSchema> eventSchemas = const <String, LogEventSchema>{},
  }) async {
    try {
      final response = await channel.invokeMapMethod<Object?, Object?>(
        'initialize',
      );
      return NativeAppLogger._(
        channel: channel,
        appSessionId:
            response?['appSessionId'] as String? ?? _degradedSessionId(),
        appRoot: appRoot,
        eventSchemas: eventSchemas,
        degraded: response == null,
      );
    } catch (_) {
      return NativeAppLogger._(
        channel: channel,
        appSessionId: _degradedSessionId(),
        appRoot: appRoot,
        eventSchemas: eventSchemas,
        degraded: true,
      );
    }
  }

  final MethodChannel _channel;
  @override
  final String appSessionId;
  late final InMemoryAppLogger _mirror;
  bool _degraded;
  int _transportFailureCount = 0;

  List<LogEvent> get recentEvents => _mirror.events;
  bool get degraded => _degraded;

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
    _mirror.emit(
      level: level,
      category: category,
      event: event,
      outcome: outcome,
      code: code,
      message: message,
      gameSessionId: gameSessionId,
      operationId: operationId,
      durationMs: durationMs,
      context: context,
      error: error,
      stackTrace: stackTrace,
    );
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
    return _mirror.startOperation(
      operationId: operationId,
      category: category,
      startedEvent: startedEvent,
      finishedEvent: finishedEvent,
      failureCode: failureCode,
      gameSessionId: gameSessionId,
    );
  }

  @override
  Future<AppLogSnapshot> loadSnapshot({int limit = 500}) async {
    try {
      final response = await _channel.invokeMapMethod<Object?, Object?>(
        'snapshot',
        <String, Object?>{'limit': limit},
      );
      if (response != null) {
        return AppLogSnapshot.fromMap(response);
      }
    } catch (_) {
      _markTransportFailure();
    }
    return AppLogSnapshot(
      appSessionId: appSessionId,
      persisting: false,
      degraded: true,
      logDirectory: null,
      totalBytes: 0,
      writeFailureCount: _transportFailureCount,
      droppedByLevel: const <String, int>{},
      events: _mirror.events.map((event) => event.toJson()).toList(),
    );
  }

  @override
  Future<void> flush({Duration timeout = const Duration(milliseconds: 500)}) {
    return _invokeControl('flush', timeout);
  }

  @override
  Future<void> deleteHistory() => _invokeControl(
        'deleteHistory',
        const Duration(seconds: 2),
      );

  Future<void> endSession() => _invokeControl(
        'endSession',
        const Duration(milliseconds: 500),
      );

  void _forward(LogEvent event) {
    unawaited(
      _channel
          .invokeMethod<void>('emit', event.toJson())
          .catchError((Object _) => _markTransportFailure()),
    );
  }

  Future<void> _invokeControl(String method, Duration timeout) async {
    try {
      await _channel
          .invokeMethod<void>(method)
          .timeout(timeout, onTimeout: () => null);
    } catch (_) {
      _markTransportFailure();
    }
  }

  void _markTransportFailure() {
    _degraded = true;
    _transportFailureCount += 1;
  }

  static String _degradedSessionId() =>
      'degraded-${DateTime.now().toUtc().microsecondsSinceEpoch}';
}
