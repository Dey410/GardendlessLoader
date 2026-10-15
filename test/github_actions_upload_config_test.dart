import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android CI supplies a monotonic version code', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();

    final versionStep = _workflowStep(
      workflow,
      'Compute Android version code',
    );
    final buildStep = _workflowStep(workflow, 'Build release APK');

    expect(versionStep, contains('100000 + GITHUB_RUN_NUMBER'));
    expect(versionStep, contains('version_code='));
    expect(versionStep, contains(r'$GITHUB_OUTPUT'));
    expect(
      buildStep,
      contains(
        r'--build-number "${{ steps.android_version.outputs.version_code }}"',
      ),
    );
  });

  test('GitHub Actions builds and directly uploads maintained platforms', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();

    expect(workflow, contains('\n  android:'));
    expect(workflow, contains('\n  ios:'));
    expect(workflow, contains('\n  harmonyos:'));
    expect(
      workflow,
      contains('Build unsigned HarmonyOS HAP (ohos-arm64)'),
    );
    expect(
      workflow,
      contains('flutter build hap --release --target-platform ohos-arm64'),
    );
    expect(workflow, isNot(contains('target-platform: ohos-x64')));

    _expectDirectFileUpload(
      workflow,
      stepName: 'Upload APK',
      path: 'build/app/outputs/flutter-apk/GardendlessLoader-android.apk',
    );
    _expectDirectFileUpload(
      workflow,
      stepName: 'Upload unsigned IPA',
      path: 'build/ios/ipa/GardendlessLoader-unsigned.ipa',
    );
    _expectDirectFileUpload(
      workflow,
      stepName: 'Upload unsigned HarmonyOS HAP',
      path: 'build/ohos/unsigned/GardendlessLoader-unsigned-ohos-arm64.hap',
    );
  });

  test('CI rejects artifacts whose embedded version differs from pubspec', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();

    final androidStep = _workflowStep(workflow, 'Verify APK version');
    final iosStep = _workflowStep(workflow, 'Verify IPA version');
    final harmonyStep = _workflowStep(workflow, 'Verify HAP version');

    for (final step in [androidStep, iosStep, harmonyStep]) {
      expect(step, contains('EXPECTED_VERSION='));
      expect(step, contains(r'test "$ACTUAL_VERSION" = "$EXPECTED_VERSION"'));
    }
    expect(androidStep, contains(r'find "$ANDROID_HOME/build-tools"'));
    expect(androidStep, contains('dump badging'));
    expect(iosStep, contains('CFBundleShortVersionString'));
    expect(harmonyStep, contains('pack.info'));
  });

  test('HarmonyOS CI pins the previously validated Flutter revision', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();
    final setupStep = _workflowStep(
      workflow,
      'Set up OpenHarmony Flutter SDK',
    );

    expect(
      workflow,
      contains(
        'OHOS_FLUTTER_SDK_REVISION: '
        'add49ea449c07c6e9a4bcfe7c03f2169fc15cd2b',
      ),
    );
    expect(
      workflow,
      contains('OHOS_FLUTTER_SDK_BRANCH: oh-3.35.7-release'),
    );
    expect(setupStep, contains(r'--branch "$OHOS_FLUTTER_SDK_BRANCH"'));
    expect(
      setupStep,
      contains(r'git checkout --detach "$OHOS_FLUTTER_SDK_REVISION"'),
    );
    expect(
      setupStep,
      contains(r'test "$(git rev-parse HEAD)" = "$OHOS_FLUTTER_SDK_REVISION"'),
    );
  });

  test('one quality gate owns explicit safe Flutter and shared runtime tests',
      () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();
    final quality = _workflowJob(workflow, 'quality');
    expect(quality, contains('run: flutter analyze'));
    expect(quality, contains('npm ci --ignore-scripts --prefix ohos/test'));
    expect(quality, contains('npm test --prefix ohos/test'));
    expect(quality,
        contains('cache-dependency-path: ohos/test/package-lock.json'));
    for (final script in [
      'check_game_bridge.mjs',
      'check_export_download_patch.mjs',
      'check_audio_diagnostic.mjs',
      'check_auto_sun.mjs',
      'check_touch_state_machine.mjs',
      'check_touch_patch.mjs',
    ]) {
      expect(quality, contains('node tool/$script'));
    }
    final safeTests =
        _workflowStep(workflow, 'Test retained and pure Flutter behavior');
    for (final filename in [
      'resource_package_test.dart',
      'resource_readiness_test.dart',
      'resource_self_check_test.dart',
      'http_text_test.dart',
      'about_content_cache_test.dart',
      'app_paths_retained_test.dart',
      'game_session_test.dart',
      'github_actions_upload_config_test.dart',
      'harmony_build_config_test.dart',
    ]) {
      expect(safeTests, contains('test/$filename'));
    }
    for (final unsafe in [
      'import_service_test.dart',
      'manifest_store_test.dart',
      'app_controller_paths_test.dart',
      'resource_validator_test.dart',
      'game_session_store_test.dart',
      'home_page_layout_test.dart',
    ]) {
      expect(safeTests, isNot(contains('test/$unsafe')));
    }
    expect('flutter test'.allMatches(workflow), hasLength(1));
    expect(workflow, isNot(contains('find test')));
    for (final platform in ['android', 'ios', 'harmonyos']) {
      expect(_workflowJob(workflow, platform), contains('needs: quality'));
    }
  });

  test('native test gates select pure and retained cases explicitly', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();
    final swift = _workflowStep(workflow, 'Test native GardendlessKit');
    expect(swift, contains('swift test --disable-sandbox'));
    expect(swift, contains('--filter'));
    expect(swift, contains('FileTaskCoordinatorTests|TaskCallbackGateTests'));
    expect(swift, contains('ReservedMetadataPathsTests|ResourceMIMETests'));
    expect(swift, isNot(contains('PathSandboxTests')));
    final android =
        _workflowStep(workflow, 'Test retained and pure Android behavior');
    expect(android, contains('./gradlew testReleaseUnitTest'));
    expect(
        android,
        contains(
            '--tests io.github.dey410.gardendlessloader.game.FileCommitGateTest'));
    expect(
        android,
        contains(
            '--tests io.github.dey410.gardendlessloader.game.FileTransferCursorTest'));
    expect(
        android,
        contains(
            '--tests io.github.dey410.gardendlessloader.game.FileTransferRetainedFixtureTest'));
    expect(
        android,
        contains(
            '--tests io.github.dey410.gardendlessloader.game.GameResourceRetainedFixtureTest'));
    expect(android, isNot(contains('GpNextPackArchiveNormalizerTest')));
    expect(android, isNot(contains('game.GameResourceResolverTest')));
  });

  test(
      'all three uploaded artifacts record digest version and host ABI evidence',
      () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();
    for (final label in ['APK', 'unsigned IPA', 'unsigned HarmonyOS HAP']) {
      final summary = _workflowStep(workflow, 'Summarize $label');
      expect(summary, contains('SHA256='));
      expect(summary, contains(r'echo "version=$VERSION"'));
      expect(summary, contains(r'echo "sha256=$SHA256"'));
      expect(summary, contains(r'echo "host_abi=$HOST_ABI"'));
      expect(summary, contains(r'$GITHUB_STEP_SUMMARY'));
    }
    final aggregate = _workflowJob(workflow, 'artifacts');
    expect(aggregate, contains('if: always()'));
    expect(aggregate, contains('needs: [quality, android, ios, harmonyos]'));
    for (final platform in ['android', 'ios', 'harmonyos']) {
      expect(aggregate, contains('needs.$platform.result'));
      expect(aggregate, contains('needs.$platform.outputs.sha256'));
    }
    expect(aggregate, contains("result != 'success'"));
    expect(aggregate, contains('actual != version'));
    expect(aggregate, contains("abi != '1'"));
    expect(aggregate, contains("re.fullmatch(r'[a-f0-9]{64}', digest)"));
  });
}

