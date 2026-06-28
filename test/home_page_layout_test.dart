import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/constants.dart';
import 'package:gardendless_loader/src/services/about_content_service.dart';
import 'package:gardendless_loader/src/services/announcement_service.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:gardendless_loader/src/services/diagnostics_service.dart';
import 'package:gardendless_loader/src/services/update_check_service.dart';
import 'package:gardendless_loader/src/ui/home_page.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets(
    'home page enters immersive system UI',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final platformCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final controller = await _emptyController(tester);

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();

      final systemUiModeCalls = platformCalls
          .where((call) => call.method == 'SystemChrome.setEnabledSystemUIMode')
          .toList();

      expect(systemUiModeCalls, isNotEmpty);
      expect(systemUiModeCalls.last.arguments, 'SystemUiMode.immersiveSticky');
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  testWidgets(
    'home page presents a landscape launcher for current resources',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = await _readyController(tester);

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('资源'), findsOneWidget);
      expect(find.text('更新app'), findsNothing);
      expect(find.text('日志'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);
      expect(find.text('PvZ2 Gardendless'), findsOneWidget);
      expect(find.text('v0.1.0'), findsOneWidget);
      expect(find.byKey(const ValueKey('app-version-pill')), findsOneWidget);
      expect(find.text('资源根目录'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('资源校验'), findsOneWidget);
      expect(find.text('本地服务'), findsOneWidget);
      expect(find.text('诊断摘要'), findsOneWidget);
      expect(find.text('上次自检'), findsOneWidget);
      expect(find.text('最近错误'), findsOneWidget);
      expect(find.text('公告'), findsOneWidget);
      expect(find.text('开始游戏'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('launcher-navigation-rail')))
            .width,
        greaterThanOrEqualTo(150),
      );

      expect(find.text('导入来源'), findsNothing);
      expect(find.text('检查更新'), findsNothing);
      expect(find.text('本地服务器'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  testWidgets(
    'home page does not reserve horizontal camera safe area padding',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      tester.view.viewPadding = const FakeViewPadding(left: 80);
      tester.view.padding = const FakeViewPadding(left: 80);
      addTearDown(tester.view.reset);

      final controller = await _emptyController(tester);

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();

      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('launcher-navigation-rail')))
            .dx,
        closeTo(12, 0.1),
      );
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  testWidgets(
    'home page opens the about dialog from the lower-left navigation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = await _readyController(tester);

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();

      await tester.runAsync(controller.refreshAboutContent);
      await tester.pump();

      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('关于 GardendlessLoader'), findsOneWidget);
      expect(find.text('远端 JSON 关于内容'), findsOneWidget);
      expect(find.text('免责声明'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  testWidgets(
    'home page fits an Android landscape viewport without scrolling',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(915, 412);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = await _readyController(tester);

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();

      final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
      final visibleControls = <String, Finder>{
        'navigation rail':
            find.byKey(const ValueKey('launcher-navigation-rail')),
        'title': find.text('PvZ2 Gardendless'),
        'resource information': find.text('资源信息'),
        'quick actions': find.text('快捷操作'),
        'diagnostics summary': find.text('诊断摘要'),
        'announcement': find.text('公告'),
        'start game button': find.byKey(
          const ValueKey('home-start-game-button'),
        ),
      };
      for (final entry in visibleControls.entries) {
        final rect = tester.getRect(entry.value);
        expect(rect.left, greaterThanOrEqualTo(0), reason: entry.key);
        expect(rect.top, greaterThanOrEqualTo(0), reason: entry.key);
        expect(rect.right, lessThanOrEqualTo(viewport.width),
            reason: entry.key);
        expect(rect.bottom, lessThanOrEqualTo(viewport.height),
            reason: entry.key);
      }
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  testWidgets(
    'home page renders announcements inline without disclaimer controls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const trackedBilibiliUrl =
          'https://space.bilibili.com/523667580?spm_id_from=333.1007.0.0';
      final controller = await _readyController(
        tester,
        announcementService: _announcementService('''
{
  "schemaVersion": 1,
  "announcement": {
    "id": "notice-1",
    "title": "公告",
    "message": "只显示正文内容",
    "links": [
      {
        "label": "GitHub",
        "url": "$appGithubUrl"
      },
      {
        "label": "B站主页",
        "url": "$trackedBilibiliUrl"
      }
    ]
  }
}
'''),
      );
      await tester.runAsync(controller.refreshAnnouncement);

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('公告'), findsOneWidget);
      expect(find.text('只显示正文内容'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('announcement-content-box')),
        findsOneWidget,
      );
      final contentBox = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('announcement-content-box')),
      );
      final contentDecoration = contentBox.decoration as BoxDecoration;
      final contentBorder = contentDecoration.border! as Border;
      expect(
        contentBorder.top.color,
        isNot(const Color(0xff0a84ff).withValues(alpha: 0.24)),
      );
      expect(find.text('免责声明'), findsNothing);
      expect(
        find.byKey(ValueKey('announcement-link-$bilibiliHomeUrl')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('announcement-link-$trackedBilibiliUrl')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('announcement-link-$appGithubUrl')),
        findsOneWidget,
      );
      expect(find.byIcon(FontAwesomeIcons.bilibili.data), findsOneWidget);
      expect(find.byIcon(FontAwesomeIcons.github.data), findsOneWidget);
      expect(
        tester.getCenter(find.byIcon(FontAwesomeIcons.bilibili.data)).dx,
        lessThan(
            tester.getCenter(find.byIcon(FontAwesomeIcons.github.data)).dx),
      );
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  testWidgets(
    'home page separates resource information from quick actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = await _readyController(tester);

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();

      expect(find.text('资源信息'), findsOneWidget);
      expect(find.text('资源根目录'), findsOneWidget);
      expect(find.text('资源校验'), findsOneWidget);
      expect(find.text('本地服务'), findsOneWidget);
      expect(find.text('快捷操作'), findsOneWidget);

      final resourceInfoTop = tester.getTopLeft(find.text('资源信息')).dy;
      final quickActionsTop = tester.getTopLeft(find.text('快捷操作')).dy;

      expect(resourceInfoTop, lessThan(quickActionsTop));
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  testWidgets(
    'home page switches diagnostics into a launcher log view',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = await _readyController(tester);

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();

      await tester.tap(find.text('日志'));
      await tester.pump();

      expect(find.text('日志信息'), findsOneWidget);
      expect(find.text('复制日志信息'), findsOneWidget);
      expect(
        find.textContaining('[INFO] app', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('current.validation', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('资源信息'), findsNothing);
      expect(find.text('诊断摘要'), findsNothing);
      expect(find.text('开始游戏'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  testWidgets(
    'diagnostics log uses the installed package version',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final version = _pubspecVersion();
      final controller = await _readyController(
        tester,
        diagnosticsService: DiagnosticsService(
          appVersionLoader: () async => version,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();

      await tester.tap(find.text('日志'));
      await tester.pump();

      expect(
        find.textContaining('version="$version"', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('version="0.1.0"', findRichText: true),
        findsNothing,
      );
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  testWidgets(
    'diagnostics log view copies the full diagnostic snapshot',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final data = call.arguments as Map<Object?, Object?>;
          copiedText = data['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final controller = await _readyController(tester);

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();

      await tester.tap(find.text('日志'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('copy-diagnostics-button')));
      await tester.pump();

      expect(copiedText, contains('App version:'));
      expect(copiedText, contains('current validation:'));
      expect(copiedText, contains('serverStatus:'));
      expect(find.text('日志信息已复制'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  testWidgets(
    'home page copies the visible resource root',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final data = call.arguments as Map<Object?, Object?>;
          copiedText = data['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final controller = await _readyController(tester);

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('copy-resource-root-button')));
      await tester.pump();

      expect(copiedText, controller.userVisibleRoot);
      expect(find.text('资源根目录已复制'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  testWidgets(
    'home page disables launching until resources are imported',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = await _emptyController(tester);

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();

      final startButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('home-start-game-button')),
      );

      expect(find.text('需导入'), findsOneWidget);
      expect(find.text('需要导入资源'), findsOneWidget);
      expect(find.text('请先导入资源'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('app-version-pill'))).right,
        lessThan(tester.getRect(find.text('需导入')).left),
      );
      expect(startButton.onPressed, isNull);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}

Future<AppController> _readyController(
  WidgetTester tester, {
  AnnouncementService? announcementService,
  AboutContentService? aboutContentService,
  DiagnosticsService? diagnosticsService,
}) async {
  return (await tester.runAsync(() async {
    final root = await Directory.systemTemp.createTemp('gl_home_layout_');
    await _writeValidResource(Directory(p.join(root.path, 'current')));

    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      announcementService: announcementService,
      aboutContentService: aboutContentService ?? _aboutContentService(),
      diagnosticsService: diagnosticsService,
      updateCheckService: _noUpdateService(),
    );
    await controller.initialize();
    return controller;
  }))!;
}

Future<AppController> _emptyController(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final root = await Directory.systemTemp.createTemp('gl_home_empty_');
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: _noUpdateService(),
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

String _pubspecVersion() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match =
      RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(pubspec);
  if (match == null) {
    throw StateError('pubspec.yaml version is missing');
  }
  return match.group(1)!;
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
