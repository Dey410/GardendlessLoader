import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/manifest_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test('does not persist legacy announcement dismissal fields', () async {
    final temp = await Directory.systemTemp.createTemp('gl_manifest_');
    final manifestFile = File(p.join(temp.path, 'manifest.json'));
    final store = ManifestStore(manifestFile);

    await manifestFile.writeAsString('''
{
  "schemaVersion": 1,
  "announcement": {
    "dismissedId": "notice-1",
    "dismissedLocalDate": "2026-05-17"
  }
}
''');

    final manifest = await store.read();
    await store.write(manifest);

    expect(await manifestFile.readAsString(), isNot(contains('announcement')));
    expect(await manifestFile.readAsString(), isNot(contains('dismissedId')));
  });
}
