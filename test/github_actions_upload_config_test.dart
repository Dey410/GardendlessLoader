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
