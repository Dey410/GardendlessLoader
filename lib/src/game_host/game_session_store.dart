import 'dart:convert';
import 'dart:io';

import 'game_host.dart';

enum GameExitReason {
  normal,
  userReturned,
  rendererGone,
  launchFailed,
  systemTerminated;

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
    );
  }

  final String sessionId;
  final GameExitReason reason;
  final DateTime finishedAt;
  final String? message;
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

  Future<GameExitResult?> consumeExitResult() async {
    final prepared = await readPrepared();
    if (prepared == null || !await exitResultFile.exists()) {
      return null;
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
