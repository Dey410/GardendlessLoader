import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/constants.dart';
import 'package:gardendless_loader/src/services/about_content_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('downloads newer GitHub about content and replaces the cached json',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_about_content_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final cacheFile = File(p.join(root.path, 'about_content.json'));
    await cacheFile.writeAsString('''
{
  "schemaVersion": 1,
  "contentVersion": 1,
  "content": "旧的关于内容"
}
''');

    final service = AboutContentService(
      bundledJsonLoader: () async => '''
{
  "schemaVersion": 1,
  "contentVersion": 1,
  "content": "内置关于内容"
}
''',
      loader: (uri, timeout, maxBytes) async {
        expect(uri.toString(), remoteAboutContentUrl);
        expect(timeout, aboutContentTimeout);
        expect(maxBytes, aboutContentMaxBytes);
        return const AboutContentHttpResponse(
          statusCode: HttpStatus.ok,
          body: '''
{
  "schemaVersion": 1,
  "contentVersion": 2,
  "content": "新的关于内容"
}
''',
        );
      },
    );

    final content = await service.refreshContent(cacheFile: cacheFile);

    expect(content.contentVersion, 2);
    expect(content.content, '新的关于内容');
    final cached = await cacheFile.readAsString();
    expect(cached, contains('"contentVersion":2'));
    expect(cached, contains('"content":"新的关于内容"'));
  });

  test('keeps cached about content when remote json is not newer', () async {
    final root = await Directory.systemTemp.createTemp('gl_about_content_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final cacheFile = File(p.join(root.path, 'about_content.json'));
    const cachedJson = '''
{
  "schemaVersion": 1,
  "contentVersion": 3,
  "content": "缓存关于内容"
}
''';
    await cacheFile.writeAsString(cachedJson);

    final service = AboutContentService(
      bundledJsonLoader: () async => '''
{
  "schemaVersion": 1,
  "contentVersion": 1,
  "content": "内置关于内容"
}
''',
      loader: (uri, timeout, maxBytes) async => const AboutContentHttpResponse(
        statusCode: HttpStatus.ok,
        body: '''
{
  "schemaVersion": 1,
  "contentVersion": 2,
  "content": "不是新版"
}
''',
      ),
    );

    final content = await service.refreshContent(cacheFile: cacheFile);

    expect(content.contentVersion, 3);
    expect(content.content, '缓存关于内容');
    expect(await cacheFile.readAsString(), cachedJson);
  });

  test('seeds the one local cache from the bundle for offline refreshes',
      () async {
    final root = await Directory.systemTemp.createTemp('gl_about_content_');
    addTearDown(() => root.delete(recursive: true));
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
    final root = await Directory.systemTemp.createTemp('gl_about_content_');
    addTearDown(() => root.delete(recursive: true));
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
