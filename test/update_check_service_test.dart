import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/update_check_service.dart';

void main() {
  test('returns update info when latest GitHub release is newer', () async {
    final service = UpdateCheckService(
      currentVersion: '0.1.0',
      loader: (uri, timeout, maxBytes) async {
        expect(
          uri.toString(),
          'https://api.github.com/repos/Dey410/GardendlessLoader/releases/latest',
        );
        return const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{
  "tag_name": "v0.2.0",
  "name": "GardendlessLoader 0.2.0",
  "html_url": "https://github.com/Dey410/GardendlessLoader/releases/tag/v0.2.0",
  "body": "Bug fixes",
  "published_at": "2026-05-20T08:00:00Z"
}
''',
        );
      },
    );

    final update = await service.checkForUpdate();

    expect(update?.latestVersion, '0.2.0');
    expect(update?.tagName, 'v0.2.0');
    expect(
      update?.releaseUrl,
      'https://github.com/Dey410/GardendlessLoader/releases/tag/v0.2.0',
    );
    expect(update?.releaseName, 'GardendlessLoader 0.2.0');
    expect(update?.releaseNotes, 'Bug fixes');
    expect(update?.publishedAt, DateTime.utc(2026, 5, 20, 8));
  });

  test('returns null when latest GitHub release is not newer', () async {
    final service = UpdateCheckService(
      currentVersion: '0.2.0+3',
      loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
        statusCode: HttpStatus.ok,
        body: '''
{
  "tag_name": "v0.2.0",
  "html_url": "https://github.com/Dey410/GardendlessLoader/releases/tag/v0.2.0"
}
''',
      ),
    );

    final update = await service.checkForUpdate();

    expect(update, isNull);
  });

  test('throws update check exception when GitHub request fails', () {
    final service = UpdateCheckService(
      loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
        statusCode: HttpStatus.forbidden,
        body: '{}',
      ),
    );

    expect(service.checkForUpdate(), throwsA(isA<UpdateCheckException>()));
  });
}
