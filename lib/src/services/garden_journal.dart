import 'dart:convert';
import 'dart:io';

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
      imports: imports is List
          ? imports
              .whereType<Map<String, dynamic>>()
              .map(ImportRecord.fromJson)
              .toList(growable: false)
          : const <ImportRecord>[],
    );
  }

  static const maxImports = 30;

  final int totalPlayMs;
  final int sessionCount;
  final int longestPlayMs;
  final DateTime? lastPlayedAt;
  final int lastPlayMs;

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
