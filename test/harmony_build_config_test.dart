import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OpenHarmony override no longer carries a Flutter WebView plugin', () {
    final pubspec = File('pubspec_overrides.ohos.yaml').readAsStringSync();

    expect(pubspec, contains('openharmony-tpc/flutter_packages.git'));
    expect(pubspec, contains('packages/path_provider/path_provider'));
    expect(pubspec, isNot(contains('flutter_inappwebview')));
    expect(pubspec, contains('openharmony-sig/fluttertpc_wakelock_plus.git'));
    expect(pubspec, contains('wakelock_plus'));
    expect(pubspec, contains('wakelock_plus_platform_interface: 1.3.0'));
    expect(pubspec, contains('package_info_plus: ^4.2.0'));
  });

  test('OpenHarmony compatible test dependencies support Dart 3.9', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('wakelock_plus_platform_interface: ^1.3.0'));
    expect(pubspec, isNot(contains('wakelock_plus_platform_interface: ^1.4')));
    expect(pubspec, isNot(contains('wakelock_plus_platform_interface: ^1.5')));
  });

  test('OpenHarmony project files are present for HAP builds', () {
    expect(File('ohos/build-profile.json5').existsSync(), isTrue);
    expect(File('ohos/oh-package.json5').existsSync(), isTrue);
    expect(File('ohos/entry/build-profile.json5').existsSync(), isTrue);
    expect(File('ohos/entry/src/main/module.json5').existsSync(), isTrue);
    expect(
      File('ohos/entry/src/main/ets/MainAbility/MainAbility.ets').existsSync(),
      isTrue,
    );
  });

  test(
    'OpenHarmony module does not request legacy user storage permissions',
    () {
      final module = File(
        'ohos/entry/src/main/module.json5',
      ).readAsStringSync();

      expect(module, isNot(contains('ohos.permission.READ_USER_STORAGE')));
      expect(module, isNot(contains('ohos.permission.WRITE_USER_STORAGE')));
    },
  );

  test('OpenHarmony does not register the legacy folder picker', () {
    final ability = File(
      'ohos/entry/src/main/ets/entryability/EntryAbility.ets',
    ).readAsStringSync();
    final picker = File(
      'ohos/entry/src/main/ets/plugins/DocumentPickerPlugin.ets',
    ).readAsStringSync();

    expect(ability, isNot(contains('DocumentPickerPlugin')));
    expect(ability, isNot(contains('addPlugin(new DocumentPickerPlugin())')));
    expect(
      picker,
      contains('io.github.dey410.gardendlessloader/document_picker'),
    );
    expect(picker, contains("} from '@ohos/flutter_ohos';"));
    expect(
      picker,
      isNot(
        contains(
          '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware',
        ),
      ),
    );
    expect(picker, isNot(contains('AbilityAware')));
    expect(picker, isNot(contains('AbilityPluginBinding')));
    expect(picker, isNot(contains('binding.getAbility().context')));
    expect(picker, isNot(contains('binding.getAbilityContext()')));
    expect(picker, isNot(contains('pickDocsDirectory')));
    expect(picker, isNot(contains('DocumentViewPicker')));
    expect(picker, isNot(contains('DocumentSelectMode.FOLDER')));
  });

  test('OpenHarmony registers a streaming zip importer', () {
    final ability = File(
      'ohos/entry/src/main/ets/entryability/EntryAbility.ets',
    ).readAsStringSync();
    final importer = File(
      'ohos/entry/src/main/ets/plugins/ResourceZipImporterPlugin.ets',
    ).readAsStringSync();

    expect(ability, contains('ResourceZipImporterPlugin'));
    expect(ability, contains('addPlugin(new ResourceZipImporterPlugin())'));
    expect(
      importer,
      contains('io.github.dey410.gardendlessloader/resource_zip_importer'),
    );
    expect(importer, contains('pickAndExtractDocsZip'));
    expect(importer, contains('DocumentViewPicker'));
    expect(importer, contains('decompressFile'));
    expect(importer, contains('src/settings.json'));
    expect(importer, contains('src/import-map.json'));
  });

  test(
    'OpenHarmony extracts resources into the inactive slot without copying',
    () {
      final importer = File(
        'ohos/entry/src/main/ets/plugins/ResourceZipImporterPlugin.ets',
      ).readAsStringSync();

      expect(importer, contains('decompressFile(zipPath, targetDirectory)'));
      expect(importer, isNot(contains('copyDirectoryContents')));
    },
  );

  test('OpenHarmony streams ZIP import progress to Flutter', () {
    final importer = File(
      'ohos/entry/src/main/ets/plugins/ResourceZipImporterPlugin.ets',
    ).readAsStringSync();

    expect(importer, contains("invokeMethod('progress'"));
    expect(importer, contains("phase: 'receiving'"));
    expect(importer, contains("phase: 'extracting'"));
    expect(importer, contains("'processedBytes'"));
    expect(importer, contains("'totalBytes'"));
    expect(importer, contains("'processedFiles'"));
    expect(importer, contains("'totalFiles'"));
  });

  test('OpenHarmony GameAbility owns LocalStorage before loading GamePage', () {
    final ability = File(
      'ohos/entry/src/main/ets/game/GameAbility.ets',
    ).readAsStringSync();

    expect(ability, contains('new LocalStorage'));
    expect(ability, isNot(contains('LocalStorage.getShared()')));
    expect(
      ability,
      contains("windowStage.loadContent('pages/GamePage', this.storage)"),
    );
    expect(
      ability.indexOf('new LocalStorage'),
      lessThan(ability.indexOf("windowStage.loadContent('pages/GamePage'")),
    );
  });

  test('OpenHarmony native GameHost avoids known ArkTS build blockers', () {
    final gamePage = File(
      'ohos/entry/src/main/ets/pages/GamePage.ets',
    ).readAsStringSync();
    final gameBridge = File(
      'ohos/entry/src/main/ets/game/GameBridge.ets',
    ).readAsStringSync();
    final gpNextCore = File(
      'ohos/entry/src/main/ets/game/GpNextNativeCore.ets',
    ).readAsStringSync();
    final gameHostPlugin = File(
      'ohos/entry/src/main/ets/plugins/GameHostPlugin.ets',
    ).readAsStringSync();
    final arkTsSources = [
      gamePage,
      gameBridge,
      gpNextCore,
      gameHostPlugin,
    ].join('\n');

    expect(gamePage, contains('Stack() {'));
    expect(
      gamePage,
      contains(
        '.onOverrideUrlLoading((request: WebResourceRequest): boolean =>',
      ),
    );
    expect(gamePage, contains('request.getRequestUrl()'));
    expect(gamePage, isNot(contains('event.request.getRequestUrl()')));
    expect(gameHostPlugin, contains('interface GameSessionArguments'));
    expect(gameHostPlugin, contains("call.argument('schemaVersion')"));
    expect(gameHostPlugin, contains("call.argument('platform')"));
    expect(gameHostPlugin, contains("call.argument('origin')"));
    expect(gameHostPlugin, contains("call.argument('allowedRemoteHosts')"));
    expect(gameHostPlugin, isNot(contains('call.args as Object')));
    expect(gameHostPlugin, isNot(contains('call.argument as Object')));
    expect(gameHostPlugin, isNot(contains('call.arguments')));
    expect(gpNextCore, contains('class GpNextDirectoryEntry'));
    expect(arkTsSources, isNot(contains('writeTextSync')));
    expect(arkTsSources, isNot(contains('throw error;')));
  });

  test('GitHub Actions exports a HAP artifact', () {
    final workflow = File(
      '.github/workflows/build-mobile.yml',
    ).readAsStringSync();

    expect(workflow, contains('Build unsigned HarmonyOS HAP'));
    expect(workflow, contains('openharmony-tpc/flutter_flutter.git'));
    expect(workflow, contains('oh-3.35.7-release'));
    expect(workflow, contains('OHOS_MIN_DART_VERSION: 3.5.0'));
    expect(workflow, contains('Verify OpenHarmony Dart SDK compatibility'));
    expect(workflow, contains('HarmonyOS HAP skipped'));
    expect(workflow, contains('enabled=false'));
    expect(
      workflow,
      isNot(contains('OHOS_COMMANDLINE_TOOLS_URL secret is required')),
    );
    expect(
      workflow,
      contains('cp pubspec_overrides.ohos.yaml pubspec_overrides.yaml'),
    );
    expect(workflow, isNot(contains('target-platform: ohos-x64')));
    expect(workflow, isNot(contains('matrix:')));
    expect(
      workflow,
      contains('flutter build hap --release --target-platform ohos-arm64'),
    );
    expect(
      workflow,
      contains('GardendlessLoader-unsigned-ohos-arm64.hap'),
    );
    expect(workflow, contains('set +e'));
    expect(workflow, contains(r'FLUTTER_BUILD_STATUS="$?"'));
    expect(workflow, contains(r'exit "$FLUTTER_BUILD_STATUS"'));
    expect(workflow, contains('Unsigned HAP recovered'));
    expect(
      workflow.replaceAll(RegExp(r'\\\r?\n\s*'), ''),
      contains("find ohos/entry/build -type f -name '*unsigned*.hap'"),
    );
    expect(workflow, contains('Upload unsigned HarmonyOS HAP'));
    expect(
      workflow,
      contains(
        'build/ohos/unsigned/GardendlessLoader-unsigned-ohos-arm64.hap',
      ),
    );
  });
}
