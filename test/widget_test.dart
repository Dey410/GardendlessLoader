import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/main.dart';
import 'package:gardendless_loader/src/ui/game_page.dart';

void main() {
  test('app widget type is available', () {
    expect(const GardendlessLoaderApp(), isA<GardendlessLoaderApp>());
  });

  testWidgets('game viewport clamps iPad landscape to 16:10', (tester) async {
    const childKey = Key('game-child');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameViewportFrame(
          child: ColoredBox(key: childKey, color: Colors.green),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(childKey));

    expect(size.width, 1024);
    expect(size.height, 640);
  });

  testWidgets('game viewport clamps ultrawide landscape to 17:9', (
    tester,
  ) async {
    const childKey = Key('game-child');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(2400, 1080);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameViewportFrame(
          child: ColoredBox(key: childKey, color: Colors.green),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(childKey));

    expect(size.width, 2040);
    expect(size.height, 1080);
  });

  testWidgets('game viewport fills screens within the adaptive ratio range', (
    tester,
  ) async {
    const childKey = Key('game-child');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameViewportFrame(
          child: ColoredBox(key: childKey, color: Colors.green),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(childKey));

    expect(size.width, 1920);
    expect(size.height, 1080);
  });

  testWidgets('game viewport overlays watermark in content bottom-left', (
    tester,
  ) async {
    const childKey = Key('game-child');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameViewportFrame(
          child: ColoredBox(key: childKey, color: Colors.green),
        ),
      ),
    );

    final childRect = tester.getRect(find.byKey(childKey));
    final watermarkRect = tester.getRect(find.text(gameWatermarkText));

    expect(watermarkRect.left, greaterThanOrEqualTo(childRect.left + 10));
    expect(watermarkRect.bottom, lessThanOrEqualTo(childRect.bottom - 8));
    expect(find.byType(GameWatermark), findsOneWidget);
    final ignorePointer = tester.widget<IgnorePointer>(
      find.byKey(const ValueKey('game-watermark-ignore-pointer')),
    );

    expect(ignorePointer.ignoring, isTrue);
  });

  testWidgets('game viewport hides the watermark when disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameViewportFrame(
          showWatermark: false,
          child: ColoredBox(color: Colors.green),
        ),
      ),
    );

    expect(find.text(gameWatermarkText), findsNothing);
  });

  testWidgets('game menu exposes auto sunlight collection switch', (
    tester,
  ) async {
    bool? requestedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameMenuDialog(
            autoCollectSunlightEnabled: false,
            onAutoCollectSunlightChanged: (value) {
              requestedValue = value;
            },
            watermarkEnabled: true,
            onWatermarkChanged: (_) {},
            onContinue: () {},
            onReturnHome: () {},
            onReload: () {},
            onDiagnostics: () {},
          ),
        ),
      ),
    );

    expect(find.text('自动收集阳光'), findsOneWidget);

    await tester.tap(find.text('自动收集阳光'));
    await tester.pump();

    expect(requestedValue, isTrue);
  });

  testWidgets('game menu exposes the watermark as the second switch', (
    tester,
  ) async {
    bool? requestedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameMenuDialog(
            autoCollectSunlightEnabled: false,
            onAutoCollectSunlightChanged: (_) {},
            watermarkEnabled: true,
            onWatermarkChanged: (value) {
              requestedValue = value;
            },
            onContinue: () {},
            onReturnHome: () {},
            onReload: () {},
            onDiagnostics: () {},
          ),
        ),
      ),
    );

    expect(find.text('显示水印'), findsOneWidget);
    expect(find.text('在游戏画面左下角显示防倒卖提示'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('自动收集阳光')).dy,
      lessThan(tester.getTopLeft(find.text('显示水印')).dy),
    );

    await tester.tap(find.text('显示水印'));
    await tester.pump();

    expect(requestedValue, isFalse);
  });

  testWidgets('game menu hides auto sunlight collection for GP-Next', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameMenuDialog(
            autoCollectSunlightEnabled: false,
            onAutoCollectSunlightChanged: (_) {},
            watermarkEnabled: true,
            onWatermarkChanged: (_) {},
            showGpNext: true,
            onOpenGpNext: () {},
            onContinue: () {},
            onReturnHome: () {},
            onReload: () {},
            onDiagnostics: () {},
          ),
        ),
      ),
    );

    expect(find.text('自动收集阳光'), findsNothing);
    expect(find.text('每 1.5 秒自动按下 A 键'), findsNothing);
    expect(find.text('显示水印'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('game menu omits the removed force stretch switch', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameMenuDialog(
            autoCollectSunlightEnabled: false,
            onAutoCollectSunlightChanged: (_) {},
            watermarkEnabled: true,
            onWatermarkChanged: (_) {},
            onContinue: () {},
            onReturnHome: () {},
            onReload: () {},
            onDiagnostics: () {},
          ),
        ),
      ),
    );

    expect(find.text('强制拉伸'), findsNothing);
  });

  testWidgets('game menu only exposes GP-Next for a detected build', (
    tester,
  ) async {
    var openCount = 0;

    Widget buildMenu({required bool showGpNext, VoidCallback? onOpenGpNext}) {
      return MaterialApp(
        home: Scaffold(
          body: GameMenuDialog(
            autoCollectSunlightEnabled: false,
            onAutoCollectSunlightChanged: (_) {},
            watermarkEnabled: true,
            onWatermarkChanged: (_) {},
            showGpNext: showGpNext,
            onOpenGpNext: onOpenGpNext,
            onContinue: () {},
            onReturnHome: () {},
            onReload: () {},
            onDiagnostics: () {},
          ),
        ),
      );
    }

    await tester.pumpWidget(buildMenu(showGpNext: false));
    expect(find.text('打开 GP-Next'), findsNothing);

    await tester.pumpWidget(
      buildMenu(showGpNext: true, onOpenGpNext: () => openCount += 1),
    );
    await tester.tap(find.byKey(const ValueKey('open-gp-next-button')));
    expect(openCount, 1);
  });

  testWidgets('unsupported GP-Next is visible but disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameMenuDialog(
            autoCollectSunlightEnabled: false,
            onAutoCollectSunlightChanged: (_) {},
            watermarkEnabled: true,
            onWatermarkChanged: (_) {},
            showGpNext: true,
            gpNextUnavailableReason: '暂不支持 GP-Next 9.9.9',
            onContinue: () {},
            onReturnHome: () {},
            onReload: () {},
            onDiagnostics: () {},
          ),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('open-gp-next-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('暂不支持 GP-Next 9.9.9'), findsOneWidget);
  });

  testWidgets('double tapping the game menu backdrop continues the game', (
    tester,
  ) async {
    var continueCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: GameMenuOverlay(
          onContinue: () {
            continueCount += 1;
          },
          child: const SizedBox(width: 300, height: 200),
        ),
      ),
    );

    await tester.tapAt(const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 100));

    expect(continueCount, 1);
  });

  testWidgets('double tapping inside the game menu keeps it open', (
    tester,
  ) async {
    var continueCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: GameMenuOverlay(
          onContinue: () {
            continueCount += 1;
          },
          child: const Material(
            key: ValueKey('game-menu-panel'),
            child: SizedBox(width: 300, height: 200),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('game-menu-panel')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('game-menu-panel')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(continueCount, 0);
  });

  testWidgets('game menu uses a responsive 480 pixel glass panel', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameMenuDialog(
            autoCollectSunlightEnabled: false,
            onAutoCollectSunlightChanged: (_) {},
            watermarkEnabled: true,
            onWatermarkChanged: (_) {},
            onContinue: () {},
            onReturnHome: () {},
            onReload: () {},
            onDiagnostics: () {},
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('game-menu-panel'))).width,
      480,
    );

    tester.view.physicalSize = const Size(400, 300);
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const ValueKey('game-menu-panel'))).width,
      lessThanOrEqualTo(360),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('game menu presents primary secondary and warning actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameMenuDialog(
            autoCollectSunlightEnabled: false,
            onAutoCollectSunlightChanged: (_) {},
            watermarkEnabled: true,
            onWatermarkChanged: (_) {},
            onContinue: () {},
            onReturnHome: () {},
            onReload: () {},
            onDiagnostics: () {},
          ),
        ),
      ),
    );

    final filledButtons = find.byWidgetPredicate(
      (widget) => widget is FilledButton,
    );
    final outlinedButtons = find.byWidgetPredicate(
      (widget) => widget is OutlinedButton,
    );

    expect(
      find.descendant(
        of: filledButtons,
        matching: find.byIcon(Icons.play_arrow_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: filledButtons,
        matching: find.byIcon(Icons.refresh_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: filledButtons,
        matching: find.byIcon(Icons.terminal_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: outlinedButtons,
        matching: find.byIcon(Icons.home_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('game menu glass surface follows light and dark themes', (
    tester,
  ) async {
    Widget buildMenu(Brightness brightness) {
      return MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(
          body: GameMenuDialog(
            autoCollectSunlightEnabled: false,
            onAutoCollectSunlightChanged: (_) {},
            watermarkEnabled: true,
            onWatermarkChanged: (_) {},
            onContinue: () {},
            onReturnHome: () {},
            onReload: () {},
            onDiagnostics: () {},
          ),
        ),
      );
    }

    await tester.pumpWidget(buildMenu(Brightness.light));
    final lightDecoration = tester
        .widget<DecoratedBox>(
          find.byKey(const ValueKey('game-menu-glass-surface')),
        )
        .decoration as BoxDecoration;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(buildMenu(Brightness.dark));
    final darkDecoration = tester
        .widget<DecoratedBox>(
          find.byKey(const ValueKey('game-menu-glass-surface')),
        )
        .decoration as BoxDecoration;

    expect(lightDecoration.gradient, isNot(darkDecoration.gradient));
  });
}
