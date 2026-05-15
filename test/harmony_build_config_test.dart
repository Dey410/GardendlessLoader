import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OpenHarmony override uses compatible plugin forks', () {
    final pubspec = File('pubspec_overrides.ohos.yaml').readAsStringSync();

    expect(pubspec, contains('openharmony-tpc/flutter_packages.git'));
    expect(pubspec, contains('packages/path_provider/path_provider'));
    expect(pubspec, contains('openharmony-sig/flutter_inappwebview.git'));
    expect(pubspec, contains('br_v6.1.5_ohos'));
    expect(pubspec, contains('flutter_inappwebview'));
    expect(pubspec, contains('openharmony-sig/fluttertpc_wakelock_plus.git'));
    expect(pubspec, contains('wakelock_plus'));
  });

  test('OpenHarmony project files are present for HAP builds', () {
    expect(File('ohos/build-profile.json5').existsSync(), isTrue);
    expect(File('ohos/oh-package.json5').existsSync(), isTrue);
    expect(File('ohos/entry/build-profile.json5').existsSync(), isTrue);
    expect(File('ohos/entry/src/main/module.json5').existsSync(), isTrue);
    expect(File('ohos/entry/src/main/ets/MainAbility/MainAbility.ets').existsSync(), isTrue);
  });

  test('GitHub Actions exports a HAP artifact', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();

    expect(workflow, contains('Build HarmonyOS HAP'));
    expect(workflow, contains('openharmony-tpc/flutter_flutter.git'));
    expect(workflow, contains('oh-3.35.7-release'));
    expect(workflow, contains('OHOS_FLUTTER_SDK_VERSION: 3.35.7'));
    expect(workflow, contains('flutter.version.json'));
    expect(workflow, contains(r'"frameworkVersion": "$OHOS_FLUTTER_SDK_VERSION"'));
    expect(workflow, contains('OHOS_MIN_DART_VERSION: 3.5.0'));
    expect(workflow, contains('Verify OpenHarmony Dart SDK compatibility'));
    expect(workflow, contains('HarmonyOS HAP skipped'));
    expect(workflow, contains('enabled=false'));
    expect(workflow, isNot(contains('OHOS_COMMANDLINE_TOOLS_URL secret is required')));
    expect(workflow, contains('cp pubspec_overrides.ohos.yaml pubspec_overrides.yaml'));
    expect(workflow, contains('flutter build hap --release --target-platform ohos-arm64'));
    expect(workflow, contains('gardendless-loader-hap'));
    expect(
      workflow,
      contains('ohos/entry/build/default/outputs/default/entry-default-signed.hap'),
    );
  });
}
