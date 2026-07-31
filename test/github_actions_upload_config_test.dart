import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GitHub Actions only builds and directly uploads HarmonyOS ARM', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();

    expect(workflow, isNot(contains('\n  android:')));
    expect(workflow, isNot(contains('\n  ios:')));
    expect(workflow, contains('\n  harmonyos:'));
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
