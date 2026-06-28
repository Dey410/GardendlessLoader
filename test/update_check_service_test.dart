import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/constants.dart';
import 'package:gardendless_loader/src/services/update_check_service.dart';

void main() {
  test('fallback app version matches the pubspec package version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(appVersion, match!.group(1)!.split('+').first);
  });

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

  test('uses installed package version before fallback app version', () async {
    final service = UpdateCheckService(
      currentVersion: '0.1.0',
      installedVersionLoader: () async => '0.2.0+2',
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

  test('falls back to app version when installed version is unavailable',
      () async {
    final service = UpdateCheckService(
      currentVersion: '0.2.0',
      installedVersionLoader: () async => throw const SocketException('no api'),
      loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
        statusCode: HttpStatus.ok,
        body: '''
{
  "tag_name": "v0.2.1",
  "html_url": "https://github.com/Dey410/GardendlessLoader/releases/tag/v0.2.1"
}
''',
      ),
    );

    final update = await service.checkForUpdate();

    expect(update?.currentVersion, '0.2.0');
    expect(update?.latestVersion, '0.2.1');
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
