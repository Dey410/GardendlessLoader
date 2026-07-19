import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/game_update_check_service.dart';

void main() {
  test('loads the imported game version from the page title', () async {
    final root = await Directory.systemTemp.createTemp('gl_game_version_');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/index.html').writeAsString('''
<!doctype html>
<html><head><title>PvZ2 Gardendless Online | 0.12.0-next</title></head></html>
''');

    final version = await GameUpdateCheckService().loadCurrentVersion(root);

    expect(version, '0.12.0-next');
  });

  test('normalizes a v-prefixed imported game version', () async {
    final root = await Directory.systemTemp.createTemp('gl_game_version_');
    addTearDown(() => root.delete(recursive: true));
    await File(
      '${root.path}/index.html',
    ).writeAsString('<title>PvZ2 Gardendless | v0.8.2</title>');

    final version = await GameUpdateCheckService().loadCurrentVersion(root);

    expect(version, '0.8.2');
  });

  test('loads a GP-Next game version from its module entry', () async {
    final root = await Directory.systemTemp.createTemp('gl_game_version_');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/assets').create();
    await File('${root.path}/index.html').writeAsString('''
<title>Cocos Creator | PvZ2_Gardendless</title>
<script src="./assets/index-test.js" type="module"></script>
''');
    await File(
      '${root.path}/assets/index-test.js',
    ).writeAsString("console.info('Playing version 0.11.4');");

    final version = await GameUpdateCheckService().loadCurrentVersion(root);

    expect(version, '0.11.4');
  });

  test(
    'selects the greatest stable game tag and ignores prereleases',
    () async {
      final service = GameUpdateCheckService(
        loader: (uri, timeout, maxBytes) async {
          expect(
            uri.toString(),
            'https://api.github.com/repos/Gzh0821/pvzg_site/tags?per_page=100',
          );
          return const GameUpdateCheckHttpResponse(
            statusCode: HttpStatus.ok,
            body: '''
[
  {"name":"0.10.0"},
  {"name":"0.12.0-rc.1"},
  {"name":"0.9.3"},
  {"name":"0.11.0"},
  {"name":"0.11.1-next"}
]
''',
          );
        },
      );

      final update = (await service.check(currentVersion: '0.10.0')).update;

      expect(update?.currentVersion, '0.10.0');
      expect(update?.latestVersion, '0.11.0');
      expect(update?.tagName, '0.11.0');
    },
  );

  test('offers the stable release to an imported prerelease', () async {
    final service = GameUpdateCheckService(
      loader: (uri, timeout, maxBytes) async =>
          const GameUpdateCheckHttpResponse(
        statusCode: HttpStatus.ok,
        body: '[{"name":"0.12.0"}]',
      ),
    );

    final update = (await service.check(currentVersion: '0.12.0-next')).update;

    expect(update?.latestVersion, '0.12.0');
  });
}
