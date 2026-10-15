import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/http_text.dart';

void main() {
  test('reads UTF-8 text and keeps the HTTP status', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.accepted;
      request.response.write('公告');
      await request.response.close();
    });

    final result =
        await loadHttpText(_uri(server), const Duration(seconds: 1), 16);

    expect(result.statusCode, HttpStatus.accepted);
    expect(result.body, '公告');
  });

  test('rejects oversized chunked text without a declared length', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.bufferOutput = false;
      request.response.add([1, 2, 3]);
      await request.response.flush();
      request.response.add([4, 5, 6]);
      await request.response.close();
    });

    await expectLater(loadHttpText(_uri(server), const Duration(seconds: 1), 4),
        throwsFormatException);
  });

  test('bounds the whole request including a response that never finishes',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {});

    await expectLater(
        loadHttpText(_uri(server), const Duration(milliseconds: 30), 16),
        throwsA(isA<TimeoutException>()));
  });
}

Uri _uri(HttpServer server) =>
    Uri.parse('http://127.0.0.1:${server.port}/text');
