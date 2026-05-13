import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/constants.dart';
import 'package:gardendless_loader/src/services/local_game_server.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late LocalGameServer server;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gl_server_');
    await _writeFiles(temp);
    server = LocalGameServer();
  });

  tearDown(() async {
    await server.stop();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('serves GET and HEAD with no-store and expected MIME', () async {
    await server.start(root: temp);
    final client = HttpClient();

    final getRequest = await client.getUrl(Uri.parse('$localOrigin/index.html'));
    final getResponse = await getRequest.close();
    await getResponse.drain<void>();

    final headRequest = await client.headUrl(Uri.parse('$localOrigin/src/settings.json'));
    final headResponse = await headRequest.close();
    await headResponse.drain<void>();
    client.close(force: true);

    expect(getResponse.statusCode, HttpStatus.ok);
    expect(getResponse.headers.contentType?.mimeType, 'text/html');
    expect(getResponse.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    expect(headResponse.statusCode, HttpStatus.ok);
    expect(headResponse.headers.contentType?.mimeType, 'application/json');
  });

  test('rejects unsupported methods, missing files, directories, and traversal', () async {
    await server.start(root: temp);
    final client = HttpClient();

    final post = await (await client.postUrl(Uri.parse('$localOrigin/index.html'))).close();
    await post.drain<void>();
    final missing = await (await client.getUrl(Uri.parse('$localOrigin/nope.js'))).close();
    await missing.drain<void>();
    final directory = await (await client.getUrl(Uri.parse('$localOrigin/assets/'))).close();
    await directory.drain<void>();
    final traversal = await (await client.getUrl(Uri.parse('$localOrigin/../secret.txt'))).close();
    await traversal.drain<void>();
    client.close(force: true);

    expect(post.statusCode, HttpStatus.methodNotAllowed);
    expect(missing.statusCode, HttpStatus.notFound);
    expect(directory.statusCode, HttpStatus.notFound);
    expect(traversal.statusCode, HttpStatus.notFound);
  });

  test('selfCheck verifies real server paths and wasm MIME', () async {
    await File(p.join(temp.path, 'assets', 'game.wasm')).writeAsBytes([0, 97, 115, 109]);

    await server.selfCheck(root: temp);

    expect(server.isRunning, isTrue);
  });
}

Future<void> _writeFiles(Directory root) async {
  await Directory(p.join(root.path, 'assets')).create(recursive: true);
  await Directory(p.join(root.path, 'cocos-js')).create(recursive: true);
  await Directory(p.join(root.path, 'src')).create(recursive: true);
  await File(p.join(root.path, 'index.html')).writeAsString('<title>PvZ2 Gardendless</title>pvzge');
  await File(p.join(root.path, 'src', 'settings.json')).writeAsString('{"platform":"web-mobile"}');
  await File(p.join(root.path, 'src', 'import-map.json')).writeAsString('{}');
  await File(p.join(root.path, 'cocos-js', 'cc.js')).writeAsString('console.log("cc");');
}
