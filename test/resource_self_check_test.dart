import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/resource_validator.dart';
import 'package:path/path.dart' as p;

void main() {
  test('readiness rejects a linked Cocos file outside the resource root',
      () async {
    final root = await _resource();
    final outside = await Directory.systemTemp.createTemp('gl_outside_');
    final outsideFile = File(p.join(outside.path, 'cc.js'));
    await outsideFile.writeAsString('outside');
    await Link(p.join(root.path, 'cocos-js', 'cc.js')).create(outsideFile.path);

    final result = await ResourceValidator().validate(root);

    expect(result.isValid, isFalse);
    expect(result.errorCode, 'resource_path_unsafe');
  });

  test('readiness rejects a linked Cocos file inside the resource root',
      () async {
    final root = await _resource();
    await Link(p.join(root.path, 'cocos-js', 'cc.js')).create(
      p.join(root.path, 'src', 'settings.json'),
    );

    final result = await ResourceValidator().validate(root);

    expect(result.isValid, isFalse);
    expect(result.errorCode, 'resource_path_unsafe');
  });
}

// Retain fixtures for inspection.
Future<Directory> _resource() async {
  final root = await Directory.systemTemp.createTemp('gl_resource_check_');
  for (final path in ['assets', 'src', 'cocos-js']) {
    await Directory(p.join(root.path, path)).create();
  }
  await File(p.join(root.path, 'index.html')).writeAsString(
    '<title>PvZ2 Gardendless</title>pvzge',
  );
  await File(p.join(root.path, 'src', 'settings.json'))
      .writeAsString('{"platform":"web-mobile"}');
  await File(p.join(root.path, 'src', 'import-map.json')).writeAsString('{}');
  return root;
}
