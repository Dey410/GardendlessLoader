import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:gardendless_loader/src/services/update_check_service.dart';
import 'package:gardendless_loader/src/ui/home_page.dart';
import 'package:path/path.dart' as p;

void main() {
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
      expect(find.text('更新'), findsOneWidget);
      expect(find.text('诊断'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);
      expect(find.text('PvZ2 Gardendless'), findsOneWidget);
      expect(find.text('资源根目录'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('资源校验'), findsOneWidget);
      expect(find.text('本地服务'), findsOneWidget);
      expect(find.text('诊断摘要'), findsOneWidget);
      expect(find.text('上次自检'), findsOneWidget);
      expect(find.text('最近错误'), findsOneWidget);
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

      await tester.tap(find.widgetWithText(TextButton, '复制'));
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
      expect(startButton.onPressed, isNull);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}

Future<AppController> _readyController(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final root = await Directory.systemTemp.createTemp('gl_home_layout_');
    await _writeValidResource(Directory(p.join(root.path, 'current')));

    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
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
