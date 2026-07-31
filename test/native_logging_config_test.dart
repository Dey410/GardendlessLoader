import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all maintained platforms expose the same native logging channel', () {
    final android = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/logging/AppLogStore.kt',
    ).readAsStringSync();
    final ios = File('ios/Runner/AppLogStore.swift').readAsStringSync();
    final ohos = File(
      'ohos/entry/src/main/ets/plugins/AppLoggerPlugin.ets',
    ).readAsStringSync();

    for (final source in <String>[android, ios, ohos]) {
      expect(
        source,
        contains('io.github.dey410.gardendlessloader/app_logger'),
      );
      expect(source, contains('initialize'));
      expect(source, contains('emit'));
      expect(source, contains('snapshot'));
      expect(source, contains('flush'));
      expect(source, contains('deleteHistory'));
      expect(source, contains('endSession'));
    }
  });

  test('native stores enforce shared storage limits and JSONL sessions', () {
    final sources = <String>[
      File(
        'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/logging/AppLogStore.kt',
      ).readAsStringSync(),
      File('ios/Runner/AppLogStore.swift').readAsStringSync(),
      File('ohos/entry/src/main/ets/logging/AppLogStore.ets')
          .readAsStringSync(),
    ];

    for (final source in sources) {
      expect(source, contains(RegExp(r'2L? \* 1024L? \* 1024L?')));
      expect(source, contains(RegExp(r'10L? \* 1024L? \* 1024L?')));
      expect(source, contains('500'));
      expect(source, contains('1000'));
      expect(source, contains('.jsonl'));
      expect(source, contains('active-session.json'));
      expect(source, contains('previous_run_unclean_shutdown'));
      expect(source, contains('previousLastEvent'));
      expect(source, contains('app_session_ended'));
    }
    expect(sources[1], contains('1100'));
    expect(sources[2], contains('1100'));
  });

  test('all game hosts accept the shared JavaScript logging command', () {
    final sources = <String>[
      File(
        'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameBridge.kt',
      ).readAsStringSync(),
      File('ios/Runner/GameScriptBridge.swift').readAsStringSync(),
      File('ohos/entry/src/main/ets/game/GameBridge.ets').readAsStringSync(),
    ];
    for (final source in sources) {
      expect(source, contains('host:log'));
    }
    expect(sources[0], contains('bridge_message_invalid'));
    expect(
      '${sources[1]}${File('ios/Runner/GameViewController.swift').readAsStringSync()}',
      contains('bridge_message_invalid'),
    );
    expect(sources[2], contains('bridge_message_invalid'));

    final sharedScript =
        File('assets/game_bridge/logging.js').readAsStringSync();
    expect(sharedScript, contains('javascript_uncaught_error'));
    expect(sharedScript, contains('javascript_unhandled_rejection'));
    expect(sharedScript, contains('javascript_console'));
  });

  test('all native resource handlers log stable failure codes', () {
    final sources = <String>[
      File(
        'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameWebViewClient.kt',
      ).readAsStringSync(),
      File('ios/Runner/GameResourceSchemeHandler.swift').readAsStringSync(),
      File('ohos/entry/src/main/ets/game/NativeGameResourceHandler.ets')
          .readAsStringSync(),
    ];

    for (final source in sources) {
      expect(source, contains('resource_path_forbidden'));
      expect(source, contains('resource_file_not_found'));
      expect(source, contains('resource_read_failed'));
      expect(source, contains('resource_mime_mismatch'));
    }
  });

  test('Android logger does not depend on disabled BuildConfig generation', () {
    final source = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/logging/AppLogStore.kt',
    ).readAsStringSync();

    expect(source, isNot(contains('BuildConfig')));
    expect(source, contains('packageManager'));
  });

  test('iOS previous-session parsing keeps collection chains out of guard', () {
    final source = File('ios/Runner/AppLogStore.swift').readAsStringSync();

    expect(source, contains('let candidates = files.filter'));
    expect(source, contains('guard let file = candidates.max'));
  });

  test('iOS log cleanup uses explicit types and small metadata helpers', () {
    final source = File('ios/Runner/AppLogStore.swift').readAsStringSync();

    expect(source, contains('let discovered: [URL]'));
    expect(source, contains('let groupedFiles: [String: [URL]]'));
    expect(source, contains('private func modificationDate('));
    expect(source, contains('private func fileSize('));
  });

  test('HarmonyOS logging uses strict ArkTS-compatible data shapes', () {
    final logStore = File('ohos/entry/src/main/ets/logging/AppLogStore.ets')
        .readAsStringSync();
    final sources = <String>[
      logStore,
      File('ohos/entry/src/main/ets/game/GameBridge.ets').readAsStringSync(),
      File('ohos/entry/src/main/ets/game/NativeGameResourceHandler.ets')
          .readAsStringSync(),
      File('ohos/entry/src/main/ets/pages/GamePage.ets').readAsStringSync(),
    ].join('\n');

    expect(sources, contains('interface AppLogContext'));
    expect(logStore, isNot(contains('Record<string, Object>')));
    expect(sources, isNot(contains('appLogStore.emit({')));
    expect(sources, isNot(contains(RegExp(r'\bdelete\s+'))));
    expect(sources, isNot(contains('...details')));
  });
}
