import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/ui/verdant/verdant_home_page.dart';
import '../test/verdant_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Fonts are loaded from the CI machine, not copied into the application or
    // distributed in artifacts. Captures contain explicit fixture data only.
    for (final font in {
      'Noto Sans': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      'Noto Sans CJK SC': '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    }.entries) {
      final loader = FontLoader(font.key)
        ..addFont(File(font.value).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('capture native Verdant pages', (tester) async {
    tester.view.devicePixelRatio = 1;
    final boundary = GlobalKey();
    for (final spec in [
      ('home', 0, const Size(1440, 1000)),
      ('resources', 1, const Size(1440, 1150)),
      ('logs', 2, const Size(1440, 1000)),
      ('settings', 3, const Size(1440, 1150)),
      ('portrait', 0, const Size(390, 844)),
      ('landscape', 0, const Size(844, 390)),
    ]) {
      tester.view.physicalSize = spec.$3;
      final c = VerdantFixtureController();
      await tester.pumpWidget(RepaintBoundary(key: boundary,
        child: MaterialApp(debugShowCheckedModeBanner: false, home: HomePage(controller: c))));
      await tester.pumpAndSettle();
      if (spec.$2 != 0) {
        await tester.tap(find.byKey(ValueKey('garden-nav-${spec.$2}')));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('artifacts').create(recursive: true);
        await File('artifacts/verdant-${spec.$1}.png').writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
