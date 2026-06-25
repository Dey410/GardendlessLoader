import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GitHub Actions uploads single-file artifacts without ZIP wrapping', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();

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
      stepName: 'Upload unsigned HarmonyOS arm64 HAP',
      path: 'build/ohos/unsigned/GardendlessLoader-unsigned-ohos-arm64.hap',
    );
    _expectDirectFileUpload(
      workflow,
      stepName: 'Upload unsigned HarmonyOS x64 HAP',
      path: 'build/ohos/unsigned/GardendlessLoader-unsigned-ohos-x64.hap',
    );
  });

  test('GitHub Actions keeps directory artifacts archived', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();
    final webUpload = _workflowStep(workflow, 'Upload Web bundle');

    expect(webUpload, contains('uses: actions/upload-artifact@v7'));
    expect(webUpload, contains('name: gardendless-loader-web'));
    expect(webUpload, contains('path: build/web'));
    expect(webUpload, isNot(contains('archive: false')));
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
  final match = RegExp(
    '^      - name: ${RegExp.escape(stepName)}\n'
    r'(?:(?!^      - name: |^  [a-zA-Z0-9_-]+:).*\n?)*',
    multiLine: true,
  ).firstMatch(workflow);

  if (match == null) {
    fail('Could not find workflow step "$stepName".');
  }

  return match.group(0)!;
}
