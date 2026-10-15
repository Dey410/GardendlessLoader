import 'dart:io';

import 'package:path/path.dart' as p;

/// Fractional crop of the source texture, so it applies at any decode size.
class KeyArtCrop {
  const KeyArtCrop(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;
}

class KeyArtSource {
  const KeyArtSource({required this.file, required this.crop});

  final File file;
  final KeyArtCrop crop;
}

/// Finds promotional art inside the user's imported resource so the launcher
/// can show it without bundling any game asset of its own.
///
/// Gardendless ships the "It's About Time" key art as one Cocos texture that
/// stacks two 4:3 posters; the path has been identical in 0.13–0.15. The top
/// poster (2052×1538 at the top of a 2054×3084 texture) is used, inset a few
/// pixels to skip the atlas padding. Mobile packs may re-encode the texture,
/// so every common image extension is accepted.
class KeyArtLocator {
  const KeyArtLocator();

  static const _stem = 'assets/resources/native/1a/1aae2f737';
  static const _extensions = ['avif', 'webp', 'png', 'jpg', 'jpeg'];
  static const _topPoster = KeyArtCrop(
    4 / 2054,
    6 / 3084,
    2048 / 2054,
    1536 / 3084,
  );

  Future<KeyArtSource?> locate(Directory resourceRoot) async {
    for (final extension in _extensions) {
      final file = File(p.join(resourceRoot.path, '$_stem.$extension'));
      if (await file.exists() && await file.length() > 0) {
        return KeyArtSource(file: file, crop: _topPoster);
      }
    }
    return null;
  }
}
