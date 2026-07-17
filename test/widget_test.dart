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
          child: ColoredBox(
            key: childKey,
            color: Colors.green,
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(childKey));

    expect(size.width, 1024);
    expect(size.height, 640);
  });

  testWidgets('game viewport clamps ultrawide landscape to 17:9',
      (tester) async {
    const childKey = Key('game-child');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(2400, 1080);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameViewportFrame(
          child: ColoredBox(
            key: childKey,
            color: Colors.green,
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(childKey));

    expect(size.width, 2040);
    expect(size.height, 1080);
  });

  testWidgets('game viewport fills screens within the adaptive ratio range',
      (tester) async {
    const childKey = Key('game-child');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameViewportFrame(
          child: ColoredBox(
            key: childKey,
            color: Colors.green,
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(childKey));

    expect(size.width, 1920);
    expect(size.height, 1080);
  });

  testWidgets('game viewport overlays watermark in content bottom-left',
      (tester) async {
    const childKey = Key('game-child');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameViewportFrame(
          child: ColoredBox(
            key: childKey,
            color: Colors.green,
          ),
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

  testWidgets('game menu exposes auto sunlight collection switch',
      (tester) async {
    bool? requestedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameMenuDialog(
            autoCollectSunlightEnabled: false,
            onAutoCollectSunlightChanged: (value) {
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

    expect(find.text('自动收集阳光'), findsOneWidget);

    await tester.tap(find.text('自动收集阳光'));
    await tester.pump();

    expect(requestedValue, isTrue);
  });

  testWidgets('game menu omits the removed force stretch switch',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameMenuDialog(
            autoCollectSunlightEnabled: false,
            onAutoCollectSunlightChanged: (_) {},
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
}
