import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/game_host/game_host.dart';
import 'package:gardendless_loader/src/logging/app_logger.dart';
import 'package:gardendless_loader/src/logging/log_event_catalog.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/about_content_service.dart';
import 'package:gardendless_loader/src/services/announcement_service.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:gardendless_loader/src/services/app_settings_store.dart';
import 'package:gardendless_loader/src/services/game_update_check_service.dart';
import 'package:gardendless_loader/src/services/resource_picker_service.dart';
import 'package:gardendless_loader/src/services/sensor_housing_service.dart';
import 'package:gardendless_loader/src/services/update_check_service.dart';
import 'package:gardendless_loader/src/ui/home_page.dart';
import 'package:gardendless_loader/src/ui/theme/garden_theme.dart';
import 'package:path/path.dart' as p;

const _phone = Size(874, 402);
const _tablet = Size(1194, 834);
// The first frame on iPhone is laid out in portrait before rotation.
const _portrait = Size(402, 874);

void _useSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  if (size == _phone) {
    // Landscape iPhone with a Dynamic Island: insets on both long edges.
    tester.view.padding = const FakeViewPadding(
      left: 62,
      right: 62,
      bottom: 21,
    );
    addTearDown(tester.view.resetPadding);
  }
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(AppController controller,
    {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: buildGardenTheme(brightness),
    home: HomePage(controller: controller),
  );
}

Future<void> _openTab(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey('nav-$name')));
  await tester.pumpAndSettle();
}

