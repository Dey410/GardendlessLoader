import 'dart:io';

import 'package:path/path.dart' as p;

/// Rejects links and paths outside a resource slot before reading or writing.
Future<void> requireSafeResourcePath(
  Directory root,
  String path,
  FileSystemEntityType expected, {
  bool allowMissing = false,
}) async {
  final absoluteRoot = p.normalize(root.absolute.path);
  final absolutePath = p.normalize(p.absolute(path));
  if (absoluteRoot != absolutePath && !p.isWithin(absoluteRoot, absolutePath)) {
    throw const FileSystemException('文件越出资源根目录');
  }
  var current = absoluteRoot;
  final components = p.equals(absoluteRoot, absolutePath)
      ? const <String>[]
      : p.split(p.relative(absolutePath, from: absoluteRoot));
  for (final component in <String>['', ...components]) {
    if (component.isNotEmpty) current = p.join(current, component);
    if (await FileSystemEntity.type(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('资源路径不能包含符号链接');
    }
  }
  final type = await FileSystemEntity.type(absolutePath, followLinks: false);
  if (type == FileSystemEntityType.notFound && allowMissing) return;
  if (type != expected) {
    throw const FileSystemException('资源类型无效');
  }
  final canonicalRoot = p.normalize(await root.resolveSymbolicLinks());
  final resolved = p.normalize(await (expected == FileSystemEntityType.file
      ? File(absolutePath).resolveSymbolicLinks()
      : Directory(absolutePath).resolveSymbolicLinks()));
  if (resolved != canonicalRoot && !p.isWithin(canonicalRoot, resolved)) {
    throw const FileSystemException('文件越出资源根目录');
  }
  if (expected == FileSystemEntityType.file) {
    final handle = await File(resolved).open(mode: FileMode.read);
    await handle.close();
  }
}
