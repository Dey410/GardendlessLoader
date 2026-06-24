import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/game_download_service.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gl_download_');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('uses a safe suggested filename before content disposition', () {
    final name = downloadFileName(
      suggestedFilename: '../save:slot?.json',
      contentDisposition: "attachment; filename*=UTF-8''fallback.json",
      mimeType: 'application/json',
    );

    expect(name, 'save_slot_.json');
  });

  test('decodes RFC 5987 content disposition filename', () {
    final name = downloadFileName(
      contentDisposition:
          "attachment; filename*=UTF-8''%E5%AD%98%E6%A1%A3.json",
      mimeType: 'application/json',
    );

    expect(name, '存档.json');
  });

  test('prepares a data URL export and writes it to a temporary file',
      () async {
    GameDownloadFile? sharedFile;
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileSharer: (file, origin) async {
        sharedFile = file;
      },
    );

    final file = await service.exportDownload(
      request: GameDownloadRequest(
        uri: Uri.parse(
          'data:application/json;base64,${base64Encode(utf8.encode('{"ok":true}'))}',
        ),
        suggestedFilename: 'save.json',
      ),
      sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
    );

    expect(sharedFile?.path, file.path);
    expect(file.name, 'save.json');
    expect(file.mimeType, 'application/json');
    expect(await File(file.path).readAsString(), '{"ok":true}');
  });

  test('defaults JSON exports to the game json file format', () async {
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileSharer: (file, origin) async {},
    );

    final file = await service.prepareDownload(
      request: GameDownloadRequest(
        uri: Uri.parse(
          'data:;base64,${base64Encode(utf8.encode('{"coins":1}'))}',
        ),
      ),
    );

    expect(file.name, 'gardendless-export.json');
    expect(file.mimeType, 'application/json');
    expect(await File(file.path).readAsString(), '{"coins":1}');
  });

  test('renames generic JSON blob exports to json files', () async {
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileSharer: (file, origin) async {},
    );

    final file = await service.prepareDownload(
      request: GameDownloadRequest(
        uri: Uri.parse('blob:http://127.0.0.1:26410/export-id'),
        suggestedFilename: 'save.bin',
        mimeType: 'application/octet-stream',
      ),
      blobResolver: (_) async => GameDownloadPayload(
        bytes: utf8.encode('{"level":2}'),
        mimeType: 'application/octet-stream',
      ),
    );

    expect(file.name, 'save.json');
    expect(file.mimeType, 'application/json');
    expect(await File(file.path).readAsString(), '{"level":2}');
  });

  test('downloads allowed HTTP export content', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"slot":1}');
      await request.response.close();
    });
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileSharer: (file, origin) async {},
      isAllowedHttpUri: (uri) => uri.port == server.port,
    );

    final file = await service.prepareDownload(
      request: GameDownloadRequest(
        uri: Uri.parse('http://127.0.0.1:${server.port}/export'),
        suggestedFilename: 'slot.json',
      ),
    );

    expect(file.mimeType, 'application/json');
    expect(await File(file.path).readAsString(), '{"slot":1}');
  });

  test('rejects non-local HTTP export content', () async {
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileSharer: (file, origin) async {},
      isAllowedHttpUri: (_) => false,
    );

    expect(
      service.prepareDownload(
        request: GameDownloadRequest(
          uri: Uri.parse('https://example.com/export.json'),
        ),
      ),
      throwsA(isA<GameDownloadFailure>()),
    );
  });

  test('uses the WebView blob resolver for blob exports', () async {
    final service = GameDownloadService(
      temporaryDirectoryProvider: () async => temp,
      fileSharer: (file, origin) async {},
    );

    final file = await service.prepareDownload(
      request: GameDownloadRequest(
        uri: Uri.parse('blob:http://127.0.0.1:26410/export-id'),
        suggestedFilename: 'blob-save.txt',
      ),
      blobResolver: (_) async => GameDownloadPayload(
        bytes: utf8.encode('blob content'),
        mimeType: 'text/plain',
      ),
    );

    expect(file.name, 'blob-save.txt');
    expect(await File(file.path).readAsString(), 'blob content');
  });
}
