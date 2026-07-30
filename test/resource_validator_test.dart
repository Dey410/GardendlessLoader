import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/resource_validator.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late ResourceValidator validator;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gl_validator_');
    validator = ResourceValidator();
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('rejects missing index.html', () async {
    await _writeValidResource(temp, writeIndex: false);

    final result = await validator.validate(temp);

    expect(result.status, ResourceStatus.invalid);
    expect(result.errorCode, 'missing_required_file');
  });

  test('rejects title fingerprint mismatch', () async {
    await _writeValidResource(temp, title: 'Other Game');

    final result = await validator.validate(temp);

    expect(result.status, ResourceStatus.invalid);
    expect(result.errorCode, 'title_fingerprint_mismatch');
  });

  test('rejects missing pvzge fingerprint', () async {
    await _writeValidResource(
      temp,
      indexBody: '<html><title>PvZ2 Gardendless</title></html>',
    );

    final result = await validator.validate(temp);

    expect(result.status, ResourceStatus.invalid);
    expect(result.errorCode, 'index_fingerprint_mismatch');
  });

  test('rejects settings without cocos config', () async {
    await _writeValidResource(temp, settingsJson: '{"name":"nope"}');

    final result = await validator.validate(temp);

    expect(result.status, ResourceStatus.invalid);
    expect(result.errorCode, 'settings_cocos_config_missing');
  });

  test('accepts valid docs resource', () async {
    await _writeValidResource(temp);

    final result = await validator.validate(temp);
    final stats = await validator.scanStats(
      temp,
      detectedTitle: result.detectedTitle,
    );

    expect(result.isValid, isTrue);
    expect(result.detectedTitle, 'PvZ2 Gardendless');
    expect(result.buildProfile, ResourceBuildProfile.standardWeb);
    expect(result.gpNextVersion, isNull);
    expect(stats.fileCount, greaterThanOrEqualTo(4));
    expect(stats.totalBytes, greaterThan(0));
  });

  test('accepts current pvzge Cocos settings shape', () async {
    await _writeValidResource(
      temp,
      settingsJson: '''
{
  "CocosEngine": "3.8.4",
  "engine": {
    "debug": false,
    "platform": "web-mobile",
    "builtinAssets": []
  },
  "assets": {
    "remoteBundles": [],
    "subpackages": [],
    "preloadBundles": [{"bundle": "resources"}, {"bundle": "main"}],
    "bundleVers": {}
  },
  "launch": {
    "launchScene": "db://assets/scene/preSplashScene.scene"
  },
  "scripting": {
    "scriptPackages": ["../src/chunks/bundle.js"]
  }
}
''',
    );

    final result = await validator.validate(temp);

    expect(result.isValid, isTrue);
  });

  test('detects a GP-Next desktop build without checking its version',
      () async {
    await _writeGpNextResource(temp, version: '9.9.9');

    final result = await validator.validate(temp);

    expect(result.isValid, isTrue);
    expect(result.detectedTitle, 'Cocos Creator | PvZ2_Gardendless');
    expect(result.buildProfile, ResourceBuildProfile.gpNext);
    expect(result.gpNextVersion, isNull);
    expect(result.gpNextCompatibilityError, isNull);
    expect(result.gpNextCompatible, isTrue);
  });

  test(
    'disables the GP-Next bridge when a required module is missing',
    () async {
      await _writeGpNextResource(
        temp,
        version: '1.4.2',
        includeJsModLoader: false,
      );

      final result = await validator.validate(temp);

      expect(result.isValid, isTrue);
      expect(result.hasGpNext, isTrue);
      expect(result.gpNextCompatible, isFalse);
      expect(
        result.gpNextCompatibilityError,
        'GP-Next 缺少兼容模块：JS mod loader module',
      );
    },
  );
}

Future<void> _writeGpNextResource(
  Directory root, {
  required String version,
  bool includeJsModLoader = true,
}) async {
  await _writeValidResource(
    root,
    indexBody: '''
<html>
  <head><title>Cocos Creator | PvZ2_Gardendless</title></head>
  <body><script type="module" src="./assets/index-test.js"></script></body>
</html>
''',
  );
  await File(p.join(root.path, 'assets', 'index-test.js')).writeAsString('''
console.info('GP-Next loading...');
window.gpNext = {};
function loadAllPatches() {}
import('./patcher-test.js');
import('./file-loader-test.js');
${includeJsModLoader ? 'import(\'./js-mod-loader-test.js\');' : ''}
import('./config-test.js');
''');
  await File(
    p.join(root.path, 'assets', 'config-test.js'),
  ).writeAsString("export const version = '$version';");
}

Future<void> _writeValidResource(
  Directory root, {
  bool writeIndex = true,
  String title = 'PvZ2 Gardendless',
  String? indexBody,
  String settingsJson =
      '{"platform":"web-mobile","launchScene":"db://assets/start.scene"}',
}) async {
  await Directory(p.join(root.path, 'assets')).create(recursive: true);
  await Directory(p.join(root.path, 'cocos-js')).create(recursive: true);
  await Directory(p.join(root.path, 'src')).create(recursive: true);
  if (writeIndex) {
    await File(p.join(root.path, 'index.html')).writeAsString(
      indexBody ??
          '<html><head><title>$title</title></head><body>pvzge</body></html>',
    );
  }
  await File(
    p.join(root.path, 'src', 'settings.json'),
  ).writeAsString(settingsJson);
  await File(p.join(root.path, 'src', 'import-map.json')).writeAsString('{}');
  await File(
    p.join(root.path, 'cocos-js', 'cc.js'),
  ).writeAsString('console.log("cc");');
}