void _expectDirectFileUpload(
  String workflow, {
  required String stepName,
  required String path,
}) {
  final uploadStep = _workflowStep(workflow, stepName);

  expect(uploadStep, contains('uses: actions/upload-artifact@v7'));
  expect(uploadStep, contains('path: $path'));
  expect(uploadStep, contains('archive: false'));
  expect(uploadStep, isNot(contains('          name:')));
}

String _workflowStep(String workflow, String stepName) {
  final normalizedWorkflow = workflow.replaceAll('\r\n', '\n');
  final match = RegExp(
    '^      - name: ${RegExp.escape(stepName)}\n'
    r'(?:(?!^      - name: |^  [a-zA-Z0-9_-]+:).*\n?)*',
    multiLine: true,
  ).firstMatch(normalizedWorkflow);

  if (match == null) {
    fail('Could not find workflow step "$stepName".');
  }

  return match.group(0)!;
}

String _workflowJob(String workflow, String job) {
  final match = RegExp(
    '^  ${RegExp.escape(job)}:\n'
    r'(?:(?!^  [a-zA-Z0-9_-]+:).*\n?)*',
    multiLine: true,
  ).firstMatch(workflow.replaceAll('\r\n', '\n'));
  if (match == null) fail('Could not find workflow job "$job".');
  return match.group(0)!;
}
