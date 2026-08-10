import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android ZIP picker uses a custom-ROM-compatible MIME contract', () {
    final activity = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('Intent.ACTION_OPEN_DOCUMENT'));
    expect(activity, contains('Intent.EXTRA_MIME_TYPES'));
    expect(activity, contains('type = "*/*"'));
    expect(activity, isNot(contains('type = "application/zip"')));
    expect(activity, contains('Intent.ACTION_GET_CONTENT'));
    expect(activity, contains('ActivityNotFoundException'));
  });

  test('Android streams ZIP import progress to Flutter', () {
    final activity = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('resourceZipImporterChannel'));
    expect(activity, contains('invokeMethod("progress"'));
    expect(activity, contains('phase = "receiving"'));
    expect(activity, contains('phase = "extracting"'));
    expect(activity, contains('"processedBytes"'));
    expect(activity, contains('"totalBytes"'));
    expect(activity, contains('"processedFiles"'));
    expect(activity, contains('"totalFiles"'));
  });

  test('Android native game host owns save export and GP-Next picking', () {
    final activity = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameActivity.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final build = File('android/app/build.gradle').readAsStringSync();

    expect(build, contains('namespace = "io.github.dey410.gardendlessloader"'));
    expect(manifest, contains('android:name=".game.GameActivity"'));
    expect(manifest, contains('android:exported="false"'));
    expect(activity, contains('beginChunkedExport'));
    expect(activity, contains('Intent.ACTION_CREATE_DOCUMENT'));
    expect(activity, contains('input.copyTo(output, 128 * 1024)'));
    expect(activity, contains('export_in_progress'));
    expect(activity, contains('export_picker_failed'));
    expect(activity, contains('export_cancelled'));
    expect(activity, contains('beginGpNextPackageImport'));
    expect(activity, contains('Intent.ACTION_OPEN_DOCUMENT'));
    expect(activity, contains('Intent.EXTRA_ALLOW_MULTIPLE'));
  });

  test('Android document pickers use the shared adaptive orientation policy',
      () {
    final gameActivity = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameActivity.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/MainActivity.kt',
    ).readAsStringSync();
    final policy = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/DocumentPickerOrientationPolicy.kt',
    ).readAsStringSync();

    expect(gameActivity, contains('private fun launchDocumentPicker('));
    expect(gameActivity, contains('prepareForDocumentPicker()'));
    expect(mainActivity, contains('prepareForDocumentPicker()'));
    expect(policy, contains('const val COMPACT_BREAKPOINT_DP = 600'));
    expect(
      policy,
      contains('screenWidthDp < COMPACT_BREAKPOINT_DP ||'),
    );
    expect(
      policy,
      contains('screenHeightDp < COMPACT_BREAKPOINT_DP'),
    );
    expect(policy, contains('ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT'));
    expect(policy, contains('ActivityInfo.SCREEN_ORIENTATION_FULL_USER'));
    expect(
        policy, contains('ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE'));
    expect(
      gameActivity,
      matches(RegExp(r'restoreGameOrientation\(\)\s+}\s+when \(requestCode\)')),
    );
    expect(
      mainActivity,
      matches(RegExp(r'restoreLandscapeOrientation\(\)\s+val result')),
    );
    expect(
      'startActivityForResult('.allMatches(gameActivity),
      hasLength(1),
      reason: 'Every document picker should use launchDocumentPicker',
    );
  });

  test('Android exports reconcile MIME type with the suggested filename', () {
    final activity = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameActivity.kt',
    ).readAsStringSync();
    final contract = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/ExportDocumentSpec.kt',
    ).readAsStringSync();

    expect(activity,
        contains('type = exportMimeType(export.fileName, export.mimeType)'));
    expect(activity, isNot(contains('type = export.mimeType')));
    expect(activity,
        contains('MimeTypeMap.getSingleton().getMimeTypeFromExtension'));
    expect(contract, contains('application/vnd.gardendless.export'));
    expect(contract, contains('it != "text/plain"'));
    expect(contract, contains('it != "application/octet-stream"'));
  });
}
