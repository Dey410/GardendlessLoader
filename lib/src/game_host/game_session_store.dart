import 'dart:convert';
import 'dart:io';

import 'game_host.dart';

enum GameExitReason {
  normal,
  userReturned,
  rendererGone,
  launchFailed,

  /// The host left this provisional result when the game went to the
  /// background, and the system ended the app before it came back.
  systemTerminated,

  /// The app ended while the game was in the foreground, leaving no exit
  /// result; the launcher infers it from the prepared session.
  interrupted;

  static GameExitReason fromWireName(Object? value) {
    return GameExitReason.values.firstWhere(
      (reason) => reason.name == value,
      orElse: () => throw FormatException('Unknown game exit reason: $value'),
    );
  }
}

class GameExitResult {
  const GameExitResult({
    required this.sessionId,
    required this.reason,
    required this.finishedAt,
    this.message,
    this.code,
    this.playedMs = 0,
    this.exports = const <GameExport>[],
  });

  factory GameExitResult.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported game exit result schema');
    }
    final sessionId = json['sessionId'];
    final finishedAt = DateTime.tryParse(json['finishedAt'] as String? ?? '');
    if (sessionId is! String || sessionId.isEmpty || finishedAt == null) {
      throw const FormatException('Invalid game exit result');
    }
    return GameExitResult(
      sessionId: sessionId,
      reason: GameExitReason.fromWireName(json['reason']),
      finishedAt: finishedAt.toUtc(),
      message: json['message'] as String?,
      code: json['code'] as String?,
      playedMs: (json['playedMs'] as num?)?.toInt() ?? 0,
      exports: (json['exports'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(GameExport.fromJson)
              .toList(growable: false) ??
          const <GameExport>[],
    );
  }

  final String sessionId;
  final GameExitReason reason;
  final DateTime finishedAt;
  final String? message;

  /// Error code naming a known launch failure cause; absent for other exits.
  final String? code;

  /// Time the game spent in the foreground; time in the background is not
  /// play time.
  final int playedMs;

  /// Files the player exported from the game during the session, oldest
  /// first.
  final List<GameExport> exports;
}

/// What the launcher shows about the game the player just left.
class GameSessionReport {
  const GameSessionReport({
    required this.reason,
    required this.errorCount,
    required this.memoryWarnings,
  });

  /// Counts the session's errors and memory warnings in [events], the
  /// latest log events.
  factory GameSessionReport.of(
    GameExitResult result,
    Iterable<Map<String, Object?>> events,
  ) {
    var errors = 0;
    var memoryWarnings = 0;
    for (final event in events) {
      if (event['gameSessionId'] != result.sessionId) continue;
      final level = event['level']?.toString().toUpperCase();
      if (level == 'ERROR' || level == 'FATAL') errors++;
      if (event['event'] == 'memory_pressure') memoryWarnings++;
    }
    return GameSessionReport(
      reason: result.reason,
      errorCount: errors,
      memoryWarnings: memoryWarnings,
    );
  }

  final GameExitReason reason;
  final int errorCount;
  final int memoryWarnings;

  /// The renderer or the whole app ended under the player.
  bool get crashed =>
      reason == GameExitReason.rendererGone ||
      reason == GameExitReason.interrupted;
}

/// A file the game exported through the host's save picker.
class GameExport {
  const GameExport({required this.name, required this.exportedAt});

  factory GameExport.fromJson(Map<String, dynamic> json) {
    final exportedAt = DateTime.tryParse(json['at'] as String? ?? '');
    final name = json['name'];
    if (name is! String || exportedAt == null) {
      throw const FormatException('Invalid game export record');
    }
    return GameExport(name: name, exportedAt: exportedAt.toUtc());
  }

  final String name;
  final DateTime exportedAt;
}

class GameSessionStore {
  GameSessionStore(this.root);

  final Directory root;

  File get preparedSessionFile => File(
        '${root.path}${Platform.pathSeparator}game_session.json',
      );
  File get exitResultFile => File(
        '${root.path}${Platform.pathSeparator}game_exit_result.json',
      );
  File get _temporarySessionFile => File('${preparedSessionFile.path}.tmp');

  Future<void> prepare(GameSession session) async {
    await root.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _temporarySessionFile.writeAsString(
      '${encoder.convert(session.toJson())}\n',
      flush: true,
    );
    await _temporarySessionFile.rename(preparedSessionFile.path);
  }

  Future<GameSession?> readPrepared() async {
    if (!await preparedSessionFile.exists()) {
      return null;
    }
    try {
      final value = jsonDecode(await preparedSessionFile.readAsString());
      if (value is! Map<String, dynamic>) {
        return null;
      }
      return GameSession.fromJson(value.cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  /// Removes the prepared session of a launch the host never accepted.
  Future<void> discardPrepared() async {
    if (await preparedSessionFile.exists()) {
      await preparedSessionFile.delete();
    }
  }

  Future<GameExitResult?> consumeExitResult() async {
    final prepared = await readPrepared();
    if (prepared == null) {
      return null;
    }
    // Every host writes its exit result before it returns, and a provisional
    // one while the game is in the background, so a missing result means
    // the app ended during play.
    if (!await exitResultFile.exists()) {
      await preparedSessionFile.delete();
      return GameExitResult(
        sessionId: prepared.sessionId,
        reason: GameExitReason.interrupted,
        finishedAt: DateTime.now().toUtc(),
      );
    }
    try {
      final value = jsonDecode(await exitResultFile.readAsString());
      if (value is! Map<String, dynamic>) {
        return null;
      }
      final result = GameExitResult.fromJson(value.cast<String, Object?>());
      if (result.sessionId != prepared.sessionId) {
        return null;
      }
      await exitResultFile.delete();
      if (await preparedSessionFile.exists()) {
        await preparedSessionFile.delete();
      }
      return result;
    } catch (_) {
      return null;
    }
  }
}
