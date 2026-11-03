import 'dart:convert';

import 'package:path/path.dart' as p;

const maxResourceIndexBytes = 32 * 1024 * 1024;

typedef ResourcePackageEntry = ({String path, int sizeBytes, String sha256});

/// The same strict index format applies before delta copying and validation.
List<ResourcePackageEntry> decodeResourcePackageIndex(List<int> bytes) {
  if (bytes.length > maxResourceIndexBytes) {
    throw const FormatException('资源包元数据过大');
  }
  final index = jsonDecode(utf8.decode(bytes));
  if (index is! Map<String, dynamic> ||
      index.length != 2 ||
      index['schemaVersion'] != 1 ||
      index['files'] is! List) {
    throw const FormatException('资源包索引格式无效');
  }
  final entries = <ResourcePackageEntry>[];
  final hexDigest = RegExp(r'^[a-f0-9]{64}$');
  String? previous;
  for (final entry in index['files'] as List) {
    if (entry is! Map<String, dynamic> ||
        entry.length != 3 ||
        entry['path'] is! String ||
        entry['sizeBytes'] is! int ||
        (entry['sizeBytes'] as int) < 0 ||
        entry['sha256'] is! String ||
        !hexDigest.hasMatch(entry['sha256'] as String)) {
      throw const FormatException('资源包索引条目无效');
    }
    final path = entry['path'] as String;
    final uri = Uri.tryParse(path);
    if (path.isEmpty ||
        path.contains('\\') ||
        path.contains('\u0000') ||
        p.posix.isAbsolute(path) ||
        p.posix.normalize(path) != path ||
        path
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..') ||
        uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        (previous != null && previous.compareTo(path) >= 0)) {
      throw const FormatException('资源包索引路径不安全、重复或未排序');
    }
    previous = path;
    entries.add((
      path: path,
      sizeBytes: entry['sizeBytes'] as int,
      sha256: entry['sha256'] as String,
    ));
  }
  return entries;
}
