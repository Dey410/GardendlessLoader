import 'dart:async';

import 'package:flutter/services.dart';

import 'app_logger.dart';

class NativeAppLogger implements AppLogger {
  NativeAppLogger._({
    required this.appSessionId,
    required String? appRoot,
    required Map<String, LogEventSchema> eventSchemas,
  }) : _sanitizer = LogSanitizer(appRoot: appRoot, eventSchemas: eventSchemas);

  static const channelName = 'io.github.dey410.gardendlessloader/app_logger';
  static const MethodChannel _channel = MethodChannel(channelName);

  static Future<NativeAppLogger> initialize({
    String? appRoot,
    Map<String, LogEventSchema> eventSchemas = const <String, LogEventSchema>{},
  }) async {
    final response =
        await _channel.invokeMapMethod<Object?, Object?>('initialize');
    final sessionId = response?['appSessionId'];
    if (sessionId is! String || sessionId.isEmpty) {
      throw const FormatException('Native logger returned no app session');
    }
    return NativeAppLogger._(
      appSessionId: sessionId,
      appRoot: appRoot,
      eventSchemas: eventSchemas,
    );
  }

  final LogSanitizer _sanitizer;
  @override
  final String appSessionId;

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
    final payload = <String, Object?>{
      'schemaVersion': 1,
      'source': LogSource.dart.name,
      'level': level.name.toUpperCase(),
      'category': category,
      'event': event,
      'outcome': outcome.name,
      'appSessionId': appSessionId,
      if (code != null) 'code': code,
      if (message != null) 'message': _sanitizer.sanitizeText(message, 2048),
      if (gameSessionId != null) 'gameSessionId': gameSessionId,
      if (operationId != null) 'operationId': operationId,
      if (durationMs != null) 'durationMs': durationMs,
      if (context != null)
        'context': _sanitizer.sanitizeContext(event, context),
      if (error != null)
        'error': LogEventError(
          type: error.runtimeType.toString(),
          message: _sanitizer.sanitizeText(error.toString(), 4096),
          stackTrace:
              _sanitizer.sanitizeText(stackTrace?.toString() ?? '', 8192),
        ).toJson(),
    };
    // Logging must not replace an application failure. Native owns all retained
    // events and its snapshot reports persistence health.
    unawaited(
        _channel.invokeMethod<void>('emit', payload).catchError((Object _) {}));
  }

  @override
  LogOperation startOperation({
    required String operationId,
    required String category,
    required String startedEvent,
    required String finishedEvent,
    String? failureCode,
    String? gameSessionId,
  }) =>
      startLogOperation(
        logger: this,
        operationId: operationId,
        category: category,
        startedEvent: startedEvent,
        finishedEvent: finishedEvent,
        failureCode: failureCode,
        gameSessionId: gameSessionId,
      );

  @override
  Future<AppLogSnapshot> loadSnapshot({int limit = 500}) async {
    final response = await _channel.invokeMapMethod<Object?, Object?>(
      'snapshot',
      <String, Object?>{'limit': limit},
    );
    if (response == null) {
      throw const FormatException('Native logger returned no snapshot');
    }
    return AppLogSnapshot.fromMap(response);
  }

  @override
  Future<void> flush({Duration timeout = const Duration(milliseconds: 500)}) =>
      _channel.invokeMethod<void>('flush').timeout(timeout);

  @override
  Future<void> deleteHistory() => _channel
      .invokeMethod<void>('deleteHistory')
      .timeout(const Duration(seconds: 2));
}