void main() {
  for (final (label, size) in const [
    ('phone', _phone),
    ('tablet', _tablet),
    ('portrait', _portrait),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'every page lays out without overflow on $label '
          '(${brightness.name})', (tester) async {
        _useSize(tester, size);
        final controller = await _readyController(tester);
        await tester.pumpWidget(_app(controller, brightness: brightness));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('page-title')), findsOneWidget);
        for (final tab in const ['resources', 'logs', 'settings', 'game']) {
          await _openTab(tester, tab);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final edge in SensorHousingEdge.values) {
    testWidgets('phone keeps the notch inset only on the ${edge.name} edge',
        (tester) async {
      _useSize(tester, _phone);
      final housing = SensorHousingService()..value = edge;
      addTearDown(housing.dispose);
      final controller = await _readyController(tester);
      await tester.pumpWidget(MaterialApp(
        theme: buildGardenTheme(Brightness.dark),
        home: HomePage(controller: controller, sensorHousing: housing),
      ));
      await tester.pumpAndSettle();

      final rail = tester.getRect(
        find.byKey(const ValueKey('launcher-navigation-rail')),
      );
      final rightmost = tester.getRect(
        find.byKey(const ValueKey('announcement-button')),
      );
      final housingLeft = edge == SensorHousingEdge.left;
      // Compact rail is 76pt wide plus the left inset (62 or 20).
      expect(rail.width, housingLeft ? 62 + 76 : 20 + 76);
      // Right edge: inset (20 or 62) plus the 20pt compact gutter.
      expect(_phone.width - rightmost.right, housingLeft ? 40 : 82);
    });
  }

  testWidgets('ready resource offers one primary start action', (tester) async {
    _useSize(tester, _phone);
    final host = _RecordingGameHost();
    final controller = await _readyController(tester, gameHost: host);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('资源已就绪'), findsOneWidget);
    expect(find.text('PvZ2 Gardendless'), findsOneWidget);
    expect(find.text('加载器 v0.1.0'), findsOneWidget);
    expect(find.textContaining('版本 未知'), findsOneWidget);
    expect(find.textContaining('游戏 未知'), findsNothing);
    expect(find.byKey(const ValueKey('go-import-button')), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.text('开始游戏'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    expect(host.launchCount, 1);
  });

  testWidgets('empty state routes the user to the resource import',
      (tester) async {
    _useSize(tester, _phone);
    final controller = await _emptyController(tester);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await tester.runAsync(() => precacheImage(
          const ResizeImage(
            AssetImage('assets/artwork/launcher_poster.png'),
            width: 1600,
            allowUpscaling: false,
          ),
          tester.element(find.byType(HomePage)),
        ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('key-art')), findsOneWidget);

    expect(find.text('需要导入资源'), findsOneWidget);
    expect(find.text('开始游戏'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('go-import-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-zip-button')), findsOneWidget);
    expect(find.text('选择 ZIP 导入'), findsOneWidget);
    expect(find.text('无激活槽'), findsOneWidget);
  });

  testWidgets('launch preferences live in settings and persist',
      (tester) async {
    _useSize(tester, _tablet);
    final controller = await _readyController(tester);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('launch-preferences')), findsNothing);
    await _openTab(tester, 'settings');
    expect(find.byKey(const ValueKey('launch-preferences')), findsOneWidget);

    final autoCollect =
        find.byKey(const ValueKey('home-auto-collect-sun-switch'));
    await tester.ensureVisible(autoCollect);
    await tester.pumpAndSettle();
    expect(controller.autoCollectSunEnabled, isFalse);
    await tester.tap(autoCollect);
    await tester.pumpAndSettle();
    expect(controller.autoCollectSunEnabled, isTrue);

    final watermark = find.byKey(const ValueKey('home-watermark'));
    await tester.ensureVisible(watermark);
    await tester.pumpAndSettle();
    expect(controller.watermarkEnabled, isTrue);
    await tester.tap(watermark);
    await tester.pumpAndSettle();
    expect(controller.watermarkEnabled, isFalse);
  });

  testWidgets('appearance preferences are saved to app settings',
      (tester) async {
    _useSize(tester, _tablet);
    final controller = await _readyController(tester);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await _openTab(tester, 'settings');

    await tester.ensureVisible(
      find.byKey(const ValueKey('theme-preference-light')),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('theme-preference-light')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('reduce-motion-switch')),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('reduce-motion-switch')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(controller.themePreference, ThemePreference.light);
    expect(controller.reduceMotion, isTrue);
    final saved = await tester.runAsync(
      () => AppSettingsStore(controller.paths!.appSettingsFile).read(),
    );
    expect(saved!.themePreference, ThemePreference.light);
    expect(saved.reduceMotion, isTrue);
    expect(saved.watermarkEnabled, isTrue);
  });

  testWidgets('resource page copies the root and shows health details',
      (tester) async {
    _useSize(tester, _tablet);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final controller = await _readyController(tester);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await _openTab(tester, 'resources');

    expect(find.text('选择 ZIP 更新'), findsOneWidget);
    expect(find.text('校验通过'), findsOneWidget);
    expect(find.textContaining('无 HTTP Server'), findsOneWidget);
    expect(find.text('最近错误'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('copy-resource-root-button')));
    await tester.pump();
    expect(copied.single, controller.userVisibleRoot);
    expect(find.text('资源根目录已复制'), findsOneWidget);

    await tester.tap(find.text('技术详情'));
    await tester.pumpAndSettle();
    expect(find.text('generation'), findsOneWidget);
  });

  testWidgets(
    'active import shows progress and keeps a badge across navigation',
    (tester) async {
      _useSize(tester, _tablet);
      late AppController controller;
      late Completer<void> importerStarted;
      late Completer<void> releaseImporter;
      Future<void>? importFuture;
      await tester.runAsync(() async {
        importerStarted = Completer<void>();
        releaseImporter = Completer<void>();
        final root = await Directory.systemTemp.createTemp('gl_home_progress_');
        await _writeValidResource(Directory(p.join(root.path, 'current')));
        controller = AppController(
          gameHostPlatform: GameHostPlatform.android,
          pathsService:
              AppPathsService(rootOverride: root, platformName: 'test'),
          announcementService: _announcementService('null'),
          aboutContentService: _aboutContentService(),
          updateCheckService: _noUpdateService(),
          gameUpdateCheckService: _noGameUpdateService(),
          importAwakeModeSetter: (_) async {},
          resourcePickerService: ResourcePickerService(
            platformName: 'android',
            mobileZipImporter: ({required targetDirectory, onProgress}) async {
              onProgress?.call(const ImportProgress(
                phase: ImportPhase.extracting,
                copiedBytes: 256,
                totalBytes: 1024,
                copiedFiles: 2,
                totalFiles: 8,
                message: '正在解压资源',
              ));
              if (!importerStarted.isCompleted) importerStarted.complete();
              await releaseImporter.future;
              await _writeValidResource(Directory(targetDirectory));
              return targetDirectory;
            },
          ),
        );
        await controller.initialize();
      });
      addTearDown(() {
        if (!releaseImporter.isCompleted) releaseImporter.complete();
      });
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      await _openTab(tester, 'resources');
      expect(
          find.byKey(const ValueKey('resource-progress-region')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('import-zip-button')));
      await tester.runAsync(() async {
        importFuture = controller.importResources();
        await importerStarted.future;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('resource-progress-region')),
          findsOneWidget);
      expect(find.text('步骤 2/4 · 正在解压资源'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.byKey(const ValueKey('resource-progress-details')),
          findsOneWidget);
      expect(find.text('2/8'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('resource-progress-toggle')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('resource-progress-details')),
          findsNothing);

      await tester.tap(find.byKey(const ValueKey('nav-logs')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.byKey(const ValueKey('resource-nav-progress')), findsOneWidget);

      releaseImporter.complete();
      await tester.runAsync(() async => importFuture);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('resource-nav-progress')), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  testWidgets('logs page filters events and copies a single event',
      (tester) async {
    _useSize(tester, _tablet);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final logger = InMemoryAppLogger(
      appSessionId: 'app-session-test',
      source: LogSource.dart,
      eventSchemas: defaultLogEventSchemas,
    );
    final controller = await _readyController(tester, appLogger: logger);
    logger.emit(
      level: LogLevel.error,
      category: 'game.webview',
      event: 'webview_page_load_failed',
      outcome: LogOutcome.failed,
      code: 'webview_page_load_failed',
      gameSessionId: 'game-session-test',
      operationId: 'launch-operation-test',
      error: StateError('page failed'),
      stackTrace: StackTrace.current,
    );

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-logs')));
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 100),
        ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('log-overview')), findsOneWidget);
    expect(find.byKey(const ValueKey('log-operation-filter')), findsOneWidget);
    expect(find.text('webview_page_load_failed'), findsOneWidget);
    expect(find.text('游戏页面加载失败'), findsOneWidget);
    expect(find.text('game-session-test'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('log-errors-only-filter')));
    await tester.pumpAndSettle();
    expect(find.text('webview_page_load_failed'), findsOneWidget);
    expect(find.textContaining('resource_'), findsNothing);

    await tester.tap(find.byTooltip('复制单条事件 JSON'));
    await tester.pump();
    expect(copied.single, contains('webview_page_load_failed'));
    expect(find.text('单条事件 JSON 已复制'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('log-level-FATAL')));
    await tester.pumpAndSettle();
    expect(find.text('当前筛选条件下没有事件'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clear-log-view-filter')));
    await tester.pumpAndSettle();
    expect(find.text('webview_page_load_failed'), findsOneWidget);
  });

  testWidgets('deleting log history asks for confirmation first',
      (tester) async {
    _useSize(tester, _tablet);
    final controller = await _readyController(tester);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await _openTab(tester, 'logs');

    await tester.tap(find.byKey(const ValueKey('delete-log-history-button')));
    await tester.pumpAndSettle();
    expect(find.text('删除历史日志？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('删除历史日志？'), findsNothing);
  });

  group('announcement', () {
    const body = '{"schemaVersion":1,"announcement":{"id":"t1",'
        '"title":"测试公告","message":"完整的公告内容","links":['
        '{"label":"GitHub","url":"https://github.com/Dey410/GardendlessLoader"}'
        ']}}';

    Future<AppController> withAnnouncement(
      WidgetTester tester, {
      Directory? root,
    }) async {
      final controller = await _readyController(
        tester,
        root: root,
        announcementService: _announcementService(body),
      );
      await tester.runAsync(controller.refreshAnnouncement);
      return controller;
    }

    testWidgets('a new announcement pops up once and is remembered',
        (tester) async {
      _useSize(tester, _phone);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('gl_announcement_'),
      ))!;
      final controller = await withAnnouncement(tester, root: root);
      expect(controller.hasUnseenAnnouncement, isTrue);

      await tester.runAsync(() async {
        await tester.pumpWidget(_app(controller));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      final dialog = find.byKey(const ValueKey('announcement-dialog'));
      expect(dialog, findsOneWidget);
      expect(find.text('完整的公告内容'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('B站主页')),
        findsOneWidget,
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(controller.hasUnseenAnnouncement, isFalse);
      expect(find.byKey(const ValueKey('announcement-dot')), findsNothing);

      // A later launch with the same announcement stays quiet.
      final relaunched = await withAnnouncement(tester, root: root);
      expect(relaunched.hasUnseenAnnouncement, isFalse);
      await tester.pumpWidget(_app(relaunched));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
    });

    testWidgets('the top bar icon reopens the announcement', (tester) async {
      _useSize(tester, _tablet);
      final controller = await withAnnouncement(tester);
      await tester.runAsync(controller.markAnnouncementSeen);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      final dialog = find.byKey(const ValueKey('announcement-dialog'));
      expect(dialog, findsNothing);

      await tester.tap(find.byKey(const ValueKey('announcement-button')));
      await tester.pumpAndSettle();

      expect(dialog, findsOneWidget);
      expect(find.text('测试公告'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('GitHub')),
        findsOneWidget,
      );
    });

    testWidgets('the home page no longer carries an announcement card',
        (tester) async {
      _useSize(tester, _tablet);
      final controller = await withAnnouncement(tester);
      await tester.runAsync(controller.markAnnouncementSeen);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      expect(find.text('完整的公告内容'), findsNothing);
      expect(find.byKey(const ValueKey('announcement-button')), findsOneWidget);
    });
  });

  testWidgets('settings shows about content and the usage guide',
      (tester) async {
    _useSize(tester, _tablet);
    final controller = await _readyController(tester);
    await tester.runAsync(controller.refreshAboutContent);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await _openTab(tester, 'settings');

    expect(find.text('远端 JSON 关于内容'), findsOneWidget);
    expect(find.text('双指轻点'), findsOneWidget);
    expect(find.text('加载器 GitHub'), findsOneWidget);
    expect(find.text('上游游戏 GitHub'), findsOneWidget);
  });
}

Future<AppController> _readyController(
  WidgetTester tester, {
  Directory? root,
  AnnouncementService? announcementService,
  AboutContentService? aboutContentService,
  AppLogger? appLogger,
  bool gpNext = false,
  GameHost? gameHost,
}) async {
  return (await tester.runAsync(() async {
    final appRoot =
        root ?? await Directory.systemTemp.createTemp('gl_home_layout_');
    final resource = Directory(p.join(appRoot.path, 'current'));
    if (!await resource.exists()) await _writeValidResource(resource);
    if (gpNext) {
      await File(p.join(resource.path, 'index.html')).writeAsString('''
<html>
  <head><title>Cocos Creator | PvZ2_Gardendless</title></head>
  <body><script type="module" src="./assets/index-test.js"></script></body>
</html>
''');
      await File(p.join(resource.path, 'assets', 'index-test.js'))
          .writeAsString('''
console.info('GP-Next loading...');
window.gpNext = {};
function loadAllPatches() {}
import('./patcher-test.js');
import('./file-loader-test.js');
import('./js-mod-loader-test.js');
import('./config-test.js');
''');
    }

    final controller = AppController(
      gameHostPlatform: GameHostPlatform.android,
      pathsService:
          AppPathsService(rootOverride: appRoot, platformName: 'test'),
      announcementService: announcementService,
      aboutContentService: aboutContentService ?? _aboutContentService(),
      appLogger: appLogger,
      updateCheckService: _noUpdateService(),
      gameUpdateCheckService: _noGameUpdateService(),
      gameHost: gameHost,
    );
    await controller.initialize();
    return controller;
  }))!;
}

class _RecordingGameHost implements GameHost {
  int launchCount = 0;

  @override
  Future<void> launch(GameSession session) async {
    launchCount += 1;
  }
}

Future<AppController> _emptyController(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final root = await Directory.systemTemp.createTemp('gl_home_empty_');
    final controller = AppController(
      gameHostPlatform: GameHostPlatform.android,
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: _noUpdateService(),
      gameUpdateCheckService: _noGameUpdateService(),
    );
    await controller.initialize();
    return controller;
  }))!;
}

UpdateCheckService _noUpdateService() {
  return UpdateCheckService(
    currentVersion: '0.1.0',
    installedVersionLoader: () async => '0.1.0',
    loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
      statusCode: HttpStatus.ok,
      body: '''
{
  "tag_name": "v0.1.0",
  "html_url": "https://github.com/Dey410/GardendlessLoader/releases/tag/v0.1.0"
}
''',
    ),
  );
}

GameUpdateCheckService _noGameUpdateService() {
  return GameUpdateCheckService(
    loader: (uri, timeout, maxBytes) async => const GameUpdateCheckHttpResponse(
      statusCode: HttpStatus.ok,
      body: '[{"name":"0.11.0"}]',
    ),
  );
}

AnnouncementService _announcementService(String body) {
  return AnnouncementService(
    loader: (uri, timeout, maxBytes) async => AnnouncementHttpResponse(
      statusCode: HttpStatus.ok,
      body: body,
    ),
  );
}

AboutContentService _aboutContentService() {
  return AboutContentService(
    bundledJsonLoader: () async => '''
{
  "schemaVersion": 1,
  "contentVersion": 1,
  "content": "本地 JSON 关于内容"
}
''',
    loader: (uri, timeout, maxBytes) async => const AboutContentHttpResponse(
      statusCode: HttpStatus.ok,
      body: '''
{
  "schemaVersion": 1,
  "contentVersion": 2,
  "content": "远端 JSON 关于内容"
}
''',
    ),
  );
}

Future<void> _writeValidResource(Directory root) async {
  await Directory(p.join(root.path, 'assets')).create(recursive: true);
  await Directory(p.join(root.path, 'cocos-js')).create(recursive: true);
  await Directory(p.join(root.path, 'src')).create(recursive: true);
  await File(p.join(root.path, 'index.html')).writeAsString(
    '<html><head><title>PvZ2 Gardendless</title></head>'
    '<body>play.pvzge.com</body></html>',
  );
  await File(p.join(root.path, 'src', 'settings.json'))
      .writeAsString('{"platform":"web-mobile"}');
  await File(p.join(root.path, 'src', 'import-map.json')).writeAsString('{}');
  await File(p.join(root.path, 'cocos-js', 'cc.js'))
      .writeAsString('console.log("cc");');
}
