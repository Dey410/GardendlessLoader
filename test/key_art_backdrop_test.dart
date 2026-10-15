import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/ui/theme/garden_theme.dart';
import 'package:gardendless_loader/src/ui/widgets/key_art_backdrop.dart';

const _poster = ResizeImage(
  AssetImage('assets/artwork/launcher_poster.png'),
  width: 1600,
  allowUpscaling: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled poster decodes as one cropped image', () async {
    final bytes = await rootBundle.load('assets/artwork/launcher_poster.png');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    ));
    try {
      final frame = await codec.getNextFrame();
      try {
        expect(frame.image.width, 1600);
        expect(frame.image.height, 1198);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  });

  testWidgets('poster renders without imported resources and survives rebuilds',
      (tester) async {
    Widget app(Brightness brightness, double contentLeft) => MaterialApp(
          theme: buildGardenTheme(brightness),
          home: KeyArtBackdrop(contentLeft: contentLeft),
        );

    await tester.pumpWidget(app(Brightness.dark, 96));
    await tester.runAsync(() => precacheImage(
          _poster,
          tester.element(find.byType(KeyArtBackdrop)),
        ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('key-art')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(app(Brightness.light, 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('key-art')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
