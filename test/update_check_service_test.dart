import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/constants.dart';
import 'package:gardendless_loader/src/services/update_check_service.dart';

void main() {
  test('release version metadata exposes version 0.8.2 consistently', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(pubspec);
    final harmonyAppConfig = File('ohos/AppScope/app.json5').readAsStringSync();

    expect(match, isNotNull);
    expect(match!.group(1), '0.8.2');
    expect(appVersion, match.group(1)!.split('+').first);
    expect(harmonyAppConfig, contains('"versionName": "0.8.2"'));
    expect(harmonyAppConfig, contains('"versionCode": 8002000'));
  });

  test('direct Xcode builds use the tracked loader version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([^\s+]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    final appVersionConfig =
        File('ios/Flutter/AppVersion.xcconfig').readAsStringSync();
    final debugConfig = File('ios/Flutter/Debug.xcconfig').readAsStringSync();
    final releaseConfig =
        File('ios/Flutter/Release.xcconfig').readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final xcodeProject =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    expect(appVersionConfig, contains('APP_VERSION=$version'));
    for (final config in <String>[debugConfig, releaseConfig]) {
      expect(config, contains('#include "Generated.xcconfig"'));
      expect(config, contains('#include "AppVersion.xcconfig"'));
      expect(
        config.indexOf('#include "AppVersion.xcconfig"'),
        greaterThan(config.indexOf('#include "Generated.xcconfig"')),
      );
    }
    expect(
      infoPlist,
      contains('<string>\$(APP_VERSION)</string>'),
    );
    expect(xcodeProject, contains('Verify App Version'));
    expect(xcodeProject, contains('verify_app_version.sh'));
  });

  test('direct Xcode builds use a supported iOS deployment target', () {
    final podfile = File('ios/Podfile').readAsStringSync();
    final xcodeProject =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    expect(podfile, contains("platform :ios, '15.0'"));
    expect(
      podfile,
      contains(
        "config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'",
      ),
    );
    expect(
      RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = 15\.0;')
          .allMatches(xcodeProject)
          .length,
      3,
    );
    expect(xcodeProject, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 14.5;')));
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
