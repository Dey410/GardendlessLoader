import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/services/app_paths_service.dart';
import 'package:gardendless_loader/src/services/update_check_service.dart';
import 'package:gardendless_loader/src/ui/home_page.dart';

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
    );

    await tester.pumpWidget(
      MaterialApp(home: HomePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 v0.2.0'), findsOneWidget);
    expect(find.text('当前版本 0.1.0'), findsOneWidget);
    expect(find.text('查看 GitHub Release'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-dot')), findsOneWidget);

    await tester.tap(find.text('稍后提醒'));
    await tester.pump();

    expect(find.text('发现新版本 v0.2.0'), findsNothing);
    expect(find.byKey(const ValueKey('app-update-dot')), findsNothing);
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
        matching: find.text('v0.1.0'),
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
    );
    await controller.initialize();
    return controller;
  }))!;
}
