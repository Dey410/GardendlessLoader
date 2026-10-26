import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// GitHub rejects an issue body over 65,536 characters; the rest is left for
/// the reporter's own words.
const logSummaryLimit = 60000;

/// Every event the native store kept in [directory], oldest run first, as it
/// wrote them.
Future<List<String>> readLogHistory(String directory) async {
  // Files are named app-<UTC run start>-<id>-<segment>.jsonl, so name order is
  // time order.
  final files = [
    for (final entity in Directory(directory).listSync())
      if (entity is File && entity.path.endsWith('.jsonl')) entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      for (final line in await file.readAsLines(
        encoding: const Utf8Codec(allowMalformed: true),
      ))
        if (line.isNotEmpty) line,
  ];
}

/// The warnings and errors among [events] that fit in [budget] characters:
/// the newest errors first, then the newest warnings, listed in log order.
String summarizeLogIssues(List<String> events, int budget) {
  final issues = <(bool error, String line)>[];
  for (final line in events) {
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      // A run the system killed mid-write ends in a partial line.
      continue;
    }
    final level = event is Map ? event['level'] : null;
    if (level == 'ERROR' || level == 'FATAL') issues.add((true, line));
    if (level == 'WARN') issues.add((false, line));
  }
  final kept = List.filled(issues.length, false);
  var used = 0;
  for (final errors in [true, false]) {
    for (var i = issues.length - 1; i >= 0; i--) {
      if (issues[i].$1 != errors) continue;
      final cost = issues[i].$2.length + 1;
      if (used + cost > budget) break;
      used += cost;
      kept[i] = true;
    }
  }
  final shown = [
    for (var i = 0; i < issues.length; i++)
      if (kept[i]) issues[i].$2,
  ];
  return [
    'Warnings and errors: ${shown.length} of ${issues.length} '
        '(the exported log file has every event):',
    ...shown,
  ].join('\n');
}

/// Writes [report] to [name] in the temporary directory, replacing earlier
/// exports.
Future<File> writeLogExport(String name, String report) async {
  final exports = Directory(
    p.join((await getTemporaryDirectory()).path, 'log-exports'),
  );
  if (await exports.exists()) await exports.delete(recursive: true);
  await exports.create(recursive: true);
  return File(p.join(exports.path, name)).writeAsString(report);
}
