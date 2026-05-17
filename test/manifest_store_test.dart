import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/manifest_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test('persists announcement dismissal fields', () async {
    final temp = await Directory.systemTemp.createTemp('gl_manifest_');
    final store = ManifestStore(File(p.join(temp.path, 'manifest.json')));

    await store.write(
      ResourceManifest.initial().copyWith(
        dismissedAnnouncementId: 'notice-1',
        dismissedAnnouncementLocalDate: '2026-05-17',
      ),
    );

    final manifest = await store.read();

    expect(manifest.dismissedAnnouncementId, 'notice-1');
    expect(manifest.dismissedAnnouncementLocalDate, '2026-05-17');
  });
}
