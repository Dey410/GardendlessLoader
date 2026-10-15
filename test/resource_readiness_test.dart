import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/resource_validator.dart';
import 'package:path/path.dart' as p;

void main() {
  test('one readiness check identifies a standard version and readable entry',
      () async {
    final root = await _resource();

    final result = await ResourceValidator().validate(root);

    expect(result.isValid, isTrue);
    expect(result.gameVersion, '0.12.0-next');
    expect(result.buildProfile, ResourceBuildProfile.standardWeb);
  });

  test('reads the game version embedded directly in the module entry',
      () async {
    final root = await _resource();
    await File(p.join(root.path, 'index.html')).writeAsString(
      '<title>PvZ2 Gardendless</title>pvzge<script src="./assets/index-test.js" type="module"></script>',
    );
    await File(p.join(root.path, 'assets', 'index-test.js')).writeAsString(
      "console.info('Playing version 0.11.4');",
    );

    final result = await ResourceValidator().validate(root);

    expect(result.isValid, isTrue);
    expect(result.gameVersion, '0.11.4');
  });

  test('reads assets-root GP module references from the 0.15 entry fixture',
      () async {
    final root = await _resource();
    final fixture = Directory('test/fixtures/gp_next_015_version');
    await File(p.join(root.path, 'index.html')).writeAsString(
      '${await File(p.join(fixture.path, 'index.html')).readAsString()}pvzge',
    );
    for (final filename in ['index-DhuaRljc.js', 'gp-next-CjHHUfSh.js']) {
      await File(p.join(fixture.path, 'assets', filename))
          .copy(p.join(root.path, 'assets', filename));
    }

    final result = await ResourceValidator().validate(root);

    expect(result.isValid, isTrue);
    expect(result.gameVersion, '0.15.0');
  });

  test('readiness rejects a missing native Cocos entry', () async {
    final root = await _resource(includeCocos: false);

    final result = await ResourceValidator().validate(root);

    expect(result.isValid, isFalse);
    expect(result.errorCode, 'missing_required_file');
  });

  test('readiness refuses a linked root before reading its contents', () async {
    final root = await _resource();
    final parent = await Directory.systemTemp.createTemp('gl_readiness_link_');
    final link = Link(p.join(parent.path, 'linked'));
    await link.create(root.path);

    final result = await ResourceValidator().validate(Directory(link.path));

    expect(result.isValid, isFalse);
    expect(result.errorCode, 'resource_path_unsafe');
  });

  test('readiness refuses a linked required directory', () async {
    final root = await _resource(linkedSource: true);

    final result = await ResourceValidator().validate(root);

    expect(result.isValid, isFalse);
    expect(result.errorCode, 'resource_path_unsafe');
  });

  test('one readiness check finds the version in the referenced GP module',
      () async {
    final root = await _resource();
    await File(p.join(root.path, 'index.html')).writeAsString('''
<title>Cocos Creator | PvZ2_Gardendless</title>
<script type="module" data-gardendless-src="./assets/index-test.js"></script>
''');
    await File(p.join(root.path, 'assets', 'index-test.js'))
        .writeAsString("import('./gp-next-test.js');");
    await File(p.join(root.path, 'assets', 'gp-next-test.js')).writeAsString('''
console.info('GP-Next loading'); window.gpNext = {}; function loadAllPatches() {}
import('./patcher-test.js'); import('./file-loader-test.js');
console.info('Game Version: v0.15.0');
''');

    final result = await ResourceValidator().validate(root);

    expect(result.isValid, isTrue);
    expect(result.hasGpNext, isTrue);
    expect(result.gameVersion, '0.15.0');
  });
}

// Fixtures are deliberately retained: this task does not authorize deletion.
Future<Directory> _resource(
    {bool includeCocos = true, bool linkedSource = false}) async {
  final root = await Directory.systemTemp.createTemp('gl_readiness_');
  await Directory(p.join(root.path, 'assets')).create();
  await Directory(p.join(root.path, 'cocos-js')).create();
  var source = Directory(p.join(root.path, 'src'));
  if (linkedSource) {
    source = await Directory.systemTemp.createTemp('gl_readiness_source_');
    await Link(p.join(root.path, 'src')).create(source.path);
  } else {
    await source.create();
  }
  await File(p.join(root.path, 'index.html')).writeAsString(
    '<title>PvZ2 Gardendless | v0.12.0-next</title>pvzge',
  );
  await File(p.join(source.path, 'settings.json'))
      .writeAsString('{"platform":"web-mobile"}');
  await File(p.join(source.path, 'import-map.json')).writeAsString('{}');
  if (includeCocos) {
    await File(p.join(root.path, 'cocos-js', 'cc.js'))
        .writeAsString('window.cc = {};');
  }
  return root;
}
