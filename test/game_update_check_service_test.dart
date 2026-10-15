import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/game_update_check_service.dart';

void main() {
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
