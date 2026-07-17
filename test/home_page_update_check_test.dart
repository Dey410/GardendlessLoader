import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/constants.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:gardendless_loader/src/services/game_update_check_service.dart';
import 'package:gardendless_loader/src/services/update_check_service.dart';
import 'package:gardendless_loader/src/ui/home_page.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('home page automatically shows and defers release update',
      (tester) async {
    final controller = AppController(
      updateCheckService: UpdateCheckService(
        currentVersion: '0.1.0',
        installedVersionLoader: () async => '0.1.0',
        loader: (uri, timeout, maxBytes) async => const UpdateCheckHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{
  "tag_name": "v0.2.0",
  "html_url": "https://github.com/Dey410/GardendlessLoader/releases/tag/v0.2.0"
}
''',
        ),
      ),
      gameUpdateCheckService: _stableGameService(),
    );

    await tester.pumpWidget(
      MaterialApp(home: HomePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('更新中心'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-entry')), findsOneWidget);
    expect(find.text('0.1.0 → 0.2.0'), findsOneWidget);
    expect(find.text('网盘更新'), findsOneWidget);
    expect(find.text('查看 GitHub Release'), findsOneWidget);
    final cloudDrivePosition = tester.getTopLeft(find.text('网盘更新'));
    final githubPosition = tester.getTopLeft(find.text('查看 GitHub Release'));
    expect(
      cloudDrivePosition.dy < githubPosition.dy ||
          cloudDrivePosition.dy == githubPosition.dy &&
              cloudDrivePosition.dx < githubPosition.dx,
      isTrue,
    );
    expect(find.byKey(const ValueKey('app-update-dot')), findsOneWidget);

    await tester.tap(find.text('稍后提醒'));
    await tester.pump();

    expect(find.text('更新中心'), findsNothing);
    expect(find.byKey(const ValueKey('app-update-dot')), findsNothing);
  });

  test('cloud drive update url points to the Quark share', () {
    expect(
      appCloudDriveUpdateUrl,
      'https://pan.quark.cn/s/c3da839ca8b1?pwd=qLBU',
    );
  });

  testWidgets(
      'version pill manually checks updates and reports current version',
      (tester) async {
    final controller = await _initializedController(
      tester,
      UpdateCheckService(
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
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: HomePage(controller: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('app-version-pill')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(
          '加载器 v0.1.0 已是最新；游戏资源尚未导入，当前稳定版 0.11.0',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('version pill shows a spinner while checking updates',
      (tester) async {
    final response = Completer<UpdateCheckHttpResponse>();
    final controller = await _initializedController(
      tester,
      UpdateCheckService(
        currentVersion: '0.1.0',
        installedVersionLoader: () async => '0.1.0',
        loader: (uri, timeout, maxBytes) => response.future,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: HomePage(controller: controller)),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('app-update-spinner')), findsOneWidget);

    response.complete(
      const UpdateCheckHttpResponse(
        statusCode: HttpStatus.ok,
        body: '''
{
  "tag_name": "v0.1.0",
  "html_url": "https://github.com/Dey410/GardendlessLoader/releases/tag/v0.1.0"
}
''',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('app-update-spinner')), findsNothing);
  });

  testWidgets('game update has its own version dot and update center entry',
      (tester) async {
    late Directory root;
    late AppController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('gl_update_home_');
      await _writeValidGameResource(
        Directory(p.join(root.path, 'current')),
        version: '0.10.0',
      );
      controller = AppController(
        pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
        updateCheckService: UpdateCheckService(
          currentVersion: '0.4.8',
          installedVersionLoader: () async => '0.4.8',
          loader: (uri, timeout, maxBytes) async =>
              const UpdateCheckHttpResponse(
            statusCode: HttpStatus.ok,
            body: '''
{"tag_name":"v0.4.8","html_url":"https://github.com/Dey410/GardendlessLoader/releases/tag/v0.4.8"}
''',
          ),
        ),
        gameUpdateCheckService: GameUpdateCheckService(
          loader: (uri, timeout, maxBytes) async =>
              const GameUpdateCheckHttpResponse(
            statusCode: HttpStatus.ok,
            body: '[{"name":"0.11.0"}]',
          ),
        ),
      );
      await controller.initialize();
    });
    addTearDown(() => root.delete(recursive: true));

    await tester
        .pumpWidget(MaterialApp(home: HomePage(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('加载器 v0.4.8'), findsOneWidget);
    expect(find.text('游戏 v0.10.0'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-dot')), findsNothing);
    expect(find.byKey(const ValueKey('game-update-dot')), findsOneWidget);
    expect(find.text('更新中心'), findsOneWidget);
    expect(find.byKey(const ValueKey('game-update-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-entry')), findsNothing);
    expect(find.text('0.10.0 → 0.11.0'), findsOneWidget);
    expect(find.text('获取游戏资源'), findsOneWidget);
    expect(find.text('查看游戏 GitHub'), findsOneWidget);

    await tester.tap(find.text('稍后提醒'));
    await tester.pump();

    expect(find.byKey(const ValueKey('game-update-dot')), findsNothing);
    expect(find.text('更新中心'), findsNothing);
  });
}

Future<AppController> _initializedController(
  WidgetTester tester,
  UpdateCheckService updateCheckService,
) async {
  return (await tester.runAsync(() async {
    final root = await Directory.systemTemp.createTemp('gl_update_home_');
    final controller = AppController(
      pathsService: AppPathsService(rootOverride: root, platformName: 'test'),
      updateCheckService: updateCheckService,
      gameUpdateCheckService: _stableGameService(),
    );
    await controller.initialize();
    return controller;
  }))!;
}

GameUpdateCheckService _stableGameService() {
  return GameUpdateCheckService(
    loader: (uri, timeout, maxBytes) async => const GameUpdateCheckHttpResponse(
      statusCode: HttpStatus.ok,
      body: '[{"name":"0.11.0"}]',
    ),
  );
}

Future<void> _writeValidGameResource(
  Directory root, {
  required String version,
}) async {
  await Directory(p.join(root.path, 'assets')).create(recursive: true);
  await Directory(p.join(root.path, 'cocos-js')).create(recursive: true);
  await Directory(p.join(root.path, 'src')).create(recursive: true);
  await File(p.join(root.path, 'index.html')).writeAsString(
    '<title>PvZ2 Gardendless Online | $version</title>play.pvzge.com',
  );
  await File(p.join(root.path, 'src', 'settings.json'))
      .writeAsString('{"platform":"web-mobile"}');
  await File(p.join(root.path, 'src', 'import-map.json')).writeAsString('{}');
}
