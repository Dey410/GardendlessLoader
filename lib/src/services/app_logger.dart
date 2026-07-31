import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum AppLogLevel {
  debug(10, 'DEBUG'),
  info(20, 'INFO'),
  warning(30, 'WARN'),
  error(40, 'ERROR'),
  fatal(50, 'FATAL');

  const AppLogLevel(this.priority, this.label);

  final int priority;
  final String label;
}

class AppLogEntry {
  const AppLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    required this.sessionId,
    required this.sequence,
    this.operationId,
    this.code,
    this.data = const <String, Object?>{},
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String category;
  final String message;
  final String sessionId;
  final int sequence;
  final String? operationId;
  final String? code;
  final Map<String, Object?> data;
  final String? error;
  final String? stackTrace;

  Map<String, Object?> toJson() => <String, Object?>{
        'timestamp': timestamp.toUtc().toIso8601String(),
        'level': level.label,
        'category': category,
        'message': message,
        'sessionId': sessionId,
        'sequence': sequence,
        if (operationId != null) 'operationId': operationId,
        if (code != null) 'code': code,
        if (data.isNotEmpty) 'data': data,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stackTrace': stackTrace,
      };

  String toDisplayText() {
    final buffer = StringBuffer()
      ..write(timestamp.toLocal().toIso8601String())
      ..write(' [${level.label}]')
      ..write(' [$category]');
    if (operationId != null) {
      buffer.write(' [op=$operationId]');
    }
    if (code != null) {
      buffer.write(' [code=$code]');
    }
    buffer.write(' $message');
    if (data.isNotEmpty) {
      buffer.write(' data=${jsonEncode(data)}');
    }
    if (error != null) {
      buffer.write('\n  error=$error');
    }
    if (stackTrace != null) {
      buffer.write('\n  stack=$stackTrace');
    }
    return buffer.toString();
  }

  String get errorSummary {
    final parts = <String>[
      if (code != null) code!,
      message,
      if (error != null) error!,
    ];
    return parts.join(': ');
  }
}

class AppLogger {
  AppLogger({
    int memoryCapacity = 250,
    int maxFileBytes = 2 * 1024 * 1024,
    int retainedFileCount = 4,
    DateTime Function()? clock,
    Random? random,
  })  : assert(memoryCapacity > 0),
        assert(maxFileBytes > 0),
        assert(retainedFileCount >= 0),
        _memoryCapacity = memoryCapacity,
        _maxFileBytes = maxFileBytes,
        _retainedFileCount = retainedFileCount,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure() {
    _sessionId = _createSessionId();
  }

  static final AppLogger instance = AppLogger();
  static const String activeFileName = 'app-current.jsonl';

  final int _memoryCapacity;
  final int _maxFileBytes;
  final int _retainedFileCount;
  final DateTime Function() _clock;
  final Random _random;
  final ListQueue<AppLogEntry> _entries = ListQueue<AppLogEntry>();
  final List<AppLogEntry> _pendingDiskEntries = <AppLogEntry>[];

  late final String _sessionId;
  Directory? _directory;
  File? _activeFile;
  Future<void> _writeQueue = Future<void>.value();
  int _sequence = 0;
  int _operationSequence = 0;
  bool _initialized = false;

  String get sessionId => _sessionId;
  bool get isPersistent => _initialized && _activeFile != null;
  String? get activeLogPath => _activeFile?.path;

  AppLogEntry? get latestError {
    for (final entry in _entries.toList(growable: false).reversed) {
      if (entry.level.priority >= AppLogLevel.error.priority) {
        return entry;
      }
    }
    return null;
  }

  Future<void> initialize({required Directory directory}) async {
    final normalizedPath = p.normalize(directory.absolute.path);
    if (_initialized &&
        _directory != null &&
        p.equals(p.normalize(_directory!.absolute.path), normalizedPath)) {
      return;
    }

    try {
      await flush();
      await directory.create(recursive: true);
      _directory = directory;
      _activeFile = File(p.join(directory.path, activeFileName));
      _initialized = true;

      final pending = List<AppLogEntry>.of(_pendingDiskEntries);
      _pendingDiskEntries.clear();
      for (final entry in pending) {
        _enqueueWrite(entry);
      }

      info(
        'logging.lifecycle',
        'Persistent logging initialized',
        data: <String, Object?>{
          'directory': directory.path,
          'activeFile': _activeFile!.path,
          'memoryCapacity': _memoryCapacity,
          'maxFileBytes': _maxFileBytes,
          'retainedFileCount': _retainedFileCount,
        },
      );
    } catch (error, stackTrace) {
      _initialized = false;
      _directory = null;
      _activeFile = null;
      debugPrint('AppLogger initialization failed: $error\n$stackTrace');
    }
  }

