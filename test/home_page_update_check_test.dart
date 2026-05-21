import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/app_controller.dart';
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

    await tester.tap(find.text('稍后提醒'));
    await tester.pump();

    expect(find.text('发现新版本 v0.2.0'), findsNothing);
  });
}
