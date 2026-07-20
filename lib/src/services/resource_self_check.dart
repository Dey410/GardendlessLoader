import 'dart:io';

import 'package:path/path.dart' as p;

abstract interface class ResourceSelfCheck {
  Future<void> validate(Directory root);
}

class FileResourceSelfCheck implements ResourceSelfCheck {
  static const requiredPaths = <String>[
    'index.html',
    'src/settings.json',
    'src/import-map.json',
    'cocos-js/cc.js',
  ];

  @override
  Future<void> validate(Directory root) async {
    if (!await root.exists()) {
      throw const ResourceSelfCheckFailure('.', '资源根目录不存在');
    }
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const ResourceSelfCheckFailure('.', '资源根目录不能是符号链接');
    }
    final canonicalRoot = p.normalize(await root.resolveSymbolicLinks());
    for (final relativePath in requiredPaths) {
      final file = File(p.join(canonicalRoot, relativePath));
      if (!await file.exists()) {
        throw ResourceSelfCheckFailure(relativePath, '缺少自检文件');
      }
      final resolved = p.normalize(await file.resolveSymbolicLinks());
      if (!p.isWithin(canonicalRoot, resolved)) {
        throw ResourceSelfCheckFailure(relativePath, '文件越出资源根目录');
      }
      var current = canonicalRoot;
      for (final component in p.split(relativePath)) {
        current = p.join(current, component);
        if (await FileSystemEntity.type(current, followLinks: false) ==
            FileSystemEntityType.link) {
          throw ResourceSelfCheckFailure(relativePath, '资源路径不能包含符号链接');
        }
      }
      if (await FileSystemEntity.type(resolved, followLinks: true) !=
          FileSystemEntityType.file) {
        throw ResourceSelfCheckFailure(relativePath, '资源不是普通文件');
      }
      final handle = await File(resolved).open(mode: FileMode.read);
      await handle.close();
    }
  }
}

class ResourceSelfCheckFailure implements Exception {
  const ResourceSelfCheckFailure(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => '资源自检失败 $path: $message';
}