  String nextOperationId(String category) {
    _operationSequence += 1;
    final normalized = category
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final prefix = normalized.isEmpty ? 'operation' : normalized;
    return '$prefix-${_sessionId.substring(0, 8)}-$_operationSequence';
  }

  void debug(
    String category,
    String message, {
    String? operationId,
    String? code,
    Map<String, Object?> data = const <String, Object?>{},
  }) =>
      log(
        AppLogLevel.debug,
        category,
        message,
        operationId: operationId,
        code: code,
        data: data,
      );

  void info(
    String category,
    String message, {
    String? operationId,
    String? code,
    Map<String, Object?> data = const <String, Object?>{},
  }) =>
      log(
        AppLogLevel.info,
        category,
        message,
        operationId: operationId,
        code: code,
        data: data,
      );

  void warning(
    String category,
    String message, {
    String? operationId,
    String? code,
    Map<String, Object?> data = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        AppLogLevel.warning,
        category,
        message,
        operationId: operationId,
        code: code,
        data: data,
        error: error,
        stackTrace: stackTrace,
      );

  void error(
    String category,
    String message, {
    String? operationId,
    String? code,
    Map<String, Object?> data = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        AppLogLevel.error,
        category,
        message,
        operationId: operationId,
        code: code,
        data: data,
        error: error,
        stackTrace: stackTrace,
      );

  void fatal(
    String category,
    String message, {
    String? operationId,
    String? code,
    Map<String, Object?> data = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        AppLogLevel.fatal,
        category,
        message,
        operationId: operationId,
        code: code,
        data: data,
        error: error,
        stackTrace: stackTrace,
      );

  void log(
    AppLogLevel level,
    String category,
    String message, {
    String? operationId,
    String? code,
    Map<String, Object?> data = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    _sequence += 1;
    final entry = AppLogEntry(
      timestamp: _clock(),
      level: level,
      category: category.trim().isEmpty ? 'app' : category.trim(),
      message: _truncate(message.trim().isEmpty ? '-' : message.trim(), 4000),
      sessionId: _sessionId,
      sequence: _sequence,
      operationId: _nullableTrimmed(operationId),
      code: _nullableTrimmed(code),
      data: _sanitizeMap(data),
      error: error == null ? null : _truncate(error.toString(), 4000),
      stackTrace: stackTrace == null
          ? null
          : _truncateStackTrace(stackTrace.toString()),
    );

    _entries.addLast(entry);
    while (_entries.length > _memoryCapacity) {
      _entries.removeFirst();
    }

    if (_initialized) {
      _enqueueWrite(entry);
    } else {
      _pendingDiskEntries.add(entry);
    }

    if (kDebugMode || level.priority >= AppLogLevel.warning.priority) {
      debugPrint(entry.toDisplayText());
    }
  }

  Future<T> trace<T>({
    required String category,
    required String operation,
    required Future<T> Function(String operationId) action,
    String? operationId,
    String? failureCode,
    Map<String, Object?> data = const <String, Object?>{},
  }) async {
    final resolvedOperationId = operationId ?? nextOperationId(operation);
    final stopwatch = Stopwatch()..start();
    info(
      category,
      '$operation started',
      operationId: resolvedOperationId,
      data: data,
    );
    try {
      final result = await action(resolvedOperationId);
      stopwatch.stop();
      info(
        category,
        '$operation completed',
        operationId: resolvedOperationId,
        data: <String, Object?>{
          ...data,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      return result;
    } catch (error, stackTrace) {
      stopwatch.stop();
      this.error(
        category,
        '$operation failed',
        operationId: resolvedOperationId,
        code: failureCode,
        data: <String, Object?>{
          ...data,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  List<AppLogEntry> recentEntries({
    int limit = 120,
    AppLogLevel minLevel = AppLogLevel.debug,
  }) {
    if (limit <= 0) {
      return const <AppLogEntry>[];
    }
    final filtered = _entries
        .where((entry) => entry.level.priority >= minLevel.priority)
        .toList(growable: false);
    final start = filtered.length > limit ? filtered.length - limit : 0;
    return List<AppLogEntry>.unmodifiable(filtered.sublist(start));
  }

  String diagnosticsText({
    int limit = 120,
    AppLogLevel minLevel = AppLogLevel.debug,
  }) {
    final entries = recentEntries(limit: limit, minLevel: minLevel);
    if (entries.isEmpty) {
      return '[INFO] [logging] No log entries have been recorded';
    }
    return entries.map((entry) => entry.toDisplayText()).join('\n');
  }

  Future<void> flush() => _writeQueue;

  void _enqueueWrite(AppLogEntry entry) {
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _appendToDisk(entry);
      } catch (error, stackTrace) {
        debugPrint('AppLogger write failed: $error\n$stackTrace');
      }
    });
  }

  Future<void> _appendToDisk(AppLogEntry entry) async {
    final file = _activeFile;
    if (!_initialized || file == null) {
      return;
    }

    final line = '${jsonEncode(entry.toJson())}\n';
    await _rotateIfNeeded(utf8.encode(line).length);
    await file.writeAsString(
      line,
      mode: FileMode.append,
      flush: entry.level.priority >= AppLogLevel.error.priority,
    );
  }

  Future<void> _rotateIfNeeded(int incomingBytes) async {
    final file = _activeFile;
    final directory = _directory;
    if (file == null || directory == null || !await file.exists()) {
      return;
    }
    if (await file.length() + incomingBytes <= _maxFileBytes) {
      return;
    }

    final baseName = 'app-${_fileTimestamp(_clock())}';
    var candidate = File(p.join(directory.path, '$baseName.jsonl'));
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = File(p.join(directory.path, '$baseName-$suffix.jsonl'));
      suffix += 1;
    }
    await file.rename(candidate.path);
    await _pruneRotatedFiles();
  }

  Future<void> _pruneRotatedFiles() async {
    final directory = _directory;
    if (directory == null) {
      return;
    }

    final files = await directory
        .list(followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) {
      final name = p.basename(file.path);
      return name.startsWith('app-') && name != activeFileName;
    }).toList();

    final modified = <File, DateTime>{};
    for (final file in files) {
      modified[file] = await file.lastModified();
    }
    files.sort((left, right) => modified[right]!.compareTo(modified[left]!));
    for (final file in files.skip(_retainedFileCount)) {
      await file.delete();
    }
  }

  Map<String, Object?> _sanitizeMap(Map<String, Object?> source) {
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      result[entry.key] = _isSensitiveKey(entry.key)
          ? '<redacted>'
          : _sanitizeValue(entry.value, depth: 0);
    }
    return Map<String, Object?>.unmodifiable(result);
  }

  Object? _sanitizeValue(Object? value, {required int depth}) {
    if (value == null || value is num || value is bool) {
      return value;
    }
    if (depth >= 4) {
      return '<max-depth>';
    }
    if (value is String) {
      return _truncate(value, 2000);
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Uri) {
      return value.replace(query: '', fragment: '').toString();
    }
    if (value is Map) {
      final result = <String, Object?>{};
      var count = 0;
      for (final entry in value.entries) {
        if (count >= 30) {
          result['...'] = '<truncated>';
          break;
        }
        final key = entry.key.toString();
        result[key] = _isSensitiveKey(key)
            ? '<redacted>'
            : _sanitizeValue(entry.value, depth: depth + 1);
        count += 1;
      }
      return result;
    }
    if (value is Iterable) {
      return value
          .take(30)
          .map((item) => _sanitizeValue(item, depth: depth + 1))
          .toList(growable: false);
    }
    return _truncate(value.toString(), 2000);
  }

  bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized == 'authorization' ||
        normalized == 'cookie' ||
        normalized == 'setcookie' ||
        normalized.contains('password') ||
        normalized.contains('passwd') ||
        normalized.contains('secret') ||
        normalized.endsWith('token') ||
        normalized == 'apikey' ||
        normalized.endsWith('privatekey');
  }

  String _truncateStackTrace(String value) {
    final lines = value.split('\n');
    final selected = lines.length > 40 ? lines.take(40).toList() : lines;
    return _truncate(selected.join('\n'), 12000);
  }

  String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}…';
  }

  String? _nullableTrimmed(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _createSessionId() {
    final timestamp = _fileTimestamp(_clock());
    final randomPart =
        _random.nextInt(0x1000000).toRadixString(16).padLeft(6, '0');
    return '$timestamp-$randomPart';
  }

  String _fileTimestamp(DateTime value) {
    final utc = value.toUtc();
    String two(int number) => number.toString().padLeft(2, '0');
    String three(int number) => number.toString().padLeft(3, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}-'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}-'
        '${three(utc.millisecond)}';
  }
}
