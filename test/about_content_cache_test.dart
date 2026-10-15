import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/about_content_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('seeds the one local cache from the bundle for offline refreshes',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_about_retained_');
    final cache = File(p.join(root.path, 'about.json'));
    var bundleReads = 0;
    final service = AboutContentService(
      bundledJsonLoader: () async {
        bundleReads++;
        return '{"schemaVersion":1,"contentVersion":1,"content":"本地正文"}';
      },
      loader: (_, __, ___) async => throw const SocketException('offline'),
    );

    final initial = await service.refreshContent(cacheFile: cache);
    final refreshed = await service.refreshContent(cacheFile: cache);

    expect(initial.content, '本地正文');
    expect(refreshed.content, '本地正文');
    expect(bundleReads, 1);
    expect(await cache.exists(), isTrue);
  });

  test(
      'reports invalid bundled content instead of producing fake valid content',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_about_retained_');
    final service = AboutContentService(
      bundledJsonLoader: () async => 'invalid',
      loader: (_, __, ___) async => throw const SocketException('offline'),
    );

    await expectLater(
        service.refreshContent(
            cacheFile: File(p.join(root.path, 'about.json'))),
        throwsFormatException);
  });
}
