import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/update_check_service.dart';
import 'package:gardendless_loader/src/ui/verdant/verdant_home_page.dart';
import 'verdant_fixtures.dart';

Future<void> mount(WidgetTester tester, VerdantFixtureController c, {
  Size size = const Size(1440, 1000), double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
    home: HomePage(controller: c),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ready launch invokes the native controller once while pending', (tester) async {
    final c = VerdantFixtureController()..pendingLaunch = Completer<void>();
    await mount(tester, c);
    await tester.tap(find.byKey(const ValueKey('garden-launch')));
    await tester.pump();
    expect(c.launches, 1);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('garden-launch'))).onPressed, isNull);
    c.pendingLaunch!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('first-run primary action imports instead of pretending to launch', (tester) async {
    final c = VerdantFixtureController()..ready = false;
    await mount(tester, c);
    expect(find.textContaining('等待首次导入'), findsOneWidget);
    expect(find.text('2846'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('garden-launch')));
    await tester.pumpAndSettle();
    expect(c.imports, 1);
    expect(c.launches, 0);
  });

  testWidgets('resource actions retain controller wiring', (tester) async {
    final c = VerdantFixtureController();
    await mount(tester, c);
    await tester.tap(find.byKey(const ValueKey('garden-nav-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('garden-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新检查资源'));
    await tester.pumpAndSettle();
    expect(c.imports, 1);
    expect(c.refreshes, 1);
  });

  testWidgets('launch failure restores the button and reports an error', (tester) async {
    final c = VerdantFixtureController()..launchFailure = StateError('test launch failure');
    await mount(tester, c);
    await tester.tap(find.byKey(const ValueKey('garden-launch')));
    await tester.pump();
    expect(find.textContaining('test launch failure'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('garden-launch'))).onPressed, isNotNull);
  });

  testWidgets('settings update controller state rather than cosmetic local state', (tester) async {
    final c = VerdantFixtureController();
    await mount(tester, c);
    await tester.tap(find.byKey(const ValueKey('garden-nav-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('garden-auto-sun')));
    await tester.pumpAndSettle();
    expect(c.sun, isTrue);
  });

  testWidgets('history cleanup is confirmed and cancellation does not delete', (tester) async {
    final c = VerdantFixtureController();
    await mount(tester, c);
    await tester.tap(find.byKey(const ValueKey('garden-nav-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清理历史日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(c.deletions, 0);
    await tester.tap(find.text('清理历史日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认清理'));
    await tester.pumpAndSettle();
    expect(c.deletions, 1);
  });

  testWidgets('update center displays and defers a real update object', (tester) async {
    final c = VerdantFixtureController()..update = const UpdateInfo(
      currentVersion: '0.8.2', latestVersion: '0.8.3', tagName: 'v0.8.3',
      releaseUrl: 'https://github.com/Dey410/GardendlessLoader/releases/tag/v0.8.3',
      releaseName: 'Test release', releaseNotes: '', publishedAt: null,
    );
    await mount(tester, c);
    expect(find.text('有新的版本可以探索'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('garden-updates')));
    await tester.pumpAndSettle();
    expect(find.text('0.8.2 → 0.8.3'), findsOneWidget);
    await tester.tap(find.text('稍后提醒'));
    await tester.pumpAndSettle();
    expect(c.update, isNull);
  });

  testWidgets('failed import remains visible and can be dismissed', (tester) async {
    final c = VerdantFixtureController()..progress = const ImportProgress(
      phase: ImportPhase.failed, message: 'ZIP 校验失败',
    );
    await mount(tester, c);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('garden-import-progress')), 300,
      scrollable: find.descendant(of: find.byKey(const PageStorageKey('garden-page-0')), matching: find.byType(Scrollable)));
    expect(find.text('ZIP 校验失败'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭进度'));
    await tester.pumpAndSettle();
    expect(c.progress.phase, ImportPhase.idle);
  });

  testWidgets('busy controller disables mutations', (tester) async {
    final c = VerdantFixtureController()..loading = true;
    await mount(tester, c);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('garden-launch'))).onPressed, isNull);
  });

  for (final size in [const Size(667, 375), const Size(844, 390), const Size(390, 844), const Size(1194, 834), const Size(1440, 1000)]) {
    testWidgets('all pages avoid overflow at $size', (tester) async {
      await mount(tester, VerdantFixtureController(), size: size);
      expect(find.byKey(const ValueKey('garden-launch')).hitTestable(), findsOneWidget);
      for (var page = 0; page < 4; page++) {
        await tester.tap(find.byKey(ValueKey('garden-nav-$page')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'page $page at $size');
      }
    });
  }

  testWidgets('large accessibility text reflows without overflow', (tester) async {
    await mount(tester, VerdantFixtureController(), size: const Size(1194, 834), textScale: 2);
    for (var page = 0; page < 4; page++) {
      await tester.tap(find.byKey(ValueKey('garden-nav-$page')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'large text page $page');
    }
  });
}
