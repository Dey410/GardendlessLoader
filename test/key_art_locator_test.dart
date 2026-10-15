import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/key_art_locator.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('gl_key_art_');
  });

  tearDown(() => root.delete(recursive: true));

  Future<File> writeArt(String extension) async {
    final file = File(p.join(
      root.path,
      'assets/resources/native/1a/1aae2f737.$extension',
    ));
    await file.parent.create(recursive: true);
    return file.writeAsBytes(const [1, 2, 3]);
  }

  test('finds the key art texture in a Gardendless resource', () async {
    final art = await writeArt('avif');

    final source = await const KeyArtLocator().locate(root);

    expect(source?.file.path, art.path);
    expect(source!.crop.top, lessThan(source.crop.bottom));
    expect(source.crop.bottom, closeTo(0.5, 0.01));
  });

  test('accepts a mobile pack that re-encoded the texture', () async {
    final art = await writeArt('webp');

    final source = await const KeyArtLocator().locate(root);

    expect(source?.file.path, art.path);
  });

  test('returns nothing when the resource has no key art', () async {
    expect(await const KeyArtLocator().locate(root), isNull);
  });

  test('ignores an empty placeholder file', () async {
    final file = File(p.join(
      root.path,
      'assets/resources/native/1a/1aae2f737.png',
    ));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(const []);

    expect(await const KeyArtLocator().locate(root), isNull);
  });
}
