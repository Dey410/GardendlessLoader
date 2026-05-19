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
    expect(
        File('ohos/entry/src/main/ets/MainAbility/MainAbility.ets')
            .existsSync(),
        isTrue);
    expect(
        File('ohos/entry/src/main/ets/plugins/DocumentPickerPlugin.ets')
            .existsSync(),
        isTrue);
  });

  test('OpenHarmony module does not request legacy user storage permissions',
      () {
    final module = File('ohos/entry/src/main/module.json5').readAsStringSync();

    expect(module, isNot(contains('ohos.permission.READ_USER_STORAGE')));
    expect(module, isNot(contains('ohos.permission.WRITE_USER_STORAGE')));
  });

  test('OpenHarmony document picker channel is registered', () {
    final ability =
        File('ohos/entry/src/main/ets/entryability/EntryAbility.ets')
            .readAsStringSync();
    final picker =
        File('ohos/entry/src/main/ets/plugins/DocumentPickerPlugin.ets')
            .readAsStringSync();

    expect(ability, contains('DocumentPickerPlugin'));
    expect(ability, contains('addPlugin'));
    expect(
        picker, contains('io.github.dey410.gardendlessloader/document_picker'));
    expect(picker, contains('import AbilityPluginBinding, { AbilityAware }'));
    expect(picker, contains('binding.getAbilityContext()'));
    expect(picker, contains('pickDocsDirectory'));
    expect(picker, contains('DocumentViewPicker'));
    expect(picker, contains('DocumentSelectMode.FOLDER'));
  });

  test('GitHub Actions exports a HAP artifact', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();

    expect(workflow, contains('Build unsigned HarmonyOS HAP'));
    expect(workflow, contains('openharmony-tpc/flutter_flutter.git'));
    expect(workflow, contains('oh-3.35.7-release'));
    expect(workflow, contains('OHOS_MIN_DART_VERSION: 3.5.0'));
    expect(workflow, contains('Verify OpenHarmony Dart SDK compatibility'));
    expect(workflow, contains('HarmonyOS HAP skipped'));
    expect(workflow, contains('enabled=false'));
    expect(workflow,
        isNot(contains('OHOS_COMMANDLINE_TOOLS_URL secret is required')));
    expect(workflow,
        contains('cp pubspec_overrides.ohos.yaml pubspec_overrides.yaml'));
    expect(workflow, contains('for TARGET_PLATFORM in ohos-arm64 ohos-x64'));
    expect(
      workflow,
      contains(
          'flutter build hap --release --target-platform "\$TARGET_PLATFORM"'),
    );
    expect(workflow,
        contains("find ohos/entry/build -type f -name '*unsigned*.hap'"));
    expect(workflow, contains('gardendless-loader-unsigned-haps'));
    expect(workflow, contains('build/ohos/unsigned/*.hap'));
  });
}
