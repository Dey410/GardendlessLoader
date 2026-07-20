import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
