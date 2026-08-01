import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/resource_self_check.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('gl_resource_check_');
    for (final path in ['src', 'cocos-js']) {
      await Directory(p.join(root.path, path)).create(recursive: true);
    }
    await File(p.join(root.path, 'index.html')).writeAsString('<html></html>');
    await File(p.join(root.path, 'src', 'settings.json')).writeAsString('{}');
    await File(p.join(root.path, 'src', 'import-map.json')).writeAsString('{}');
    await File(p.join(root.path, 'cocos-js', 'cc.js')).writeAsString('');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('validates required entry resources without opening a socket', () async {
    await FileResourceSelfCheck().validate(root);
  });

  test('rejects a missing required resource with its relative path', () async {
    await File(p.join(root.path, 'src', 'import-map.json')).delete();

    await expectLater(
      FileResourceSelfCheck().validate(root),
      throwsA(
        isA<ResourceSelfCheckFailure>().having(
          (error) => error.path,
          'path',
          'src/import-map.json',
        ),
      ),
    );
  });

  test('rejects a symbolic link that escapes the resource root', () async {
    final outside = await Directory.systemTemp.createTemp('gl_outside_');
    addTearDown(() async {
      if (await outside.exists()) {
        await outside.delete(recursive: true);
      }
    });
    final outsideFile = File(p.join(outside.path, 'cc.js'));
    await outsideFile.writeAsString('outside');
    await File(p.join(root.path, 'cocos-js', 'cc.js')).delete();
    await Link(p.join(root.path, 'cocos-js', 'cc.js')).create(outsideFile.path);

    await expectLater(
      FileResourceSelfCheck().validate(root),
      throwsA(isA<ResourceSelfCheckFailure>()),
    );
  });

  test('rejects a symbolic link even when it resolves inside the root',
      () async {
    final importMap = File(p.join(root.path, 'src', 'import-map.json'));
    await importMap.delete();
    await Link(importMap.path).create(
      p.join(root.path, 'src', 'settings.json'),
    );

    await expectLater(
      FileResourceSelfCheck().validate(root),
      throwsA(
        isA<ResourceSelfCheckFailure>().having(
          (error) => error.message,
          'message',
          contains('符号链接'),
        ),
      ),
    );
  });
}
