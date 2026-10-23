import 'dart:convert';
import 'dart:io';

import '../game_host/game_session_store.dart';

/// A resource import that became the active game, one ring of the version
/// rings.
class ImportRecord {
  const ImportRecord({
    required this.importedAt,
    required this.totalBytes,
    this.gameVersion,
    this.gpNextVersion,
  });

  factory ImportRecord.fromJson(Map<String, dynamic> json) {
    final importedAt = DateTime.tryParse(json['importedAt'] as String? ?? '');
    if (importedAt == null) {
      throw const FormatException('import record time is invalid');
    }
    return ImportRecord(
      importedAt: importedAt,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      gameVersion: json['gameVersion'] as String?,
      gpNextVersion: json['gpNextVersion'] as String?,
    );
  }

  final DateTime importedAt;
  final int totalBytes;
  final String? gameVersion;
  final String? gpNextVersion;

  Map<String, Object?> toJson() => <String, Object?>{
        'importedAt': importedAt.toUtc().toIso8601String(),
        'totalBytes': totalBytes,
        'gameVersion': gameVersion,
        'gpNextVersion': gpNextVersion,
      };
}

/// Play time and import history kept on this device only.
class GardenJournal {
  const GardenJournal({
    this.totalPlayMs = 0,
    this.sessionCount = 0,
    this.longestPlayMs = 0,
    this.lastPlayedAt,
    this.lastPlayMs = 0,
    this.lastSaveExportAt,
    this.imports = const <ImportRecord>[],
  });

  factory GardenJournal.fromJson(Map<String, dynamic> json) {
    final imports = json['imports'];
    return GardenJournal(
      totalPlayMs: (json['totalPlayMs'] as num?)?.toInt() ?? 0,
      sessionCount: (json['sessionCount'] as num?)?.toInt() ?? 0,
      longestPlayMs: (json['longestPlayMs'] as num?)?.toInt() ?? 0,
      lastPlayedAt: DateTime.tryParse(json['lastPlayedAt'] as String? ?? ''),
      lastPlayMs: (json['lastPlayMs'] as num?)?.toInt() ?? 0,
      lastSaveExportAt:
          DateTime.tryParse(json['lastSaveExportAt'] as String? ?? ''),
      imports: imports is List
          ? imports
              .whereType<Map<String, dynamic>>()
              .map(ImportRecord.fromJson)
              .toList(growable: false)
          : const <ImportRecord>[],
    );
  }

  static const maxImports = 30;

  /// The game names a save export `<player>(v<game version>).json`; its
  /// other exports, such as key bindings, have no version in the name.
  static final savePattern = RegExp(r'\(v[^()]+\)\.json$');

  final int totalPlayMs;
  final int sessionCount;
  final int longestPlayMs;
  final DateTime? lastPlayedAt;
  final int lastPlayMs;

  /// When the player last exported a save from the game in the loader.
  final DateTime? lastSaveExportAt;

  /// Oldest first, at most [maxImports].
  final List<ImportRecord> imports;

  GardenJournal recordPlay({
    required DateTime finishedAt,
    required int playedMs,
  }) {
    return GardenJournal(
      totalPlayMs: totalPlayMs + playedMs,
      sessionCount: sessionCount + 1,
      longestPlayMs: playedMs > longestPlayMs ? playedMs : longestPlayMs,
      lastPlayedAt: finishedAt,
      lastPlayMs: playedMs,
      lastSaveExportAt: lastSaveExportAt,
      imports: imports,
    );
  }

  /// Keeps the latest save among [exports]; other exported files are not
  /// saves.
  GardenJournal recordExports(List<GameExport> exports) {
    final saves = exports.where((export) => savePattern.hasMatch(export.name));
    if (saves.isEmpty) return this;
    return GardenJournal(
      totalPlayMs: totalPlayMs,
      sessionCount: sessionCount,
      longestPlayMs: longestPlayMs,
      lastPlayedAt: lastPlayedAt,
      lastPlayMs: lastPlayMs,
      lastSaveExportAt: saves.last.exportedAt,
      imports: imports,
    );
  }

  GardenJournal recordImport(ImportRecord record) {
    final all = [...imports, record];
    return GardenJournal(
      totalPlayMs: totalPlayMs,
      sessionCount: sessionCount,
      longestPlayMs: longestPlayMs,
      lastPlayedAt: lastPlayedAt,
      lastPlayMs: lastPlayMs,
      lastSaveExportAt: lastSaveExportAt,
      imports:
          all.length > maxImports ? all.sublist(all.length - maxImports) : all,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 1,
        'totalPlayMs': totalPlayMs,
        'sessionCount': sessionCount,
        'longestPlayMs': longestPlayMs,
        'lastPlayedAt': lastPlayedAt?.toUtc().toIso8601String(),
        'lastPlayMs': lastPlayMs,
        'lastSaveExportAt': lastSaveExportAt?.toUtc().toIso8601String(),
        'imports': [for (final record in imports) record.toJson()],
      };
}

class GardenJournalStore {
  GardenJournalStore(this._file);

  final File _file;

  File get _temporaryFile => File('${_file.path}.tmp');

  Future<GardenJournal> read() async {
    if (!await _file.exists()) {
      return const GardenJournal();
    }
    try {
      final json = jsonDecode(await _file.readAsString());
      if (json is Map<String, dynamic>) {
        return GardenJournal.fromJson(json);
      }
    } catch (_) {
      // An unreadable journal starts over; it holds no game data.
    }
    return const GardenJournal();
  }

  Future<void> write(GardenJournal journal) async {
    await _file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _temporaryFile.writeAsString(
      '${encoder.convert(journal.toJson())}\n',
      flush: true,
    );
    await _temporaryFile.rename(_file.path);
  }
}
