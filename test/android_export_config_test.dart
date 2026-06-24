import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android registers a native game save exporter', () {
    final activity = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/MainActivity.kt',
    ).readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final build = File('android/app/build.gradle.kts').readAsStringSync();

    expect(build, contains('namespace = "io.github.dey410.gardendlessloader"'));
    expect(manifest, contains('android:name=".MainActivity"'));
    expect(activity,
        contains('io.github.dey410.gardendlessloader/game_file_exporter'));
    expect(activity, contains('exportFile'));
    expect(activity, contains('Intent.ACTION_CREATE_DOCUMENT'));
    expect(activity, contains('Intent.CATEGORY_OPENABLE'));
    expect(activity, contains('Intent.EXTRA_TITLE'));
    expect(activity, contains('type = mimeType'));
    expect(activity, contains('exportFileRequestCode'));
    expect(activity, contains('openOutputStream(uri, "w")'));
    expect(activity, contains('copyFileToUri'));
    expect(activity, contains('export_in_progress'));
    expect(activity, contains('export_picker_failed'));
    expect(activity, contains('export_cancelled'));
  });
}
