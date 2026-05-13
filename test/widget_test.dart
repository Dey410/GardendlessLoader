import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/main.dart';
import 'package:gardendless_loader/src/ui/game_page.dart';

void main() {
  test('app widget type is available', () {
    expect(const GardendlessLoaderApp(), isA<GardendlessLoaderApp>());
  });

  testWidgets('game viewport contains 16:9 content on iPad landscape',
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

    final size = tester.getSize(find.byKey(childKey));

    expect(size.width, 1024);
    expect(size.height, 576);
  });

  testWidgets('game viewport contains 16:9 content on ultrawide landscape',
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

    expect(size.width, 1920);
    expect(size.height, 1080);
  });
}
