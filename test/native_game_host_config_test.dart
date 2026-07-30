import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android game path is a standalone origin-scoped native WebView', () {
    final activity = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameActivity.kt',
    ).readAsStringSync();
    final bridge = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameBridge.kt',
    ).readAsStringSync();
    final viewport = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameViewportLayout.kt',
    ).readAsStringSync();
    final session = File(
      'android/app/src/main/kotlin/io/github/dey410/gardendlessloader/game/GameSessionCodec.kt',
    ).readAsStringSync();

    expect(activity, contains('class GameActivity : Activity()'));
    expect(activity, contains('setContentView(viewport)'));
    expect(viewport, contains('16.0 / 10.0'));
    expect(viewport, contains('17.0 / 9.0'));
    expect(activity, contains('addDocumentStartJavaScript'));
    expect(activity, contains('add("touch_patch.js")'));
    expect(activity, contains('add("auto_sun.js")'));
    expect(
      activity.indexOf('add("bootstrap.js")'),
      lessThan(activity.indexOf('add("auto_sun.js")')),
    );
    expect(
      activity,
      contains(
        '.put("autoCollectSunEnabled", session.autoCollectSunEnabled)',
      ),
    );
    expect(session, contains('val autoCollectSunEnabled: Boolean'));
    expect(
      session,
      contains(
        'autoCollectSunEnabled = json.getBoolean("autoCollectSunEnabled")',
      ),
    );
    expect(activity, contains('settings.allowFileAccess = false'));
    expect(bridge, contains('sourceOrigin.toString() != session.origin'));
    expect(bridge, contains('removeActive = false'));
    expect(activity, isNot(contains('HttpServer')));
  });

  test('iOS game path destroys Flutter and uses a custom WKURLSchemeHandler',
      () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final controller =
        File('ios/Runner/GameViewController.swift').readAsStringSync();
    final handler =
        File('ios/Runner/GameResourceSchemeHandler.swift').readAsStringSync();
    final session = File('ios/Runner/GameSession.swift').readAsStringSync();

    expect(delegate, contains('engine?.destroyContext()'));
    expect(controller, contains('WKUserScript('));
    expect(controller, contains('GameViewportView(webView: webView)'));
    expect(controller, contains('16.0 / 10.0'));
    expect(controller, contains('17.0 / 9.0'));
    expect(controller, contains('injectionTime: .atDocumentStart'));
    expect(controller, contains('"touch_patch.js"'));
    expect(controller, contains('"auto_sun.js"'));
    expect(
      controller.indexOf('"bootstrap.js"'),
      lessThan(controller.indexOf('"auto_sun.js"')),
    );
    expect(
      controller,
      contains('"autoCollectSunEnabled": session.autoCollectSunEnabled'),
    );
    expect(session, contains('let autoCollectSunEnabled: Bool'));
    expect(
      session,
      contains(
        'autoCollectSunEnabled = try json.requiredBool("autoCollectSunEnabled")',
      ),
    );
    expect(controller, contains('setURLSchemeHandler'));
    expect(handler, contains('WKURLSchemeHandler'));
    expect(handler, contains('attributes: .concurrent'));
    expect(session, contains('WKContentRuleListStore.default()'));
    expect(session, contains('["url-filter": "^http://"]'));
    expect(session, contains('"type": "ignore-previous-rules"'));
    expect(session, isNot(contains('unless-domain')));
    expect(
      File('ios/Runner/GameScriptBridge.swift').readAsStringSync(),
      contains('removeActive: false'),
    );
    expect(handler, isNot(contains('HttpServer')));
  });

  test('OpenHarmony game path is a native ArkWeb Ability with scheme takeover',
      () {
    final page =
        File('ohos/entry/src/main/ets/pages/GamePage.ets').readAsStringSync();
    final handler = File(
      'ohos/entry/src/main/ets/game/NativeGameResourceHandler.ets',
    ).readAsStringSync();
    final plugin = File(
      'ohos/entry/src/main/ets/plugins/GameHostPlugin.ets',
    ).readAsStringSync();
    final ability = File(
      'ohos/entry/src/main/ets/game/GameAbility.ets',
    ).readAsStringSync();
    final session = File(
      'ohos/entry/src/main/ets/game/GameSession.ets',
    ).readAsStringSync();

    expect(page, contains('.javaScriptOnDocumentStart'));
    expect(page, contains("'touch_patch.js'"));
    expect(page, contains("'auto_sun.js'"));
    expect(
      page.indexOf("'bootstrap.js'"),
      lessThan(page.indexOf("'auto_sun.js'")),
    );
    expect(
      page,
      contains('autoCollectSunEnabled: session.autoCollectSunEnabled'),
    );
    expect(session, contains('autoCollectSunEnabled: boolean;'));
    expect(session, contains('readonly autoCollectSunEnabled: boolean;'));
    expect(
      session,
      contains('this.autoCollectSunEnabled = value.autoCollectSunEnabled;'),
    );
    expect(page, contains('.fileAccess(false)'));
    expect(page, contains('const minimumAspectRatio = 16 / 10'));
    expect(page, contains('const maximumAspectRatio = 17 / 9'));
    expect(ability, contains('setWindowLayoutFullScreen(true)'));
    expect(ability, contains('setWindowSystemBarEnable([])'));
    expect(handler, contains("setWebSchemeHandler('http'"));
    expect(handler, contains("setWebSchemeHandler('https'"));
    expect(handler, contains('didReceiveResponseBody'));
    expect(handler, contains('await fs.read'));
    expect(handler, contains('active.cancelled = true'));
    expect(plugin, contains('context.terminateSelf()'));
    expect(
      File('ohos/entry/src/main/ets/game/GameBridge.ets').readAsStringSync(),
      contains('}, false);'),
    );
    expect(page, isNot(contains('FlutterPage')));
  });

  test('production graph has no Dart socket server or Flutter WebView package',
      () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final controller = File('lib/src/app_controller.dart').readAsStringSync();
    final home = File('lib/src/ui/home_page.dart').readAsStringSync();
    final constants = File('lib/src/constants.dart').readAsStringSync();
    final dartProduction = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(pubspec, isNot(contains('flutter_inappwebview')));
    expect(controller, isNot(contains('LocalGameServer')));
    expect(home, isNot(contains('GamePage')));
    expect(home, isNot(contains('InAppWebView')));
    expect(constants, isNot(contains('localServerPort')));
    expect(dartProduction, isNot(contains('HttpServer')));
    expect(File('lib/src/ui/game_page.dart').existsSync(), isFalse);
    expect(
        File('lib/src/services/local_game_server.dart').existsSync(), isFalse);
  });
}
