import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum AppLogLevel {
  trace(0, 'TRACE'),
  debug(10, 'DEBUG'),
  info(20, 'INFO'),
  warning(30, 'WARN'),
  error(40, 'ERROR'),
  fatal(50, 'FATAL');

  const AppLogLevel(this.priority, this.label);

  final int priority;
  final String label;

  static AppLogLevel? tryParse(Object? value) {
    final normalized = value?.toString().trim().toUpperCase();
    for (final level in values) {
      if (level.label == normalized || level.name.toUpperCase() == normalized) {
        return level;
      }
    }
    return null;
  }
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

  bool get isFailure => level.priority >= AppLogLevel.error.priority;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 1,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'localOffsetMinutes': timestamp.timeZoneOffset.inMinutes,
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

  String toDisplayText({bool includeStackTrace = true}) {
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
    if (includeStackTrace && stackTrace != null) {
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

class AppLogQuery {
  const AppLogQuery({
    this.minimumLevel = AppLogLevel.trace,
    this.categories = const <String>{},
    this.operationId,
    this.search,
    this.from,
    this.to,
    this.limit = 200,
  });

  final AppLogLevel minimumLevel;
  final Set<String> categories;
  final String? operationId;
  final String? search;
  final DateTime? from;
  final DateTime? to;
  final int limit;
}

class AppLogStatistics {
  const AppLogStatistics({
    required this.totalCaptured,
    required this.entriesInMemory,
    required this.pendingDiskEntries,
    required this.droppedEntries,
    required this.sinkFailures,
    required this.byLevel,
    required this.byCategory,
  });

  final int totalCaptured;
  final int entriesInMemory;
  final int pendingDiskEntries;
  final int droppedEntries;
  final int sinkFailures;
  final Map<AppLogLevel, int> byLevel;
  final Map<String, int> byCategory;
}

class AppLogFileInfo {
  const AppLogFileInfo({
    required this.path,
    required this.bytes,
    required this.modifiedAt,
    required this.active,
  });

  final String path;
  final int bytes;
  final DateTime modifiedAt;
  final bool active;
}

class AppLogOperation {
  AppLogOperation._({
    required AppLogger logger,
    required this.category,
    required this.name,
    required this.operationId,
    required Map<String, Object?> data,
  })  : _logger = logger,
        _initialData = Map<String, Object?>.unmodifiable(data),
        _stopwatch = Stopwatch()..start() {
    _logger.info(
      category,
      '$name started',
      operationId: operationId,
      data: _initialData,
    );
  }

  final AppLogger _logger;
  final String category;
  final String name;
  final String operationId;
  final Map<String, Object?> _initialData;
  final Stopwatch _stopwatch;
  bool _ended = false;

  void step(
    String message, {
    AppLogLevel level = AppLogLevel.debug,
    String? code,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    if (_ended) {
      return;
    }
    _logger.log(
      level,
      category,
      message,
      operationId: operationId,
      code: code,
      data: <String, Object?>{
        ...data,
        'elapsedMs': _stopwatch.elapsedMilliseconds,
      },
    );
  }

  void complete({
    String? message,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    if (_ended) {
      return;
    }
    _ended = true;
    _stopwatch.stop();
    _logger.info(
      category,
      message ?? '$name completed',
      operationId: operationId,
      data: <String, Object?>{
        ..._initialData,
        ...data,
        'durationMs': _stopwatch.elapsedMilliseconds,
      },
    );
  }

  void fail(
    Object error,
    StackTrace stackTrace, {
    String? message,
    String? code,
    AppLogLevel level = AppLogLevel.error,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    if (_ended) {
      return;
    }
    _ended = true;
    _stopwatch.stop();
    _logger.log(
      level,
      category,
      message ?? '$name failed',
      operationId: operationId,
      code: code,
      data: <String, Object?>{
        ..._initialData,
        ...data,
        'durationMs': _stopwatch.elapsedMilliseconds,
      },
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class AppLogger {
  AppLogger({
    int memoryCapacity = 500,
    int maxPendingDiskEntries = 500,
    int maxFileBytes = 2 * 1024 * 1024,
    int retainedFileCount = 6,
    Duration retainedFileAge = const Duration(days: 14),
    AppLogLevel minimumLevel = AppLogLevel.trace,
    AppLogLevel? consoleMinimumLevel,
    bool consoleEnabled = true,
    bool fileEnabled = true,
    DateTime Function()? clock,
    Random? random,
  })  : assert(memoryCapacity > 0),
        assert(maxPendingDiskEntries > 0),
        assert(maxFileBytes > 0),
        assert(retainedFileCount >= 0),
        _memoryCapacity = memoryCapacity,
        _maxPendingDiskEntries = maxPendingDiskEntries,
        _maxFileBytes = maxFileBytes,
        _retainedFileCount = retainedFileCount,
        _retainedFileAge = retainedFileAge,
        _minimumLevel = minimumLevel,
        _consoleMinimumLevel = consoleMinimumLevel ??
            (kDebugMode ? AppLogLevel.debug : AppLogLevel.warning),
        _consoleEnabled = consoleEnabled,
        _fileEnabled = fileEnabled,
        _clock = clock ?? DateTime.now,
        _random = random ?? _safeRandom() {
    _sessionId = _createSessionId();
    for (final level in AppLogLevel.values) {
      _levelCounts[level] = 0;
    }
  }

  static final AppLogger instance = AppLogger();
  static const String activeFileName = 'app-current.jsonl';
  static const String exportFilePrefix = 'gardendless-diagnostics';
  static final Object _zoneContextKey = Object();

  final int _memoryCapacity;
  final int _maxPendingDiskEntries;
  final int _maxFileBytes;
  final int _retainedFileCount;
  final Duration _retainedFileAge;
  final DateTime Function() _clock;
  final Random _random;
  final ListQueue<AppLogEntry> _entries = ListQueue<AppLogEntry>();
  final ListQueue<AppLogEntry> _pendingDiskEntries =
      ListQueue<AppLogEntry>();
  final Map<AppLogLevel, int> _levelCounts = <AppLogLevel, int>{};
  final Map<String, int> _categoryCounts = <String, int>{};
  final StreamController<AppLogEntry> _entryController =
      StreamController<AppLogEntry>.broadcast(sync: true);

  late final String _sessionId;
  AppLogLevel _minimumLevel;
  AppLogLevel _consoleMinimumLevel;
  bool _consoleEnabled;
  bool _fileEnabled;
  Map<String, Object?> _baseContext = const <String, Object?>{};
  Directory? _directory;
  File? _activeFile;
  Future<void> _writeQueue = Future<void>.value();
  int _sequence = 0;
  int _operationSequence = 0;
  int _capturedCount = 0;
  int _droppedEntryCount = 0;
  int _sinkFailureCount = 0;
  bool _initialized = false;
  bool _disposed = false;

  String get sessionId => _sessionId;
  bool get isPersistent =>
      !_disposed && _fileEnabled && _initialized && _activeFile != null;
  String? get activeLogPath => _activeFile?.path;
  String? get logDirectoryPath => _directory?.path;
  AppLogLevel get minimumLevel => _minimumLevel;
  AppLogLevel get consoleMinimumLevel => _consoleMinimumLevel;
  bool get consoleEnabled => _consoleEnabled;
  bool get fileEnabled => _fileEnabled;
  int get droppedEntryCount => _droppedEntryCount;
  int get sinkFailureCount => _sinkFailureCount;
  Stream<AppLogEntry> get entries => _entryController.stream;

  AppLogEntry? get latestError {
    for (final entry in _entries.toList(growable: false).reversed) {
      if (entry.level.priority >= AppLogLevel.error.priority) {
        return entry;
      }
    }
    return null;
  }

  Set<String> get categories =>
      Set<String>.unmodifiable(_categoryCounts.keys.toSet());

  void configure({
    AppLogLevel? minimumLevel,
    AppLogLevel? consoleMinimumLevel,
    bool? consoleEnabled,
    bool? fileEnabled,
  }) {
    if (_disposed) {
      return;
    }
    final previousFileEnabled = _fileEnabled;
    _minimumLevel = minimumLevel ?? _minimumLevel;
    _consoleMinimumLevel = consoleMinimumLevel ?? _consoleMinimumLevel;
    _consoleEnabled = consoleEnabled ?? _consoleEnabled;
    _fileEnabled = fileEnabled ?? _fileEnabled;
    info(
      'logging.configuration',
      'Logging configuration updated',
      data: <String, Object?>{
        'minimumLevel': _minimumLevel.label,
        'consoleMinimumLevel': _consoleMinimumLevel.label,
        'consoleEnabled': _consoleEnabled,
        'fileEnabled': _fileEnabled,
        'previousFileEnabled': previousFileEnabled,
      },
    );
  }

  void setBaseContext(Map<String, Object?> context) {
    _baseContext = _sanitizeMap(context);
  }

  T runWithContext<T>(
    Map<String, Object?> context,
    T Function() action,
  ) {
    final current = Zone.current[_zoneContextKey];
    final inherited = current is Map<String, Object?>
        ? current
        : const <String, Object?>{};
    return runZoned<T>(
      action,
      zoneValues: <Object, Object?>{
        _zoneContextKey: <String, Object?>{
          ...inherited,
          ...context,
        },
      },
    );
  }

  Future<void> initialize({
    required Directory directory,
    Map<String, Object?> baseContext = const <String, Object?>{},
  }) async {
    if (_disposed) {
      return;
    }
    if (baseContext.isNotEmpty) {
      setBaseContext(<String, Object?>{..._baseContext, ...baseContext});
    }

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
      await _archivePreviousSessionFile();
      await _pruneRotatedFiles();
      _initialized = true;

      final pending = List<AppLogEntry>.of(_pendingDiskEntries);
      _pendingDiskEntries.clear();
      if (_fileEnabled) {
        for (final entry in pending) {
          _enqueueWrite(entry);
        }
      }

      info(
        'logging.lifecycle',
        'Persistent logging initialized',
        code: 'logging_initialized',
        data: <String, Object?>{
          'directory': directory.path,
          'activeFile': _activeFile!.path,
          'memoryCapacity': _memoryCapacity,
          'maxFileBytes': _maxFileBytes,
          'retainedFileCount': _retainedFileCount,
          'retainedFileDays': _retainedFileAge.inDays,
          'bufferedEntries': pending.length,
        },
      );
    } catch (error, stackTrace) {
      _initialized = false;
      _directory = null;
      _activeFile = null;
      _sinkFailureCount += 1;
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

  AppLogOperation beginOperation(
    String category,
    String name, {
    String? operationId,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    return AppLogOperation._(
      logger: this,
      category: category,
      name: name,
      operationId: operationId ?? nextOperationId(name),
      data: data,
    );
  }

  void traceLog(
    String category,
    String message, {
    String? operationId,
    String? code,
    Map<String, Object?> data = const <String, Object?>{},
  }) =>
      log(
        AppLogLevel.trace,
        category,
        message,
        operationId: operationId,
        code: code,
        data: data,
      );

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
    if (_disposed || level.priority < _minimumLevel.priority) {
      return;
    }

    _sequence += 1;
    _capturedCount += 1;
    final normalizedCategory =
        category.trim().isEmpty ? 'app' : category.trim();
    final zoneContext = Zone.current[_zoneContextKey];
    final inheritedContext = zoneContext is Map<String, Object?>
        ? zoneContext
        : const <String, Object?>{};
    final entry = AppLogEntry(
      timestamp: _clock(),
      level: level,
      category: normalizedCategory,
      message: _truncate(message.trim().isEmpty ? '-' : message.trim(), 4000),
      sessionId: _sessionId,
      sequence: _sequence,
      operationId: _nullableTrimmed(operationId),
      code: _nullableTrimmed(code),
      data: _sanitizeMap(<String, Object?>{
        ..._baseContext,
        ...inheritedContext,
        ...data,
      }),
      error: error == null ? null : _sanitizeString(error.toString(), 4000),
      stackTrace: stackTrace == null
          ? null
          : _truncateStackTrace(stackTrace.toString()),
    );

    _levelCounts[level] = (_levelCounts[level] ?? 0) + 1;
    _categoryCounts[normalizedCategory] =
        (_categoryCounts[normalizedCategory] ?? 0) + 1;
    _entries.addLast(entry);
    while (_entries.length > _memoryCapacity) {
      _entries.removeFirst();
      _droppedEntryCount += 1;
    }

    if (!_entryController.isClosed) {
      _entryController.add(entry);
    }

    if (_fileEnabled && _initialized) {
      _enqueueWrite(entry);
    } else if (_fileEnabled) {
      _pendingDiskEntries.addLast(entry);
      while (_pendingDiskEntries.length > _maxPendingDiskEntries) {
        _pendingDiskEntries.removeFirst();
        _droppedEntryCount += 1;
      }
    }

    if (_consoleEnabled &&
        level.priority >= _consoleMinimumLevel.priority) {
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
    final scope = beginOperation(
      category,
      operation,
      operationId: operationId,
      data: data,
    );
    try {
      final result = await action(scope.operationId);
      scope.complete();
      return result;
    } catch (error, stackTrace) {
      scope.fail(error, stackTrace, code: failureCode);
      rethrow;
    }
  }

  List<AppLogEntry> recentEntries({
    int limit = 120,
    AppLogLevel minLevel = AppLogLevel.trace,
  }) {
    return query(
      AppLogQuery(minimumLevel: minLevel, limit: limit),
    );
  }

  List<AppLogEntry> query(AppLogQuery query) {
    if (query.limit <= 0) {
      return const <AppLogEntry>[];
    }
    final normalizedSearch = query.search?.trim().toLowerCase();
    final normalizedOperation = query.operationId?.trim();
    final normalizedCategories = query.categories
        .map((category) => category.trim())
        .where((category) => category.isNotEmpty)
        .toSet();
    final matches = <AppLogEntry>[];
    for (final entry in _entries.toList(growable: false).reversed) {
      if (entry.level.priority < query.minimumLevel.priority) {
        continue;
      }
      if (normalizedCategories.isNotEmpty &&
          !normalizedCategories.contains(entry.category)) {
        continue;
      }
      if (normalizedOperation != null &&
          normalizedOperation.isNotEmpty &&
          entry.operationId != normalizedOperation) {
        continue;
      }
      if (query.from != null && entry.timestamp.isBefore(query.from!)) {
        continue;
      }
      if (query.to != null && entry.timestamp.isAfter(query.to!)) {
        continue;
      }
      if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
        final haystack = <String>[
          entry.category,
          entry.message,
          entry.code ?? '',
          entry.error ?? '',
          entry.operationId ?? '',
          jsonEncode(entry.data),
        ].join(' ').toLowerCase();
        if (!haystack.contains(normalizedSearch)) {
          continue;
        }
      }
      matches.add(entry);
      if (matches.length >= query.limit) {
        break;
      }
    }
    return List<AppLogEntry>.unmodifiable(matches.reversed);
  }

  AppLogStatistics get statistics => AppLogStatistics(
        totalCaptured: _capturedCount,
        entriesInMemory: _entries.length,
        pendingDiskEntries: _pendingDiskEntries.length,
        droppedEntries: _droppedEntryCount,
        sinkFailures: _sinkFailureCount,
        byLevel: Map<AppLogLevel, int>.unmodifiable(_levelCounts),
        byCategory: Map<String, int>.unmodifiable(_categoryCounts),
      );

  String diagnosticsText({
    int limit = 120,
    AppLogLevel minLevel = AppLogLevel.trace,
    String? search,
    Set<String> categories = const <String>{},
    bool includeStackTrace = true,
  }) {
    final entries = query(
      AppLogQuery(
        minimumLevel: minLevel,
        categories: categories,
        search: search,
        limit: limit,
      ),
    );
    if (entries.isEmpty) {
      return '[INFO] [logging] No log entries matched the query';
    }
    return entries
        .map(
          (entry) => entry.toDisplayText(
            includeStackTrace: includeStackTrace,
          ),
        )
        .join('\n');
  }

  Future<List<AppLogFileInfo>> listLogFiles() async {
    await flush();
    final directory = _directory;
    if (directory == null || !await directory.exists()) {
      return const <AppLogFileInfo>[];
    }
    final files = await directory
        .list(followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => p.extension(file.path).toLowerCase() == '.jsonl')
        .toList();
    final result = <AppLogFileInfo>[];
    for (final file in files) {
      result.add(
        AppLogFileInfo(
          path: file.path,
          bytes: await file.length(),
          modifiedAt: await file.lastModified(),
          active: p.basename(file.path) == activeFileName,
        ),
      );
    }
    result.sort((left, right) => right.modifiedAt.compareTo(left.modifiedAt));
    return List<AppLogFileInfo>.unmodifiable(result);
  }

  Future<void> clear({bool clearMemory = true}) async {
    if (_disposed) {
      return;
    }
    await flush();
    final directory = _directory;
    if (directory != null && await directory.exists()) {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File &&
            p.extension(entity.path).toLowerCase() == '.jsonl') {
          try {
            await entity.delete();
          } catch (error, stackTrace) {
            _recordSinkFailure('Unable to delete log file', error, stackTrace);
          }
        }
      }
    }
    _pendingDiskEntries.clear();
    if (clearMemory) {
      _entries.clear();
    }
    info(
      'logging.lifecycle',
      'Logs cleared',
      code: 'logs_cleared',
      data: <String, Object?>{'memoryCleared': clearMemory},
    );
    await flush();
  }

  Future<File> createSupportBundle({
    Directory? outputDirectory,
    String? diagnosticsText,
    int maxLogBytes = 8 * 1024 * 1024,
  }) async {
    if (maxLogBytes <= 0) {
      throw ArgumentError.value(maxLogBytes, 'maxLogBytes', 'Must be positive');
    }
    await flush();
    final targetDirectory =
        outputDirectory ?? _directory ?? Directory.systemTemp;
    await targetDirectory.create(recursive: true);
    final file = File(
      p.join(
        targetDirectory.path,
        '$exportFilePrefix-${_fileTimestamp(_clock())}.txt',
      ),
    );
    final stats = statistics;
    final buffer = StringBuffer()
      ..writeln('GardendlessLoader diagnostics bundle')
      ..writeln('Generated: ${_clock().toUtc().toIso8601String()}')
      ..writeln('Logging session: $_sessionId')
      ..writeln('Persistent logging: $isPersistent')
      ..writeln('Active log path: ${activeLogPath ?? '-'}')
      ..writeln('Captured entries: ${stats.totalCaptured}')
      ..writeln('Entries in memory: ${stats.entriesInMemory}')
      ..writeln('Dropped entries: ${stats.droppedEntries}')
      ..writeln('Sink failures: ${stats.sinkFailures}')
      ..writeln();
    if (diagnosticsText != null && diagnosticsText.trim().isNotEmpty) {
      buffer
        ..writeln('===== APPLICATION DIAGNOSTICS =====')
        ..writeln(diagnosticsText.trim())
        ..writeln();
    }
    buffer
      ..writeln('===== CURRENT SESSION EVENTS =====')
      ..writeln(diagnosticsTextForExport())
      ..writeln();

    var includedBytes = 0;
    final files = await listLogFiles();
    for (final logFile in files.reversed) {
      if (includedBytes >= maxLogBytes) {
        break;
      }
      final source = File(logFile.path);
      final remaining = maxLogBytes - includedBytes;
      try {
        final bytes = await source.readAsBytes();
        final selected = bytes.length <= remaining
            ? bytes
            : bytes.sublist(bytes.length - remaining);
        includedBytes += selected.length;
        buffer
          ..writeln('===== LOG FILE ${p.basename(source.path)} =====')
          ..writeln(utf8.decode(selected, allowMalformed: true))
          ..writeln();
      } catch (error, stackTrace) {
        _recordSinkFailure('Unable to read log file for export', error, stackTrace);
        buffer.writeln(
          'Unable to include ${p.basename(source.path)}: ${_sanitizeString(error.toString(), 1000)}',
        );
      }
    }
    if (includedBytes >= maxLogBytes) {
      buffer.writeln('Log archive truncated at $maxLogBytes bytes.');
    }
    await file.writeAsString(buffer.toString(), flush: true);
    info(
      'logging.export',
      'Diagnostics bundle created',
      code: 'diagnostics_exported',
      data: <String, Object?>{
        'path': file.path,
        'includedLogBytes': includedBytes,
      },
    );
    await flush();
    return file;
  }

  String diagnosticsTextForExport() {
    return diagnosticsText(
      limit: _memoryCapacity,
      minLevel: AppLogLevel.trace,
      includeStackTrace: true,
    );
  }

  Future<void> flush() => _writeQueue;

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    info('logging.lifecycle', 'Logging session closing');
    await flush();
    _disposed = true;
    await _entryController.close();
  }

  void _enqueueWrite(AppLogEntry entry) {
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _appendToDisk(entry);
      } catch (error, stackTrace) {
        _recordSinkFailure('AppLogger write failed', error, stackTrace);
      }
    });
  }

  Future<void> _appendToDisk(AppLogEntry entry) async {
    final file = _activeFile;
    if (!_initialized || !_fileEnabled || file == null) {
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

  Future<void> _archivePreviousSessionFile() async {
    final file = _activeFile;
    final directory = _directory;
    if (file == null || directory == null || !await file.exists()) {
      return;
    }
    if (await file.length() == 0) {
      await file.delete();
      return;
    }
    final modified = await file.lastModified();
    await _renameActiveFile(
      baseName: 'app-${_fileTimestamp(modified)}-previous-session',
    );
  }

  Future<void> _rotateIfNeeded(int incomingBytes) async {
    final file = _activeFile;
    if (file == null || !await file.exists()) {
      return;
    }
    if (await file.length() + incomingBytes <= _maxFileBytes) {
      return;
    }
    await _renameActiveFile(baseName: 'app-${_fileTimestamp(_clock())}');
    await _pruneRotatedFiles();
  }

  Future<void> _renameActiveFile({required String baseName}) async {
    final file = _activeFile;
    final directory = _directory;
    if (file == null || directory == null || !await file.exists()) {
      return;
    }
    var candidate = File(p.join(directory.path, '$baseName.jsonl'));
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = File(p.join(directory.path, '$baseName-$suffix.jsonl'));
      suffix += 1;
    }
    await file.rename(candidate.path);
  }

  Future<void> _pruneRotatedFiles() async {
    final directory = _directory;
    if (directory == null || !await directory.exists()) {
      return;
    }
    final now = _clock();
    final files = await directory
        .list(followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) {
      final name = p.basename(file.path);
      return name.startsWith('app-') &&
          name != activeFileName &&
          p.extension(name).toLowerCase() == '.jsonl';
    }).toList();

    final modified = <File, DateTime>{};
    for (final file in files) {
      final timestamp = await file.lastModified();
      modified[file] = timestamp;
      if (_retainedFileAge > Duration.zero &&
          now.difference(timestamp) > _retainedFileAge) {
        try {
          await file.delete();
        } catch (error, stackTrace) {
          _recordSinkFailure('Unable to prune expired log file', error, stackTrace);
        }
      }
    }

    final remaining = <File>[];
    for (final file in files) {
      if (await file.exists()) {
        remaining.add(file);
      }
    }
    remaining.sort(
      (left, right) => modified[right]!.compareTo(modified[left]!),
    );
    for (final file in remaining.skip(_retainedFileCount)) {
      try {
        await file.delete();
      } catch (error, stackTrace) {
        _recordSinkFailure('Unable to prune excess log file', error, stackTrace);
      }
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
    if (depth >= 5) {
      return '<max-depth>';
    }
    if (value is String) {
      return _sanitizeString(value, 2000);
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Duration) {
      return value.inMilliseconds;
    }
    if (value is Uri) {
      return value
          .replace(userInfo: '', query: '', fragment: '')
          .toString();
    }
    if (value is Map) {
      final result = <String, Object?>{};
      var count = 0;
      for (final entry in value.entries) {
        if (count >= 40) {
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
          .take(40)
          .map((item) => _sanitizeValue(item, depth: depth + 1))
          .toList(growable: false);
    }
    return _sanitizeString(value.toString(), 2000);
  }

  bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized == 'authorization' ||
        normalized == 'cookie' ||
        normalized == 'setcookie' ||
        normalized.contains('password') ||
        normalized.contains('passwd') ||
        normalized.contains('credential') ||
        normalized.contains('secret') ||
        normalized.contains('sessionkey') ||
        normalized.endsWith('token') ||
        normalized == 'apikey' ||
        normalized.endsWith('privatekey');
  }

  String _sanitizeString(String value, int maxLength) {
    var result = value;
    final homePaths = <String?>[
      Platform.environment['HOME'],
      Platform.environment['USERPROFILE'],
    ];
    for (final home in homePaths) {
      if (home != null && home.trim().isNotEmpty) {
        result = result.replaceAll(home, '~');
      }
    }
    final credentialPattern = RegExp(
      r'(authorization|bearer|password|passwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token)\s*[:=]\s*([^\s,;]+)',
      caseSensitive: false,
    );
    result = result.replaceAllMapped(
      credentialPattern,
      (match) => '${match.group(1)}=<redacted>',
    );
    return _truncate(result, maxLength);
  }

  String _truncateStackTrace(String value) {
    final lines = value.split('\n');
    final selected = lines.length > 60 ? lines.take(60).toList() : lines;
    return _sanitizeString(selected.join('\n'), 16000);
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

  void _recordSinkFailure(
    String message,
    Object error,
    StackTrace stackTrace,
  ) {
    _sinkFailureCount += 1;
    debugPrint('$message: $error\n$stackTrace');
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

  static Random _safeRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }
}
